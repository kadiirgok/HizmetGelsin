using Berbergelsin.Api.Auth;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Dtos;
using Berbergelsin.Api.Entities;
using Berbergelsin.Api.Enums;
using Berbergelsin.Api.Services;
using Berbergelsin.Api.Validation;
using FirebaseAdmin.Auth;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace Berbergelsin.Api.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly OtpService _otpService;
    private readonly TwilioVerifyService _twilioVerify;
    private readonly TokenService _tokenService;
    private readonly IConfiguration _config;
    private readonly IHostEnvironment _environment;
    private readonly IFirebaseIdTokenVerifier _firebaseVerifier;

    public AuthController(AppDbContext db, OtpService otpService, TwilioVerifyService twilioVerify,
        TokenService tokenService, IConfiguration config, IHostEnvironment environment,
        IFirebaseIdTokenVerifier firebaseVerifier)
    {
        _db = db;
        _otpService = otpService;
        _twilioVerify = twilioVerify;
        _tokenService = tokenService;
        _config = config;
        _environment = environment;
        _firebaseVerifier = firebaseVerifier;
    }

    private string? ClientIp =>
        Request.Headers["CF-Connecting-IP"].FirstOrDefault()
        ?? HttpContext.Connection.RemoteIpAddress?.ToString();

    /// <summary>Bootstrap admin: yapılandırılmış özel numara (örn. 11 hane "1") girildiğinde
    /// OTP sorulmadan doğrudan admin oturumu açar. Numara boşsa özellik kapalıdır.</summary>
    [HttpPost("admin-bootstrap")]
    [AllowAnonymous]
    [EnableRateLimiting("otp")]
    public async Task<IActionResult> AdminBootstrap(SendOtpRequest request, CancellationToken ct)
    {
        if (!_environment.IsDevelopment()) return NotFound();
        var bootstrapPhone = _config["Seed:AdminBootstrapPhone"];
        if (string.IsNullOrWhiteSpace(bootstrapPhone))
            return NotFound();

        var digits = new string((request.Phone ?? "").Where(char.IsDigit).ToArray());
        if (digits != bootstrapPhone)
            return Unauthorized(new { message = "Geçersiz numara." });

        var user = await _db.Users.Include(u => u.BarberProfile)
            .FirstOrDefaultAsync(u => u.PhoneNumber == bootstrapPhone, ct);
        if (user == null)
        {
            user = new User
            {
                Id = Guid.NewGuid(),
                PhoneNumber = bootstrapPhone,
                Role = UserRole.Admin,
                FirstName = "Admin",
                OnboardingCompleted = true,
                CreatedAt = DateTime.UtcNow
            };
            _db.Users.Add(user);
            await _db.SaveChangesAsync(ct);
        }

        if (user.AccountStatus is not (AccountStatus.Active or AccountStatus.Pending))
            return StatusCode(403, new { code = AccountStatusCode(user.AccountStatus) });
        else if (user.Role != UserRole.Admin)
        {
            user.Role = UserRole.Admin;
            user.OnboardingCompleted = true;
            user.TokenVersion++;
            foreach (var token in await _db.RefreshTokens.Where(t => t.UserId == user.Id && t.RevokedAt == null).ToListAsync(ct))
                token.RevokedAt = DateTime.UtcNow;
            await _db.SaveChangesAsync(ct);
        }

        var accessToken = _tokenService.CreateAccessToken(user, user.BarberProfile?.Id);
        var refreshToken = await _tokenService.CreateRefreshTokenAsync(user, ClientIp, ct);
        return Ok(new AuthResponse(accessToken, refreshToken, ToUserDto(user)));
    }

    [HttpPost("phone/send")]
    [AllowAnonymous]
    [EnableRateLimiting("otp")]
    public async Task<IActionResult> SendPhoneOtp(SendOtpRequest request, CancellationToken ct)
    {
        var phone = PhoneNormalizer.Normalize(request.Phone);
        if (phone == null)
            return BadRequest(new { message = "Geçerli bir telefon numarası girin (5XX XXX XX XX)." });

        var sendResult = await _otpService.SendOtpAsync(phone, ClientIp, ct: ct);

        return sendResult switch
        {
            OtpService.SendResult.Sent => Ok(new { message = "Doğrulama kodu gönderildi." }),
            OtpService.SendResult.TooSoon => StatusCode(429, new { message = "Yeni kod için lütfen bekleyin.", code = "auth_otp_too_soon" }),
            OtpService.SendResult.TooMany => StatusCode(429, new { message = "Çok fazla deneme yaptınız.", code = "auth_otp_too_many" }),
            OtpService.SendResult.SmsFailed => StatusCode(500, new { message = "SMS gönderilemedi. Lütfen tekrar deneyin.", code = "auth_otp_failed" }),
            _ => StatusCode(500, new { message = "Kod gönderilemedi.", code = "auth_otp_failed" })
        };
    }

    [HttpPost("phone/verify")]
    [AllowAnonymous]
    [EnableRateLimiting("otp")]
    public async Task<IActionResult> VerifyPhoneOtp(VerifyOtpRequest request, CancellationToken ct)
    {
        var phone = PhoneNormalizer.Normalize(request.Phone);
        if (phone == null)
            return BadRequest(new { message = "Geçerli bir telefon numarası girin (5XX XXX XX XX)." });

        if (string.IsNullOrWhiteSpace(request.Code) || request.Code.Length != 6)
            return BadRequest(new { message = "6 haneli doğrulama kodunu girin." });

        var reqRole = ResolveRequestedRole(request.Role);
        if (!IsKnownRole(request.Role))
            return BadRequest(new { message = "Geçersiz rol.", code = "auth_invalid_role" });

        // Development: OTP doğrulamasını atla
        var isDev = _environment.IsDevelopment();

        if (!isDev)
        {
            var verifyResult = await _otpService.TryConsumeOtpAsync(phone, request.Code, ct: ct);
            if (verifyResult != OtpService.VerifyResult.Success)
            {
                return verifyResult switch
                {
                    OtpService.VerifyResult.Expired => BadRequest(new { message = "Kodun süresi dolmuş.", code = "auth_otp_expired" }),
                    OtpService.VerifyResult.TooManyAttempts => StatusCode(429, new { message = "Çok fazla hatalı deneme.", code = "auth_otp_blocked" }),
                    _ => BadRequest(new { message = "Geçersiz kod.", code = "auth_otp_invalid" })
                };
            }
        }

        // Telefon + Rol ile kullanıcı ara
        var user = await _db.Users.Include(u => u.BarberProfile)
            .FirstOrDefaultAsync(u => u.PhoneNumber == phone && u.Role == reqRole, ct);

        if (user == null)
        {
            // Aynı telefon farklı rol ile var mı?
            var phoneUser = await _db.Users
                .FirstOrDefaultAsync(u => u.PhoneNumber == phone, ct);
            if (phoneUser != null)
                return StatusCode(409, new { code = "auth_role_mismatch", message = "Bu telefon farklı bir rolle kayıtlı." });

            // Yeni kullanıcı oluştur
            user = new User
            {
                Id = Guid.NewGuid(),
                PhoneNumber = phone,
                Role = reqRole,
                IsPhoneVerified = true,
                AccountStatus = AccountStatus.Active,
                CreatedAt = DateTime.UtcNow
            };

            if (reqRole == UserRole.Berber)
            {
                user.BarberProfile = new BarberProfile
                {
                    Id = Guid.NewGuid(),
                    UserId = user.Id,
                    Status = BarberStatus.Onboarding,
                    CreatedAt = DateTime.UtcNow
                };
            }

            _db.Users.Add(user);
            await _db.SaveChangesAsync(ct);
        }
        else
        {
            if (user.AccountStatus != AccountStatus.Active)
                return Unauthorized(new { code = AccountStatusCode(user.AccountStatus) });

            user.IsPhoneVerified = true;
            await _db.SaveChangesAsync(ct);
        }

        var accessToken = _tokenService.CreateAccessToken(user, user.BarberProfile?.Id);
        var refreshToken = await _tokenService.CreateRefreshTokenAsync(user, ClientIp, ct);

        return Ok(new AuthResponse(accessToken, refreshToken, ToUserDto(user)));
    }

    // ── Twilio Verify API ────────────────────────────────────────────────────

    [HttpPost("phone/twilio/send")]
    [AllowAnonymous]
    [EnableRateLimiting("otp")]
    public async Task<IActionResult> SendTwilioOtp(SendOtpRequest request, CancellationToken ct)
    {
        var phone = PhoneNormalizer.Normalize(request.Phone);
        if (phone == null)
            return BadRequest(new { message = "Geçerli bir telefon numarası girin (5XX XXX XX XX)." });

        var sendResult = await _twilioVerify.SendVerificationAsync(phone);
        return sendResult switch
        {
            TwilioVerifyService.SendResult.Sent => Ok(new { message = "Doğrulama kodu gönderildi." }),
            TwilioVerifyService.SendResult.TooSoon => StatusCode(429, new { message = "Yeni kod için lütfen bekleyin.", code = "auth_otp_too_soon" }),
            _ => StatusCode(500, new { message = "SMS gönderilemedi. Lütfen tekrar deneyin.", code = "auth_otp_failed" })
        };
    }

    [HttpPost("phone/twilio/verify")]
    [AllowAnonymous]
    [EnableRateLimiting("otp")]
    public async Task<IActionResult> VerifyTwilioOtp(VerifyOtpRequest request, CancellationToken ct)
    {
        var phone = PhoneNormalizer.Normalize(request.Phone);
        if (phone == null)
            return BadRequest(new { message = "Geçerli bir telefon numarası girin (5XX XXX XX XX)." });

        if (string.IsNullOrWhiteSpace(request.Code) || request.Code.Length < 4)
            return BadRequest(new { message = "Doğrulama kodunu girin." });

        var reqRole = ResolveRequestedRole(request.Role);
        if (!IsKnownRole(request.Role))
            return BadRequest(new { message = "Geçersiz rol.", code = "auth_invalid_role" });

        // Development: OTP doğrulamasını atla
        var isDev = _environment.IsDevelopment();

        if (!isDev)
        {
            var verifyResult = await _twilioVerify.CheckVerificationAsync(phone, request.Code);
            if (verifyResult != TwilioVerifyService.VerifyResult.Success)
            {
                return verifyResult switch
                {
                    TwilioVerifyService.VerifyResult.Expired => BadRequest(new { message = "Kodun süresi dolmuş.", code = "auth_otp_expired" }),
                    TwilioVerifyService.VerifyResult.TooManyAttempts => StatusCode(429, new { message = "Çok fazla hatalı deneme.", code = "auth_otp_blocked" }),
                    _ => BadRequest(new { message = "Geçersiz kod.", code = "auth_otp_invalid" })
                };
            }
        }

        // Telefon + Rol ile kullanıcı ara / oluştur
        var user = await _db.Users.Include(u => u.BarberProfile)
            .FirstOrDefaultAsync(u => u.PhoneNumber == phone && u.Role == reqRole, ct);

        if (user == null)
        {
            var phoneUser = await _db.Users
                .FirstOrDefaultAsync(u => u.PhoneNumber == phone, ct);
            if (phoneUser != null)
                return StatusCode(409, new { code = "auth_role_mismatch", message = "Bu telefon farklı bir rolle kayıtlı." });

            user = new User
            {
                Id = Guid.NewGuid(),
                PhoneNumber = phone,
                Role = reqRole,
                IsPhoneVerified = true,
                AccountStatus = AccountStatus.Active,
                CreatedAt = DateTime.UtcNow
            };

            if (reqRole == UserRole.Berber)
            {
                user.BarberProfile = new BarberProfile
                {
                    Id = Guid.NewGuid(),
                    UserId = user.Id,
                    Status = BarberStatus.Onboarding,
                    CreatedAt = DateTime.UtcNow
                };
            }

            _db.Users.Add(user);
            await _db.SaveChangesAsync(ct);
        }
        else
        {
            if (user.AccountStatus != AccountStatus.Active)
                return Unauthorized(new { code = AccountStatusCode(user.AccountStatus) });

            user.IsPhoneVerified = true;
            await _db.SaveChangesAsync(ct);
        }

        var accessToken = _tokenService.CreateAccessToken(user, user.BarberProfile?.Id);
        var refreshToken = await _tokenService.CreateRefreshTokenAsync(user, ClientIp, ct);

        return Ok(new AuthResponse(accessToken, refreshToken, ToUserDto(user)));
    }

    [HttpPost("email/send")]
    [AllowAnonymous]
    [EnableRateLimiting("otp")]
    public async Task<IActionResult> SendEmailOtp(SendEmailOtpRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Email) || !new System.ComponentModel.DataAnnotations.EmailAddressAttribute().IsValid(request.Email))
            return BadRequest(new { message = "Geçerli bir e-posta adresi girin." });

        var email = request.Email.Trim().ToLowerInvariant();
        var sendResult = await _otpService.SendEmailOtpAsync(email, ClientIp, ct: ct);

        return sendResult switch
        {
            OtpService.SendResult.Sent => Ok(new { message = "Doğrulama kodu gönderildi." }),
            OtpService.SendResult.TooSoon => StatusCode(429, new { message = "Yeni kod için lütfen bekleyin.", code = "auth_otp_too_soon" }),
            OtpService.SendResult.TooMany => StatusCode(429, new { message = "Çok fazla deneme yaptınız.", code = "auth_otp_too_many" }),
            _ => StatusCode(500, new { message = "Kod gönderilemedi.", code = "auth_otp_failed" })
        };
    }

    [HttpPost("email/verify")]
    [AllowAnonymous]
    [EnableRateLimiting("otp")]
    public async Task<IActionResult> VerifyEmailOtp(VerifyEmailOtpRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Email) || string.IsNullOrWhiteSpace(request.Code))
            return BadRequest(new { message = "E-posta ve kod zorunludur." });

        var reqRole = ResolveRequestedRole(request.Role);
        var email = request.Email.Trim().ToLowerInvariant();

        // Development: OTP doğrulamasını atla, her kod geçerli
        var isDev = _environment.IsDevelopment();

        if (string.IsNullOrWhiteSpace(request.Phone))
        {
            if (!isDev)
            {
                var checkResult = await _otpService.CheckEmailOtpAsync(email, request.Code, ct: ct);
                if (checkResult != OtpService.VerifyResult.Success)
                {
                    return checkResult switch
                    {
                        OtpService.VerifyResult.Expired => BadRequest(new { message = "Kodun süresi dolmuş.", code = "auth_otp_expired" }),
                        OtpService.VerifyResult.TooManyAttempts => StatusCode(429, new { message = "Çok fazla hatalı deneme.", code = "auth_otp_blocked" }),
                        _ => BadRequest(new { message = "Geçersiz kod.", code = "auth_otp_invalid" })
                    };
                }
            }

            var existingUser = await _db.Users.Include(u => u.BarberProfile)
                .FirstOrDefaultAsync(u => u.Email == email && u.Role == reqRole, ct);

            if (existingUser != null)
            {
                if (existingUser.AccountStatus != AccountStatus.Active)
                    return Unauthorized(new { code = AccountStatusCode(existingUser.AccountStatus) });

                if (!isDev) await _otpService.TryConsumeEmailOtpAsync(email, request.Code, ct: ct);
                var token = _tokenService.CreateAccessToken(existingUser, existingUser.BarberProfile?.Id);
                var refresh = await _tokenService.CreateRefreshTokenAsync(existingUser, ClientIp, ct);
                return Ok(new AuthResponse(token, refresh, ToUserDto(existingUser)));
            }
            else
            {
                return StatusCode(409, new { code = "auth_phone_verification_required", message = "Kayıt için telefon numarası zorunludur." });
            }
        }
        else
        {
            var phone = PhoneNormalizer.Normalize(request.Phone);
            if (phone == null) return BadRequest(new { message = "Geçerli bir telefon numarası girin." });

            var existingUser = await _db.Users.Include(u => u.BarberProfile)
                .FirstOrDefaultAsync(u => u.Email == email && u.Role == reqRole, ct);

            if (existingUser != null)
            {
                if (existingUser.AccountStatus != AccountStatus.Active)
                    return Unauthorized(new { code = AccountStatusCode(existingUser.AccountStatus) });

                if (!isDev) await _otpService.TryConsumeEmailOtpAsync(email, request.Code, ct: ct);
                var token = _tokenService.CreateAccessToken(existingUser, existingUser.BarberProfile?.Id);
                var refresh = await _tokenService.CreateRefreshTokenAsync(existingUser, ClientIp, ct);
                return Ok(new AuthResponse(token, refresh, ToUserDto(existingUser)));
            }

            if (!isDev)
            {
                var consumeResult = await _otpService.TryConsumeEmailOtpAsync(email, request.Code, ct: ct);
                if (consumeResult != OtpService.VerifyResult.Success)
                    return BadRequest(new { message = "Geçersiz veya süresi dolmuş kod." });
            }

            var phoneUser = await _db.Users.FirstOrDefaultAsync(u => u.PhoneNumber == phone && u.Role == reqRole, ct);
            if (phoneUser != null)
            {
                return StatusCode(409, new { code = "auth_phone_already_used", message = "Bu telefon numarası bu rol için başka bir hesap tarafından kullanılıyor." });
            }

            var newUser = new User
            {
                Id = Guid.NewGuid(),
                Email = email,
                PhoneNumber = phone,
                Role = reqRole,
                IsPhoneVerified = true,
                CreatedAt = DateTime.UtcNow
            };
            
            if (reqRole == UserRole.Berber)
            {
                newUser.BarberProfile = new BarberProfile
                {
                    Id = Guid.NewGuid(),
                    UserId = newUser.Id,
                    Status = BarberStatus.Onboarding,
                    CreatedAt = DateTime.UtcNow
                };
            }

            _db.Users.Add(newUser);
            await _db.SaveChangesAsync(ct);

            var newToken = _tokenService.CreateAccessToken(newUser, newUser.BarberProfile?.Id);
            var newRefresh = await _tokenService.CreateRefreshTokenAsync(newUser, ClientIp, ct);
            return Ok(new AuthResponse(newToken, newRefresh, ToUserDto(newUser)));
        }
    }

    [HttpPost("google")]
    [AllowAnonymous]
    [EnableRateLimiting("otp")]
    public async Task<IActionResult> VerifyGoogle(VerifyGoogleRequest request, CancellationToken ct)
    {
        var token = request.ActualToken;
        if (string.IsNullOrWhiteSpace(token))
            return BadRequest(new { message = "Geçersiz istek.", code = "auth_google_invalid_token" });

        var verifyResult = await _firebaseVerifier.VerifyIdTokenAsync(token, ct);
        if (!verifyResult.Success || verifyResult.User == null)
        {
            return HandleFirebaseVerifyError(verifyResult);
        }

        var vUser = verifyResult.User;
        if (!string.Equals(vUser.SignInProvider, "google.com", StringComparison.OrdinalIgnoreCase))
        {
            return Unauthorized(new { message = "Geçersiz sağlayıcı.", code = "auth_google_provider_invalid" });
        }

        if (string.IsNullOrWhiteSpace(vUser.Email) || !vUser.EmailVerified)
        {
            return Unauthorized(new { message = "E-posta adresi doğrulanmamış.", code = "auth_google_email_unverified" });
        }

        // 1. Rol belirtilmişse, önce email + rol ile ara (kullanıcı niyetine saygı)
        User? user = null;
        var reqRole = ResolveRequestedRole(request.Role);

        if (!string.IsNullOrWhiteSpace(request.Role) && !string.IsNullOrWhiteSpace(vUser.Email))
        {
            user = await _db.Users.Include(u => u.BarberProfile)
                .FirstOrDefaultAsync(u => u.Email == vUser.Email && u.Role == reqRole, ct);
        }

        // 2. Email + rol bulunamadıysa FirebaseUid ile ara
        if (user == null)
        {
            user = await _db.Users.Include(u => u.BarberProfile)
                .FirstOrDefaultAsync(u => u.FirebaseUid == vUser.Uid, ct);
        }

        // 3. Hala bulunamadıysa email ile ara (herhangi bir rol)
        if (user == null && !string.IsNullOrWhiteSpace(vUser.Email))
        {
            user = await _db.Users.Include(u => u.BarberProfile)
                .FirstOrDefaultAsync(u => u.Email == vUser.Email, ct);
        }

        // FirebaseUid'yi bağla (email ile bulunduysa)
        if (user != null && user.FirebaseUid != vUser.Uid)
        {
            user.FirebaseUid = vUser.Uid;
            await _db.SaveChangesAsync(ct);
        }

        if (user == null)
        {
            return StatusCode(409, new { code = "auth_google_phone_verification_required" });
        }

        // 4. Rol kontrolü: yanlış rolle bulunduysa, aynı email için doğru rol var mı bak
        if (!string.IsNullOrWhiteSpace(request.Role) && user.Role != reqRole)
        {
            if (reqRole == UserRole.Admin)
            {
                return Unauthorized(new { code = "auth_role_mismatch" });
            }

            // Aynı email ile istenen rolde başka hesap var mı?
            if (!string.IsNullOrWhiteSpace(vUser.Email))
            {
                var targetUser = await _db.Users.Include(u => u.BarberProfile)
                    .FirstOrDefaultAsync(u => u.Email == vUser.Email && u.Role == reqRole, ct);
                if (targetUser != null)
                {
                    // O hesaba geç, FirebaseUid'yi bağla
                    user = targetUser;
                    if (user.FirebaseUid != vUser.Uid)
                    {
                        user.FirebaseUid = vUser.Uid;
                        await _db.SaveChangesAsync(ct);
                    }
                }
                else if (reqRole == UserRole.Berber && user.Role == UserRole.Musteri)
                {
                    // Berber hesabı yok, Musteri hesabını Berber'e yükselt
                    user.Role = UserRole.Berber;
                    if (user.BarberProfile == null)
                    {
                        user.BarberProfile = new BarberProfile
                        {
                            Id = Guid.NewGuid(),
                            UserId = user.Id,
                            Status = BarberStatus.Onboarding,
                            CreatedAt = DateTime.UtcNow
                        };
                    }
                    await _db.SaveChangesAsync(ct);
                }
            }
        }

        if (user.AccountStatus != AccountStatus.Active)
            return Unauthorized(new { code = AccountStatusCode(user.AccountStatus) });

        var accessToken = _tokenService.CreateAccessToken(user, user.BarberProfile?.Id);
        var refreshToken = await _tokenService.CreateRefreshTokenAsync(user, ClientIp, ct);

        return Ok(new AuthResponse(accessToken, refreshToken, ToUserDto(user)));
    }

    [HttpPost("phone")]
    [AllowAnonymous]
    [EnableRateLimiting("otp")]
    public async Task<IActionResult> LoginWithPhone(PhoneLoginRequest request, CancellationToken ct)
    {
        var token = request.ActualToken;
        if (string.IsNullOrWhiteSpace(token))
            return BadRequest(new { message = "Geçersiz istek.", code = "auth_phone_invalid_token" });

        var verifyResult = await _firebaseVerifier.VerifyIdTokenAsync(token, ct);
        if (!verifyResult.Success || verifyResult.User == null)
        {
            var errCode = verifyResult.ErrorCode ?? "auth_phone_invalid_token";
            return Unauthorized(new { message = "Telefon doğrulaması başarısız oldu.", code = errCode });
        }

        var vUser = verifyResult.User;
        if (!string.Equals(vUser.SignInProvider, "phone", StringComparison.OrdinalIgnoreCase))
        {
            return Unauthorized(new { message = "Geçersiz sağlayıcı.", code = "auth_phone_provider_invalid" });
        }

        if (string.IsNullOrWhiteSpace(vUser.PhoneNumber))
        {
            return BadRequest(new { message = "Telefon numarası alınamadı.", code = "auth_phone_missing" });
        }

        // E.164 formatından normalize et (+905xxxxxxxxx → 905xxxxxxxxx)
        var phone = vUser.PhoneNumber.Trim();
        if (phone.StartsWith("+"))
            phone = phone[1..];

        var reqRole = ResolveRequestedRole(request.Role);
        if (!IsKnownRole(request.Role))
            return BadRequest(new { message = "Geçersiz rol.", code = "auth_invalid_role" });

        // Telefon + Rol ile kullanıcı ara
        var user = await _db.Users.Include(u => u.BarberProfile)
            .FirstOrDefaultAsync(u => u.PhoneNumber == phone && u.Role == reqRole, ct);

        if (user == null)
        {
            // Aynı telefon farklı rol ile var mı?
            var phoneUser = await _db.Users
                .FirstOrDefaultAsync(u => u.PhoneNumber == phone, ct);
            if (phoneUser != null)
                return StatusCode(409, new { code = "auth_role_mismatch", message = "Bu telefon farklı bir rolle kayıtlı." });

            // Yeni kullanıcı oluştur
            user = new User
            {
                Id = Guid.NewGuid(),
                PhoneNumber = phone,
                Role = reqRole,
                FirebaseUid = vUser.Uid,
                IsPhoneVerified = true,
                AccountStatus = AccountStatus.Active,
                CreatedAt = DateTime.UtcNow
            };

            if (reqRole == UserRole.Berber)
            {
                user.BarberProfile = new BarberProfile
                {
                    Id = Guid.NewGuid(),
                    UserId = user.Id,
                    Status = BarberStatus.Onboarding,
                    CreatedAt = DateTime.UtcNow
                };
            }

            _db.Users.Add(user);
            await _db.SaveChangesAsync(ct);
        }
        else
        {
            // Mevcut kullanıcı - FirebaseUid'yi güncelle
            if (user.FirebaseUid != vUser.Uid)
            {
                user.FirebaseUid = vUser.Uid;
                user.IsPhoneVerified = true;
                await _db.SaveChangesAsync(ct);
            }

            if (user.AccountStatus != AccountStatus.Active)
                return Unauthorized(new { code = AccountStatusCode(user.AccountStatus) });
        }

        var accessToken = _tokenService.CreateAccessToken(user, user.BarberProfile?.Id);
        var refreshToken = await _tokenService.CreateRefreshTokenAsync(user, ClientIp, ct);

        return Ok(new AuthResponse(accessToken, refreshToken, ToUserDto(user)));
    }

    [HttpPost("google/phone/save")]
    [AllowAnonymous]
    [EnableRateLimiting("otp")]
    public async Task<IActionResult> SaveGooglePhone(VerifyGooglePhoneOtpRequest request, CancellationToken ct)
    {
        var token = request.ActualToken;
        // Gelen request'in Code alanı kullanılmıyor, sadece Phone kontrol ediliyor
        if (string.IsNullOrWhiteSpace(token) || string.IsNullOrWhiteSpace(request.Phone))
            return BadRequest(new { message = "Geçersiz istek.", code = "auth_google_invalid_token" });

        var verifyResult = await _firebaseVerifier.VerifyIdTokenAsync(token, ct);
        if (!verifyResult.Success || verifyResult.User == null)
        {
            return HandleFirebaseVerifyError(verifyResult);
        }

        var vUser = verifyResult.User;
        if (!string.Equals(vUser.SignInProvider, "google.com", StringComparison.OrdinalIgnoreCase))
            return Unauthorized(new { code = "auth_google_provider_invalid" });

        if (string.IsNullOrWhiteSpace(vUser.Email) || !vUser.EmailVerified)
            return Unauthorized(new { code = "auth_google_email_unverified" });

        var phone = PhoneNormalizer.Normalize(request.Phone);
        if (phone == null)
            return BadRequest(new { message = "Geçerli bir telefon numarası girin." });

        if (!string.IsNullOrWhiteSpace(request.Role))
        {
            var roleTrimmed = request.Role.Trim().ToLowerInvariant();
            if (roleTrimmed == "admin")
            {
                return Unauthorized(new { code = "auth_role_mismatch", message = "Admin rolü oluşturulamaz." });
            }
            if (!IsKnownRole(roleTrimmed))
            {
                return BadRequest(new { code = "auth_invalid_role", message = "Geçersiz rol." });
            }
        }

        var requestedRole = ResolveRequestedRole(request.Role);

        IDbContextTransaction? tx = null;
        if (_db.Database.IsRelational())
        {
            tx = await _db.Database.BeginTransactionAsync(ct);
        }

        try
        {
            var uidUser = await _db.Users.Include(u => u.BarberProfile)
                .FirstOrDefaultAsync(u => u.FirebaseUid == vUser.Uid, ct);

            var phoneUser = await _db.Users.Include(u => u.BarberProfile)
                .FirstOrDefaultAsync(u => u.PhoneNumber == phone, ct);

            if (uidUser != null && uidUser.AccountStatus != AccountStatus.Active)
            {
                if (tx != null) { await tx.RollbackAsync(ct); await tx.DisposeAsync(); tx = null; }
                return StatusCode(403, new { message = "Hesap aktif değil.", code = AccountStatusCode(uidUser.AccountStatus) });
            }
            if (phoneUser != null && phoneUser.AccountStatus != AccountStatus.Active)
            {
                if (tx != null) { await tx.RollbackAsync(ct); await tx.DisposeAsync(); tx = null; }
                return StatusCode(403, new { message = "Hesap aktif değil.", code = AccountStatusCode(phoneUser.AccountStatus) });
            }

            if (uidUser != null && phoneUser != null && uidUser.Id != phoneUser.Id)
            {
                if (tx != null) { await tx.RollbackAsync(ct); await tx.DisposeAsync(); tx = null; }
                return StatusCode(409, new { code = "auth_google_user_conflict", message = "Bu Google hesabı ve telefon numarası farklı hesaplara bağlı." });
            }

            if (uidUser != null && !string.IsNullOrEmpty(uidUser.PhoneNumber) && uidUser.PhoneNumber != phone)
            {
                if (tx != null) { await tx.RollbackAsync(ct); await tx.DisposeAsync(); tx = null; }
                return StatusCode(409, new { code = "auth_google_uid_already_linked", message = "Bu Google hesabı başka bir telefon numarasına bağlı." });
            }

            if (phoneUser != null && !string.IsNullOrEmpty(phoneUser.FirebaseUid) && phoneUser.FirebaseUid != vUser.Uid)
            {
                if (tx != null) { await tx.RollbackAsync(ct); await tx.DisposeAsync(); tx = null; }
                return StatusCode(409, new { code = "auth_google_phone_already_linked", message = "Bu telefon numarası başka bir Google hesabına bağlı." });
            }

            if (uidUser != null && phoneUser != null && uidUser.Id == phoneUser.Id && uidUser.AccountStatus == AccountStatus.Active)
            {
                var existingAccessToken = _tokenService.CreateAccessToken(uidUser, uidUser.BarberProfile?.Id);
                var existingRefreshToken = await _tokenService.CreateRefreshTokenAsync(uidUser, ClientIp, ct);
                if (tx != null) { await tx.CommitAsync(ct); await tx.DisposeAsync(); tx = null; }
                return Ok(new AuthResponse(existingAccessToken, existingRefreshToken, ToUserDto(uidUser)));
            }

            User user;
            if (phoneUser != null)
            {
                user = phoneUser;
                user.FirebaseUid = vUser.Uid;
                if (string.IsNullOrWhiteSpace(user.Email)) user.Email = vUser.Email;
                user.IsPhoneVerified = true;

                if (requestedRole == UserRole.Berber && user.Role == UserRole.Musteri)
                {
                    user.Role = UserRole.Berber;
                    if (user.BarberProfile == null)
                    {
                        user.BarberProfile = new BarberProfile
                        {
                            Id = Guid.NewGuid(),
                            UserId = user.Id,
                            Status = BarberStatus.Onboarding,
                            CreatedAt = DateTime.UtcNow
                        };
                    }
                }
            }
            else if (uidUser != null)
            {
                user = uidUser;
                user.PhoneNumber = phone;
                user.IsPhoneVerified = true;

                if (requestedRole == UserRole.Berber && user.Role == UserRole.Musteri)
                {
                    user.Role = UserRole.Berber;
                    if (user.BarberProfile == null)
                    {
                        user.BarberProfile = new BarberProfile
                        {
                            Id = Guid.NewGuid(),
                            UserId = user.Id,
                            Status = BarberStatus.Onboarding,
                            CreatedAt = DateTime.UtcNow
                        };
                    }
                }
            }
            else
            {
                user = new User
                {
                    Id = Guid.NewGuid(),
                    PhoneNumber = phone,
                    Email = vUser.Email,
                    FirebaseUid = vUser.Uid,
                    Role = requestedRole,
                    IsPhoneVerified = true,
                    CreatedAt = DateTime.UtcNow
                };
                _db.Users.Add(user);

                if (requestedRole == UserRole.Berber)
                {
                    user.BarberProfile = new BarberProfile
                    {
                        Id = Guid.NewGuid(),
                        UserId = user.Id,
                        Status = BarberStatus.Onboarding,
                        CreatedAt = DateTime.UtcNow
                    };
                }
            }

            await _db.SaveChangesAsync(ct);

            var accessToken = _tokenService.CreateAccessToken(user, user.BarberProfile?.Id);
            var refreshToken = await _tokenService.CreateRefreshTokenAsync(user, ClientIp, ct);

            if (tx != null)
            {
                await tx.CommitAsync(ct);
            }

            return Ok(new AuthResponse(accessToken, refreshToken, ToUserDto(user)));
        }
        catch (DbUpdateException ex)
        {
            if (tx != null)
            {
                await tx.RollbackAsync(ct);
                await tx.DisposeAsync();
                tx = null;
            }

            if (!IsUniqueConstraintViolation(ex))
            {
                throw;
            }

            _db.ChangeTracker.Clear();

            var reReadUidUser = await _db.Users.Include(u => u.BarberProfile).FirstOrDefaultAsync(u => u.FirebaseUid == vUser.Uid, ct);
            var reReadPhoneUser = await _db.Users.Include(u => u.BarberProfile).FirstOrDefaultAsync(u => u.PhoneNumber == phone, ct);

            if (reReadUidUser != null && reReadPhoneUser != null && reReadUidUser.Id == reReadPhoneUser.Id && reReadUidUser.AccountStatus == AccountStatus.Active)
            {
                var accessToken = _tokenService.CreateAccessToken(reReadUidUser, reReadUidUser.BarberProfile?.Id);
                var refreshToken = await _tokenService.CreateRefreshTokenAsync(reReadUidUser, ClientIp, ct);
                return Ok(new AuthResponse(accessToken, refreshToken, ToUserDto(reReadUidUser)));
            }

            if (reReadUidUser != null && !string.IsNullOrEmpty(reReadUidUser.PhoneNumber) && reReadUidUser.PhoneNumber != phone)
            {
                return StatusCode(409, new { code = "auth_google_uid_already_linked", message = "Bu Google hesabı başka bir telefon numarasına bağlı." });
            }

            if (reReadPhoneUser != null && !string.IsNullOrEmpty(reReadPhoneUser.FirebaseUid) && reReadPhoneUser.FirebaseUid != vUser.Uid)
            {
                return StatusCode(409, new { code = "auth_google_phone_already_linked", message = "Bu telefon numarası başka bir Google hesabına bağlı." });
            }

            if (reReadUidUser != null && reReadPhoneUser != null && reReadUidUser.Id != reReadPhoneUser.Id)
            {
                return StatusCode(409, new { code = "auth_google_user_conflict", message = "Bu Google hesabı ve telefon numarası farklı hesaplara bağlı." });
            }

            return StatusCode(409, new { code = "auth_google_linking_conflict", message = "Kullanıcı oluşturulurken çakışma yaşandı." });
        }
        finally
        {
            if (tx != null) await tx.DisposeAsync();
        }
    }

    // ── Şifreli Auth ──────────────────────────────────────────────

    [HttpPost("register")]
    [AllowAnonymous]
    [EnableRateLimiting("otp")]
    public async Task<IActionResult> Register(RegisterRequest request, CancellationToken ct)
    {
        // Validation
        if (string.IsNullOrWhiteSpace(request.Email) ||
            !new System.ComponentModel.DataAnnotations.EmailAddressAttribute().IsValid(request.Email))
            return BadRequest(new { message = "Geçerli bir e-posta adresi girin." });

        var phone = PhoneNormalizer.Normalize(request.Phone);
        if (phone == null)
            return BadRequest(new { message = "Geçerli bir telefon numarası girin (5XX XXX XX XX)." });

        if (string.IsNullOrWhiteSpace(request.Password) || request.Password.Length < 8)
            return BadRequest(new { message = "Şifre en az 8 karakter olmalıdır." });

        var reqRole = ResolveRequestedRole(request.Role);
        if (!IsKnownRole(request.Role))
            return BadRequest(new { message = "Geçersiz rol.", code = "auth_invalid_role" });

        var email = request.Email.Trim().ToLowerInvariant();

        // Çakışma kontrolleri
        var existingEmail = await _db.Users.FirstOrDefaultAsync(
            u => u.Email == email && u.Role == reqRole, ct);
        if (existingEmail != null)
            return StatusCode(409, new { code = "auth_email_exists",
                message = "Bu e-posta adresi bu rol için zaten kayıtlı." });

        var existingPhone = await _db.Users.FirstOrDefaultAsync(
            u => u.PhoneNumber == phone && u.Role == reqRole, ct);
        if (existingPhone != null)
            return StatusCode(409, new { code = "auth_phone_exists",
                message = "Bu telefon numarası bu rol için zaten kayıtlı." });

        // Kullanıcı oluştur
        var passwordHash = BCrypt.Net.BCrypt.EnhancedHashPassword(request.Password);
        var user = new User
        {
            Id = Guid.NewGuid(),
            Email = email,
            PhoneNumber = phone,
            PasswordHash = passwordHash,
            Role = reqRole,
            FirstName = request.FirstName?.Trim(),
            LastName = request.LastName?.Trim(),
            IsPhoneVerified = false,
            EmailVerified = false,
            AccountStatus = AccountStatus.Active,
            CreatedAt = DateTime.UtcNow
        };

        if (reqRole == UserRole.Berber)
        {
            user.BarberProfile = new BarberProfile
            {
                Id = Guid.NewGuid(),
                UserId = user.Id,
                Status = BarberStatus.Onboarding,
                CreatedAt = DateTime.UtcNow
            };
        }

        _db.Users.Add(user);
        await _db.SaveChangesAsync(ct);

        // Otomatik giriş yap
        var accessToken = _tokenService.CreateAccessToken(user, user.BarberProfile?.Id);
        var refreshToken = await _tokenService.CreateRefreshTokenAsync(user, ClientIp, ct);

        return Ok(new AuthResponse(accessToken, refreshToken, ToUserDto(user)));
    }

    [HttpPost("login")]
    [AllowAnonymous]
    [EnableRateLimiting("otp")]
    public async Task<IActionResult> LoginWithPassword(LoginRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Credential))
            return BadRequest(new { message = "E-posta veya telefon numarası girin." });

        if (string.IsNullOrWhiteSpace(request.Password))
            return BadRequest(new { message = "Şifre girin." });

        var reqRole = ResolveRequestedRole(request.Role);
        var credential = request.Credential.Trim();

        User? user;
        if (credential.Contains('@'))
        {
            user = await _db.Users.Include(u => u.BarberProfile)
                .FirstOrDefaultAsync(u => u.Email == credential.ToLowerInvariant() && u.Role == reqRole, ct);
        }
        else
        {
            var phone = PhoneNormalizer.Normalize(credential);
            if (phone == null)
                return BadRequest(new { message = "Geçerli bir e-posta veya telefon numarası girin." });
            user = await _db.Users.Include(u => u.BarberProfile)
                .FirstOrDefaultAsync(u => u.PhoneNumber == phone && u.Role == reqRole, ct);
        }

        if (user == null)
            return Unauthorized(new { message = "Geçersiz kimlik bilgileri.", code = "auth_invalid_credentials" });

        if (user.AccountStatus != AccountStatus.Active)
            return Unauthorized(new { code = AccountStatusCode(user.AccountStatus) });

        // Hesap kilit kontrolü
        if (user.LockoutEnd != null && user.LockoutEnd > DateTime.UtcNow)
        {
            var remaining = (int)(user.LockoutEnd.Value - DateTime.UtcNow).TotalMinutes + 1;
            return StatusCode(429, new { code = "auth_account_locked",
                message = $"Çok fazla hatalı deneme. Hesabınız {remaining} dakika kilitlendi." });
        }

        // Google-only kullanıcı
        if (string.IsNullOrWhiteSpace(user.PasswordHash))
            return StatusCode(400, new { code = "auth_password_not_set",
                message = "Bu hesap Google ile oluşturulmuş. Lütfen Google ile giriş yapın." });

        if (!BCrypt.Net.BCrypt.EnhancedVerify(request.Password, user.PasswordHash))
        {
            user.FailedLoginAttempts++;
            if (user.FailedLoginAttempts >= 5)
            {
                user.LockoutEnd = DateTime.UtcNow.AddMinutes(15);
                user.FailedLoginAttempts = 0;
            }
            await _db.SaveChangesAsync(ct);
            return Unauthorized(new { message = "Geçersiz kimlik bilgileri.", code = "auth_invalid_credentials" });
        }

        // Başarılı giriş — sayaç sıfırla
        user.FailedLoginAttempts = 0;
        user.LockoutEnd = null;

        var accessToken = _tokenService.CreateAccessToken(user, user.BarberProfile?.Id);
        var refreshToken = await _tokenService.CreateRefreshTokenAsync(user, ClientIp, ct);

        return Ok(new AuthResponse(accessToken, refreshToken, ToUserDto(user)));
    }

    // ── Şifre Sıfırlama ─────────────────────────────────────────

    [HttpPost("forgot-password")]
    [AllowAnonymous]
    [EnableRateLimiting("otp")]
    public async Task<IActionResult> ForgotPassword(ForgotPasswordRequest request, CancellationToken ct)
    {
        var credential = request.Credential?.Trim();
        if (string.IsNullOrWhiteSpace(credential))
            return BadRequest(new { message = "E-posta veya telefon numarası girin." });

        var role = ResolveRequestedRole(request.Role);
        User? user;
        if (credential.Contains('@'))
            user = await _db.Users.FirstOrDefaultAsync(u => u.Email == credential && u.Role == role, ct);
        else
        {
            var phone = PhoneNormalizer.Normalize(credential);
            if (phone == null) return BadRequest(new { message = "Geçerli bir e-posta veya telefon girin." });
            user = await _db.Users.FirstOrDefaultAsync(u => u.PhoneNumber == phone && u.Role == role, ct);
        }

        // Güvenlik: Kullanıcı bulunamasa da aynı mesajı dön
        if (user == null || string.IsNullOrWhiteSpace(user.Email))
            return Ok(new { message = "Email adresinize bağlı bir hesap varsa şifre sıfırlama kodu gönderildi." });

        var sendResult = await _otpService.SendEmailOtpAsync(user.Email, ClientIp,
            purpose: OtpPurpose.Login, subject: "password-reset", ct: ct);

        return Ok(new { message = "Email adresinize bağlı bir hesap varsa şifre sıfırlama kodu gönderildi." });
    }

    [HttpPost("reset-password")]
    [AllowAnonymous]
    public async Task<IActionResult> ResetPassword(ResetPasswordRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Credential) || string.IsNullOrWhiteSpace(request.Code)
            || string.IsNullOrWhiteSpace(request.NewPassword))
            return BadRequest(new { message = "Tüm alanlar zorunludur." });

        if (request.NewPassword.Length < 8)
            return BadRequest(new { message = "Yeni şifre en az 8 karakter olmalıdır." });

        var role = ResolveRequestedRole(request.Role);
        var credential = request.Credential.Trim();
        User? user;
        if (credential.Contains('@'))
            user = await _db.Users.FirstOrDefaultAsync(u => u.Email == credential && u.Role == role, ct);
        else
        {
            var phone = PhoneNormalizer.Normalize(credential);
            if (phone == null) return BadRequest(new { message = "Geçerli bir e-posta veya telefon girin." });
            user = await _db.Users.FirstOrDefaultAsync(u => u.PhoneNumber == phone && u.Role == role, ct);
        }

        if (user == null || string.IsNullOrWhiteSpace(user.Email))
            return BadRequest(new { message = "Geçersiz şifre sıfırlama isteği." });

        // OTP doğrula
        var verifyResult = await _otpService.TryConsumeEmailOtpAsync(user.Email, request.Code,
            purpose: OtpPurpose.Login, expectedSubject: "password-reset", ct: ct);
        if (verifyResult != OtpService.VerifyResult.Success)
            return BadRequest(new { message = "Geçersiz veya süresi dolmuş kod." });

        // Şifreyi güncelle, tüm oturumları sonlandır
        user.PasswordHash = BCrypt.Net.BCrypt.EnhancedHashPassword(request.NewPassword);
        user.TokenVersion++;
        user.FailedLoginAttempts = 0;
        user.LockoutEnd = null;
        foreach (var token in await _db.RefreshTokens.Where(t => t.UserId == user.Id && t.RevokedAt == null).ToListAsync(ct))
            token.RevokedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);

        return Ok(new { message = "Şifreniz başarıyla sıfırlandı. Lütfen yeni şifrenizle giriş yapın." });
    }

    // ── Doğrulama (Authorized) ─────────────────────────────────────

    [HttpPost("verify/email/send")]
    [Authorize]
    [EnableRateLimiting("otp")]
    public async Task<IActionResult> SendEmailVerification(CancellationToken ct)
    {
        var userId = User.GetUserId();
        var user = await _db.Users.FindAsync(new object[] { userId }, ct);
        if (user == null) return Unauthorized();

        if (string.IsNullOrWhiteSpace(user.Email))
            return BadRequest(new { message = "Hesabınızda e-posta tanımlı değil." });

        if (user.EmailVerified)
            return BadRequest(new { message = "E-posta zaten doğrulanmış." });

        var sendResult = await _otpService.SendEmailOtpAsync(user.Email, ClientIp,
            purpose: OtpPurpose.EmailVerification, ct: ct);

        return sendResult switch
        {
            OtpService.SendResult.Sent => Ok(new { message = "Doğrulama kodu gönderildi." }),
            OtpService.SendResult.TooSoon => StatusCode(429, new { message = "Yeni kod için lütfen bekleyin.", code = "auth_otp_too_soon" }),
            OtpService.SendResult.TooMany => StatusCode(429, new { message = "Çok fazla deneme yaptınız.", code = "auth_otp_too_many" }),
            _ => StatusCode(500, new { message = "Kod gönderilemedi.", code = "auth_otp_failed" })
        };
    }

    [HttpPost("verify/email")]
    [Authorize]
    public async Task<IActionResult> VerifyEmail(VerifyCodeRequest request, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var user = await _db.Users.FindAsync(new object[] { userId }, ct);
        if (user == null) return Unauthorized();

        if (user.EmailVerified)
            return Ok(ToUserDto(user));

        if (string.IsNullOrWhiteSpace(request.Code) || request.Code.Length != 6)
            return BadRequest(new { message = "6 haneli doğrulama kodunu girin." });

        if (string.IsNullOrWhiteSpace(user.Email))
            return BadRequest(new { message = "Hesabınızda e-posta tanımlı değil." });

        var verifyResult = await _otpService.TryConsumeEmailOtpAsync(user.Email, request.Code,
            purpose: OtpPurpose.EmailVerification, ct: ct);
        if (verifyResult != OtpService.VerifyResult.Success)
        {
            return verifyResult switch
            {
                OtpService.VerifyResult.Expired => BadRequest(new { message = "Kodun süresi dolmuş.", code = "auth_otp_expired" }),
                OtpService.VerifyResult.TooManyAttempts => StatusCode(429, new { message = "Çok fazla hatalı deneme.", code = "auth_otp_blocked" }),
                _ => BadRequest(new { message = "Geçersiz kod.", code = "auth_otp_invalid" })
            };
        }

        user.EmailVerified = true;
        await _db.SaveChangesAsync(ct);

        return Ok(ToUserDto(user));
    }

    [HttpPost("verify/phone")]
    [Authorize]
    public async Task<IActionResult> VerifyPhone(VerifyCodeRequest request, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var user = await _db.Users.FindAsync(new object[] { userId }, ct);
        if (user == null) return Unauthorized();

        if (user.IsPhoneVerified)
            return Ok(ToUserDto(user));

        if (string.IsNullOrWhiteSpace(request.Code) || request.Code.Length != 6)
            return BadRequest(new { message = "6 haneli doğrulama kodunu girin." });

        var verifyResult = await _otpService.TryConsumeOtpAsync(user.PhoneNumber, request.Code,
            purpose: OtpPurpose.PhoneVerification, ct: ct);
        if (verifyResult != OtpService.VerifyResult.Success)
        {
            return verifyResult switch
            {
                OtpService.VerifyResult.Expired => BadRequest(new { message = "Kodun süresi dolmuş.", code = "auth_otp_expired" }),
                OtpService.VerifyResult.TooManyAttempts => StatusCode(429, new { message = "Çok fazla hatalı deneme.", code = "auth_otp_blocked" }),
                _ => BadRequest(new { message = "Geçersiz kod.", code = "auth_otp_invalid" })
            };
        }

        user.IsPhoneVerified = true;
        await _db.SaveChangesAsync(ct);

        return Ok(ToUserDto(user));
    }

    [HttpPost("verify/phone/send")]
    [Authorize]
    [EnableRateLimiting("otp")]
    public async Task<IActionResult> SendPhoneVerification(CancellationToken ct)
    {
        var userId = User.GetUserId();
        var user = await _db.Users.FindAsync(new object[] { userId }, ct);
        if (user == null) return Unauthorized();

        if (user.IsPhoneVerified)
            return BadRequest(new { message = "Telefon zaten doğrulanmış." });

        if (string.IsNullOrWhiteSpace(user.PhoneNumber))
            return BadRequest(new { message = "Hesabınızda telefon numarası tanımlı değil." });

        var sendResult = await _otpService.SendOtpAsync(user.PhoneNumber, ClientIp,
            purpose: OtpPurpose.PhoneVerification, ct: ct);

        return sendResult switch
        {
            OtpService.SendResult.Sent => Ok(new { message = "Doğrulama kodu gönderildi." }),
            OtpService.SendResult.TooSoon => StatusCode(429, new { message = "Yeni kod için lütfen bekleyin.", code = "auth_otp_too_soon" }),
            OtpService.SendResult.TooMany => StatusCode(429, new { message = "Çok fazla deneme yaptınız.", code = "auth_otp_too_many" }),
            OtpService.SendResult.SmsFailed => StatusCode(500, new { message = "SMS gönderilemedi. Lütfen tekrar deneyin.", code = "auth_otp_failed" }),
            _ => StatusCode(500, new { message = "Kod gönderilemedi.", code = "auth_otp_failed" })
        };
    }

    /// <summary>
    /// Telefon doğrulamasını Firebase Phone Auth token'ı ile yapar (NacSMS yerine).
    /// Kullanıcı giriş yapmış olmalıdır. Firebase token'dan gelen numara, hesaptaki numara ile eşleşmelidir.
    /// </summary>
    [HttpPost("verify/phone/firebase")]
    [Authorize]
    public async Task<IActionResult> VerifyPhoneWithFirebase(FirebaseTokenRequest request, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var user = await _db.Users.FindAsync(new object[] { userId }, ct);
        if (user == null) return Unauthorized();

        if (user.IsPhoneVerified)
            return Ok(ToUserDto(user));

        if (string.IsNullOrWhiteSpace(request.FirebaseIdToken))
            return BadRequest(new { message = "Firebase token zorunludur." });

        var verifyResult = await _firebaseVerifier.VerifyIdTokenAsync(request.FirebaseIdToken, ct);
        if (!verifyResult.Success || verifyResult.User == null)
            return Unauthorized(new { message = "Telefon doğrulaması başarısız oldu.", code = "auth_phone_invalid_token" });

        var vUser = verifyResult.User;
        if (!string.Equals(vUser.SignInProvider, "phone", StringComparison.OrdinalIgnoreCase))
            return Unauthorized(new { message = "Geçersiz sağlayıcı. Telefon ile doğrulama yapın.", code = "auth_phone_provider_invalid" });

        if (string.IsNullOrWhiteSpace(vUser.PhoneNumber))
            return BadRequest(new { message = "Telefon numarası alınamadı.", code = "auth_phone_missing" });

        // E.164 formatından normalize et (+905xxxxxxxxx → 905xxxxxxxxx)
        var phone = vUser.PhoneNumber.Trim();
        if (phone.StartsWith("+"))
            phone = phone[1..];

        // Telefon kullanıcının telefonuyla eşleşmeli
        if (user.PhoneNumber != phone)
            return BadRequest(new { message = "Doğrulanan numara hesabınızdaki numara ile eşleşmiyor.", code = "auth_phone_mismatch" });

        user.IsPhoneVerified = true;
        user.FirebaseUid ??= vUser.Uid;
        await _db.SaveChangesAsync(ct);

        return Ok(ToUserDto(user));
    }

    // ── Hesap Doğrulama — Twilio Verify API ─────────────────────────

    /// <summary>
    /// Twilio Verify API ile telefon doğrulama kodu gönderir.
    /// Kullanıcı giriş yapmış olmalıdır.
    /// </summary>
    [HttpPost("verify/phone/twilio/send")]
    [Authorize]
    [EnableRateLimiting("otp")]
    public async Task<IActionResult> SendPhoneVerificationTwilio(CancellationToken ct)
    {
        var userId = User.GetUserId();
        var user = await _db.Users.FindAsync(new object[] { userId }, ct);
        if (user == null) return Unauthorized();

        if (user.IsPhoneVerified)
            return BadRequest(new { message = "Telefon zaten doğrulanmış." });

        if (string.IsNullOrWhiteSpace(user.PhoneNumber))
            return BadRequest(new { message = "Hesabınızda telefon numarası tanımlı değil." });

        var sendResult = await _twilioVerify.SendVerificationAsync(user.PhoneNumber);

        return sendResult switch
        {
            TwilioVerifyService.SendResult.Sent => Ok(new { message = "Doğrulama kodu gönderildi." }),
            TwilioVerifyService.SendResult.TooSoon => StatusCode(429, new { message = "Yeni kod için lütfen bekleyin.", code = "auth_otp_too_soon" }),
            _ => StatusCode(500, new { message = "SMS gönderilemedi. Lütfen tekrar deneyin.", code = "auth_otp_failed" })
        };
    }

    /// <summary>
    /// Twilio Verify API kodu ile telefon doğrulamasını tamamlar.
    /// Kullanıcı giriş yapmış olmalıdır.
    /// </summary>
    [HttpPost("verify/phone/twilio")]
    [Authorize]
    public async Task<IActionResult> VerifyPhoneTwilio(VerifyCodeRequest request, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var user = await _db.Users.FindAsync(new object[] { userId }, ct);
        if (user == null) return Unauthorized();

        if (user.IsPhoneVerified)
            return Ok(ToUserDto(user));

        if (string.IsNullOrWhiteSpace(user.PhoneNumber))
            return BadRequest(new { message = "Hesabınızda telefon numarası tanımlı değil." });

        if (string.IsNullOrWhiteSpace(request.Code) || request.Code.Length < 4)
            return BadRequest(new { message = "Doğrulama kodunu girin." });

        var isDev = _environment.IsDevelopment();

        if (!isDev)
        {
            var verifyResult = await _twilioVerify.CheckVerificationAsync(user.PhoneNumber, request.Code);
            if (verifyResult != TwilioVerifyService.VerifyResult.Success)
            {
                return verifyResult switch
                {
                    TwilioVerifyService.VerifyResult.Expired => BadRequest(new { message = "Kodun süresi dolmuş.", code = "auth_otp_expired" }),
                    TwilioVerifyService.VerifyResult.TooManyAttempts => StatusCode(429, new { message = "Çok fazla hatalı deneme.", code = "auth_otp_blocked" }),
                    _ => BadRequest(new { message = "Geçersiz kod.", code = "auth_otp_invalid" })
                };
            }
        }

        user.IsPhoneVerified = true;
        await _db.SaveChangesAsync(ct);

        return Ok(ToUserDto(user));
    }

    // ── Token ──────────────────────────────────────────────────────

    [HttpPost("refresh")]
    [HttpPost("refresh-token")]
    [AllowAnonymous]
    public async Task<IActionResult> RefreshToken(RefreshTokenRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.RefreshToken))
            return Unauthorized(new { code = "auth_refresh_invalid" });

        var rotated = await _tokenService.RotateRefreshTokenAsync(request.RefreshToken, ClientIp, ct);
        if (!rotated.Success)
            return Unauthorized(new { code = rotated.ErrorCode ?? "auth_refresh_invalid" });

        var user = rotated.User!;
        var newRefreshToken = rotated.NewRefreshToken!;
        if (!string.IsNullOrWhiteSpace(request.Role))
        {
            var reqRole = ResolveRequestedRole(request.Role);
            if (reqRole == UserRole.Admin && user.Role != UserRole.Admin)
            {
                await _tokenService.RevokeAllAsync(user.Id, false, ct);
                return Unauthorized(new { code = "auth_role_mismatch" });
            }
        }
        var accessToken = _tokenService.CreateAccessToken(user, user.BarberProfile?.Id);
        return Ok(new AuthResponse(accessToken, newRefreshToken, ToUserDto(user)));
    }

    [HttpPost("logout")]
    [Authorize]
    public async Task<IActionResult> Logout(RefreshTokenRequest request, CancellationToken ct)
    {
        if (!string.IsNullOrWhiteSpace(request.RefreshToken))
            await _tokenService.RevokeRefreshTokenAsync(User.GetUserId(), request.RefreshToken, ct);
        return Ok(new { message = "Çıkış yapıldı." });
    }

    [HttpPost("logout-all")]
    [Authorize]
    public async Task<IActionResult> LogoutAll(CancellationToken ct)
    {
        await _tokenService.RevokeAllAsync(User.GetUserId(), true, ct);
        return Ok(new { code = "auth_session_revoked" });
    }

    [HttpGet("me")]
    [Authorize]
    public async Task<IActionResult> Me(CancellationToken ct)
    {
        var user = await _db.Users.Include(u => u.BarberProfile)
            .FirstOrDefaultAsync(u => u.Id == User.GetUserId(), ct);
        if (user == null) return Unauthorized();
        if (user.AccountStatus == AccountStatus.DeletionPending)
            return StatusCode(403, new { code = "client_profile_deletion_pending" });

        var ratingStats = await _db.Ratings
            .Where(r => r.RatedUserId == user.Id)
            .GroupBy(r => 1)
            .Select(g => new { Avg = g.Average(r => (double)r.Score), Count = g.Count() })
            .FirstOrDefaultAsync(ct);

        return Ok(ToUserDto(user,
            ratingStats == null ? null : Math.Round(ratingStats.Avg, 1),
            ratingStats?.Count ?? 0));
    }

    /// <summary>Hesap silme (soft delete). Hem müşteri hem işletme için.</summary>
    [HttpDelete("account")]
    [Authorize]
    public async Task<IActionResult> DeleteAccount(CancellationToken ct)
    {
        var userId = User.GetUserId();
        var user = await _db.Users.Include(u => u.BarberProfile)
            .FirstOrDefaultAsync(u => u.Id == userId, ct);
        if (user == null) return Unauthorized();

        // Soft delete: DeletionPending olarak işaretle
        user.AccountStatus = AccountStatus.DeletionPending;
        user.DeletionRequestedAt = DateTime.UtcNow;

        // İşletme profilini çevrimdışı yap
        if (user.BarberProfile != null)
        {
            user.BarberProfile.IsOnline = false;
        }

        // Firebase hesabını devre dışı bırak
        if (!string.IsNullOrEmpty(user.FirebaseUid))
        {
            try
            {
                await FirebaseAuth.DefaultInstance.UpdateUserAsync(
                    new FirebaseAdmin.Auth.UserRecordArgs
                    {
                        Uid = user.FirebaseUid,
                        Disabled = true,
                    },
                    ct);
            }
            catch
            {
                // Firebase hatası kritik değil — DB güncellemesi yeterli
            }
        }

        await _db.SaveChangesAsync(ct);

        // Tüm refresh token'ları geçersiz kıl
        await _tokenService.RevokeAllAsync(userId, false, ct);

        return Ok(new { message = "Hesap silme talebi alındı." });
    }

    /// <summary>Kullanıcının bildirim tercihlerini döner.</summary>
    [HttpGet("notification-preferences")]
    [Authorize]
    public async Task<IActionResult> GetNotificationPreferences(CancellationToken ct)
    {
        var userId = User.GetUserId();
        var prefs = await _db.UserNotificationPreferences
            .FirstOrDefaultAsync(p => p.UserId == userId, ct);

        return Ok(prefs?.ToDictionary() ?? UserNotificationPreference.Defaults());
    }

    /// <summary>Kullanıcının bildirim tercihlerini günceller.</summary>
    [HttpPut("notification-preferences")]
    [Authorize]
    public async Task<IActionResult> UpdateNotificationPreferences(
        [FromBody] Dictionary<string, bool> prefs,
        CancellationToken ct)
    {
        var userId = User.GetUserId();
        var entity = await _db.UserNotificationPreferences
            .FirstOrDefaultAsync(p => p.UserId == userId, ct);

        if (entity == null)
        {
            entity = new UserNotificationPreference { UserId = userId };
            _db.UserNotificationPreferences.Add(entity);
        }

        entity.SetFromDictionary(prefs);
        await _db.SaveChangesAsync(ct);

        return Ok(new { message = "Tercihler kaydedildi." });
    }

    private IActionResult HandleFirebaseVerifyError(FirebaseVerificationResult verifyResult)
    {
        var errCode = verifyResult.ErrorCode ?? "auth_google_invalid_token";
        if (errCode == "auth_google_configuration_error" || errCode == "auth_google_service_error")
        {
            return StatusCode(503, new { message = "Google doğrulama servisi geçici olarak kullanılamıyor.", code = errCode });
        }
        return Unauthorized(new { message = "Google doğrulaması başarısız oldu.", code = errCode });
    }

    private static bool IsKnownRole(string? role) => (role ?? "").Trim().ToLowerInvariant() switch
    {
        "musteri" or "berber" or "isletme" or "işletme" or "hizmetveren" => true,
        _ => false
    };

    private static UserDto ToUserDto(User user, double? avgRating = null, int ratingCount = 0) => new(
        user.Id,
        user.PhoneNumber,
        user.Role.ToString(),
        user.FirstName,
        user.LastName,
        user.Email,
        user.OnboardingCompleted,
        user.BarberProfile?.Status,
        user.BarberProfile?.RejectionReason,
        avgRating,
        ratingCount,
        user.EmailVerified,
        user.IsPhoneVerified);

    private static UserRole ResolveRequestedRole(string? role)
        => role?.Trim().ToLowerInvariant() switch
        {
            "berber" => UserRole.Berber,
            "isletme" => UserRole.Berber,
            "işletme" => UserRole.Berber,
            "hizmetveren" => UserRole.Berber,
            _ => UserRole.Musteri
        };

    private static string AccountStatusCode(AccountStatus status) => status switch
    {
        AccountStatus.Pending => "auth_account_pending",
        AccountStatus.Deleted => "auth_account_deleted",
        _ => "auth_account_inactive"
    };

    private static bool IsUniqueConstraintViolation(DbUpdateException ex)
    {
        var inner = ex.InnerException;
        while (inner != null)
        {
            if (inner is Npgsql.PostgresException pgEx && pgEx.SqlState == "23505")
                return true;

            if (inner.GetType().Name == "SqliteException")
                return true;

            if (inner.Message.Contains("UNIQUE constraint failed", StringComparison.OrdinalIgnoreCase) ||
                inner.Message.Contains("23505", StringComparison.OrdinalIgnoreCase))
                return true;

            inner = inner.InnerException;
        }
        return false;
    }
}
