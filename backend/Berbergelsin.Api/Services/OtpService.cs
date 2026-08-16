using System.Security.Cryptography;
using System.Text;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Hosting;

namespace Berbergelsin.Api.Services;

public class OtpService
{
    private readonly AppDbContext _db;
    private readonly ISmsSender _smsSender;
    private readonly IEmailSender _emailSender;
    private readonly IOtpCodeGenerator _codeGenerator;
    private readonly IConfiguration _config;
    private readonly ILogger<OtpService> _logger;
    private readonly IHostEnvironment _env;
    private readonly DevOtpStore? _devOtpStore;
    private readonly EmailLogoProvider? _logoProvider;

    public OtpService(
        AppDbContext db,
        ISmsSender smsSender,
        IEmailSender emailSender,
        IOtpCodeGenerator codeGenerator,
        IConfiguration config,
        ILogger<OtpService> logger,
        IHostEnvironment env,
        DevOtpStore? devOtpStore = null,
        EmailLogoProvider? logoProvider = null)
    {
        _db = db;
        _smsSender = smsSender;
        _emailSender = emailSender;
        _codeGenerator = codeGenerator;
        _config = config;
        _logger = logger;
        _env = env;
        _devOtpStore = devOtpStore;
        _logoProvider = logoProvider;
    }

    public enum SendResult { Sent, TooSoon, TooMany, SmsFailed }
    public enum VerifyResult { Success, Invalid, Expired, TooManyAttempts }

    public async Task<SendResult> SendOtpAsync(
        string phone,
        string? requestIp,
        OtpPurpose purpose = OtpPurpose.Login,
        string? subject = null,
        CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        var resendSeconds = _config.GetValue("Otp:ResendSeconds", 60);
        var maxSends = _config.GetValue("Otp:MaxSendsPer10Min", 3);

        var latest = await _db.OtpCodes
            .Where(o => o.PhoneNumber == phone && o.Purpose == purpose)
            .OrderByDescending(o => o.CreatedAt)
            .FirstOrDefaultAsync(ct);

        if (latest != null && !latest.Consumed && latest.ExpiresAt > now
            && (now - latest.CreatedAt).TotalSeconds < resendSeconds)
            return SendResult.TooSoon;

        var recentCount = await _db.OtpCodes
            .CountAsync(o => o.PhoneNumber == phone && o.Purpose == purpose && o.CreatedAt > now.AddMinutes(-10), ct);
        if (recentCount >= maxSends)
            return SendResult.TooMany;

        var code = _codeGenerator.GenerateCode();
        var expiry = _config.GetValue("Otp:ExpiryMinutes", 5);

        // Invalidate previous unconsumed codes for this phone and purpose
        if (_db.Database.IsRelational())
        {
            await _db.OtpCodes
                .Where(o => o.PhoneNumber == phone && o.Purpose == purpose && !o.Consumed)
                .ExecuteUpdateAsync(s => s.SetProperty(o => o.Consumed, true), ct);
        }
        else
        {
            var unconsumed = await _db.OtpCodes
                .Where(o => o.PhoneNumber == phone && o.Purpose == purpose && !o.Consumed)
                .ToListAsync(ct);
            foreach (var o in unconsumed) o.Consumed = true;
        }

        var newOtp = new OtpCode
        {
            Id = Guid.NewGuid(),
            PhoneNumber = phone,
            Purpose = purpose,
            Subject = subject,
            CodeHash = Hash(code),
            ExpiresAt = now.AddMinutes(expiry),
            RequestIp = requestIp,
            CreatedAt = now
        };
        _db.OtpCodes.Add(newOtp);
        await _db.SaveChangesAsync(ct);

        try
        {
            await _smsSender.SendAsync(phone, $"HizmetGelsin doğrulama kodunuz: {code}", ct);
            _devOtpStore?.Store(phone, code);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "SMS gönderimi başarısız.");
            newOtp.Consumed = true; // Invalidate created OTP code on SMS failure so user isn't locked out
            await _db.SaveChangesAsync(ct);
            return SendResult.SmsFailed;
        }

        return SendResult.Sent;
    }

    public async Task<SendResult> SendEmailOtpAsync(
        string email,
        string? requestIp,
        OtpPurpose purpose = OtpPurpose.Login,
        string? subject = null,
        CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        var resendSeconds = _config.GetValue("Otp:ResendSeconds", 60);
        var maxSends = _config.GetValue("Otp:MaxSendsPer10Min", 3);

        var latest = await _db.OtpCodes
            .Where(o => o.Email == email && o.Purpose == purpose)
            .OrderByDescending(o => o.CreatedAt)
            .FirstOrDefaultAsync(ct);

        if (latest != null && !latest.Consumed && latest.ExpiresAt > now
            && (now - latest.CreatedAt).TotalSeconds < resendSeconds)
            return SendResult.TooSoon;

        var recentCount = await _db.OtpCodes
            .CountAsync(o => o.Email == email && o.Purpose == purpose && o.CreatedAt > now.AddMinutes(-10), ct);
        if (recentCount >= maxSends)
            return SendResult.TooMany;

        var code = _codeGenerator.GenerateCode();
        var expiry = _config.GetValue("Otp:ExpiryMinutes", 5);

        // Invalidate previous unconsumed codes for this email and purpose
        if (_db.Database.IsRelational())
        {
            await _db.OtpCodes
                .Where(o => o.Email == email && o.Purpose == purpose && !o.Consumed)
                .ExecuteUpdateAsync(s => s.SetProperty(o => o.Consumed, true), ct);
        }
        else
        {
            var unconsumed = await _db.OtpCodes
                .Where(o => o.Email == email && o.Purpose == purpose && !o.Consumed)
                .ToListAsync(ct);
            foreach (var o in unconsumed) o.Consumed = true;
        }

        var newOtp = new OtpCode
        {
            Id = Guid.NewGuid(),
            Email = email,
            Purpose = purpose,
            Subject = subject,
            CodeHash = Hash(code),
            ExpiresAt = now.AddMinutes(expiry),
            RequestIp = requestIp,
            CreatedAt = now
        };
        _db.OtpCodes.Add(newOtp);
        await _db.SaveChangesAsync(ct);

        try
        {
            var emailSubject = "HizmetGelsin • Doğrulama Kodunuz";
            var logoHtml = @"<div style=""font-size:28px;font-weight:700;color:#FFFFFF;letter-spacing:-0.5px"">HizmetGelsin</div>";

            var htmlBody = $@"<!DOCTYPE html>
<html lang=""tr"">
<head><meta charset=""UTF-8""><meta name=""viewport"" content=""width=device-width,initial-scale=1""></head>
<body style=""margin:0;padding:0;background:#FAFAFA;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif"">
<table width=""100%"" cellpadding=""0"" cellspacing=""0"" style=""background:#FAFAFA;padding:40px 0"">
<tr><td align=""center"">
<table width=""480"" cellpadding=""0"" cellspacing=""0"" style=""background:#FFFFFF;border-radius:16px;overflow:hidden;box-shadow:0 2px 16px rgba(0,0,0,0.06)"">

<!-- Header -->
<tr><td style=""background:#111111;padding:32px 40px;text-align:center"">
{logoHtml}
<div style=""font-size:13px;color:#AAAAAA;margin-top:12px;font-weight:400"">Yanında, her an</div>
</td></tr>

<!-- Body -->
<tr><td style=""padding:40px"">

<div style=""font-size:13px;font-weight:600;color:#999999;text-transform:uppercase;letter-spacing:1px;margin-bottom:16px"">Doğrulama Kodu</div>

<div style=""background:#F8F8F8;border:1px solid #EEEEEE;border-radius:12px;padding:24px;text-align:center;margin-bottom:28px"">
<div style=""font-size:36px;font-weight:800;color:#111111;letter-spacing:8px;font-family:'SF Mono','Courier New',monospace"">{code}</div>
<div style=""font-size:12px;color:#999999;margin-top:8px"">Bu kod 5 dakika geçerlidir</div>
</div>

<div style=""font-size:14px;color:#444444;line-height:1.6;margin-bottom:28px"">
Bu kodu uygulamaya girerek girişinizi tamamlayabilirsiniz. Eğer bu işlemi siz yapmadıysanız, bu e-postayı dikkate almayın.
</div>

<!-- Divider -->
<div style=""height:1px;background:#EEEEEE;margin-bottom:24px""></div>

<!-- Footer -->
<div style=""font-size:12px;color:#B0B0B0;text-align:center;line-height:1.6"">
Bu e-posta <strong>HizmetGelsin</strong> tarafından otomatik gönderilmiştir.<br>
Yanıtlamayın.
</div>

</td></tr>
</table>
</td></tr>
</table>
</body></html>";
            await _emailSender.SendAsync(email, emailSubject, htmlBody, ct);
            _logger.LogInformation("EMAIL OTP [{Email}]: gonderildi", email);
            if (_env.IsDevelopment())
                _devOtpStore?.Store(email, code);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "E-posta gönderimi başarısız.");
            newOtp.Consumed = true;
            await _db.SaveChangesAsync(ct);
            return SendResult.SmsFailed; // We use SmsFailed as generic sending failure
        }

        return SendResult.Sent;
    }

    public async Task<VerifyResult> VerifyOtpAsync(
        string phone,
        string code,
        OtpPurpose purpose = OtpPurpose.Login,
        string? expectedSubject = null,
        CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        var maxAttempts = _config.GetValue("Otp:MaxAttempts", 5);

        var otp = await _db.OtpCodes
            .Where(o => o.PhoneNumber == phone && o.Purpose == purpose && !o.Consumed)
            .OrderByDescending(o => o.CreatedAt)
            .FirstOrDefaultAsync(ct);

        if (otp == null) return VerifyResult.Invalid;

        if (expectedSubject != null && !string.Equals(otp.Subject, expectedSubject, StringComparison.Ordinal))
        {
            return VerifyResult.Invalid;
        }

        if (otp.ExpiresAt <= now)
        {
            otp.Consumed = true;
            await _db.SaveChangesAsync(ct);
            return VerifyResult.Expired;
        }

        otp.AttemptCount++;
        if (otp.AttemptCount >= maxAttempts)
        {
            otp.Consumed = true;
            await _db.SaveChangesAsync(ct);
            return VerifyResult.TooManyAttempts;
        }

        if (!CryptographicOperations.FixedTimeEquals(
                Encoding.UTF8.GetBytes(Hash(code)),
                Encoding.UTF8.GetBytes(otp.CodeHash)))
        {
            await _db.SaveChangesAsync(ct);
            return VerifyResult.Invalid;
        }

        otp.Consumed = true;
        await _db.SaveChangesAsync(ct);
        return VerifyResult.Success;
    }

    public async Task<VerifyResult> VerifyEmailOtpAsync(
        string email,
        string code,
        OtpPurpose purpose = OtpPurpose.Login,
        string? expectedSubject = null,
        CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        var maxAttempts = _config.GetValue("Otp:MaxAttempts", 5);

        // Development kolaylığı: "000000" kodu geçerli son OTP'yi otomatik tüketir
        if (_env.IsDevelopment() && code == "000000" && _devOtpStore != null)
        {
            var devEntry = _devOtpStore.Retrieve(email);
            if (devEntry != null)
            {
                code = devEntry.Code;
            }
        }

        var otp = await _db.OtpCodes
            .Where(o => o.Email == email && o.Purpose == purpose && !o.Consumed)
            .OrderByDescending(o => o.CreatedAt)
            .FirstOrDefaultAsync(ct);

        if (otp == null) return VerifyResult.Invalid;

        if (expectedSubject != null && !string.Equals(otp.Subject, expectedSubject, StringComparison.Ordinal))
        {
            return VerifyResult.Invalid;
        }

        if (otp.ExpiresAt <= now)
        {
            otp.Consumed = true;
            await _db.SaveChangesAsync(ct);
            return VerifyResult.Expired;
        }

        otp.AttemptCount++;
        if (otp.AttemptCount >= maxAttempts)
        {
            otp.Consumed = true;
            await _db.SaveChangesAsync(ct);
            return VerifyResult.TooManyAttempts;
        }

        if (!CryptographicOperations.FixedTimeEquals(
                Encoding.UTF8.GetBytes(Hash(code)),
                Encoding.UTF8.GetBytes(otp.CodeHash)))
        {
            await _db.SaveChangesAsync(ct);
            return VerifyResult.Invalid;
        }

        otp.Consumed = true;
        await _db.SaveChangesAsync(ct);
        return VerifyResult.Success;
    }

    public async Task<VerifyResult> CheckEmailOtpAsync(
        string email,
        string code,
        OtpPurpose purpose = OtpPurpose.Login,
        string? expectedSubject = null,
        CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        var maxAttempts = _config.GetValue("Otp:MaxAttempts", 5);

        // Development kolaylığı: "000000" kodu geçerli son OTP'yi otomatik bulur
        if (_env.IsDevelopment() && code == "000000" && _devOtpStore != null)
        {
            var devEntry = _devOtpStore.Retrieve(email);
            if (devEntry != null) code = devEntry.Code;
        }

        var otp = await _db.OtpCodes
            .Where(o => o.Email == email && o.Purpose == purpose && !o.Consumed)
            .OrderByDescending(o => o.CreatedAt)
            .FirstOrDefaultAsync(ct);

        if (otp == null) return VerifyResult.Invalid;

        if (expectedSubject != null && !string.Equals(otp.Subject, expectedSubject, StringComparison.Ordinal))
        {
            return VerifyResult.Invalid;
        }

        if (otp.ExpiresAt <= now)
        {
            return VerifyResult.Expired;
        }

        otp.AttemptCount++;
        await _db.SaveChangesAsync(ct);

        if (otp.AttemptCount > maxAttempts)
        {
            return VerifyResult.TooManyAttempts;
        }

        if (!CryptographicOperations.FixedTimeEquals(
                Encoding.UTF8.GetBytes(Hash(code)),
                Encoding.UTF8.GetBytes(otp.CodeHash)))
        {
            return VerifyResult.Invalid;
        }

        return VerifyResult.Success;
    }

    public async Task<VerifyResult> TryConsumeEmailOtpAsync(
        string email,
        string code,
        OtpPurpose purpose = OtpPurpose.Login,
        string? expectedSubject = null,
        CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        var maxAttempts = _config.GetValue("Otp:MaxAttempts", 5);

        // Development kolaylığı: "000000" kodu geçerli son OTP'yi otomatik tüketir
        if (_env.IsDevelopment() && code == "000000" && _devOtpStore != null)
        {
            var devEntry = _devOtpStore.Retrieve(email);
            if (devEntry != null) code = devEntry.Code;
        }

        var otp = await _db.OtpCodes
            .Where(o => o.Email == email && o.Purpose == purpose && !o.Consumed)
            .OrderByDescending(o => o.CreatedAt)
            .FirstOrDefaultAsync(ct);

        if (otp == null) return VerifyResult.Invalid;

        if (expectedSubject != null && !string.Equals(otp.Subject, expectedSubject, StringComparison.Ordinal))
        {
            return VerifyResult.Invalid;
        }

        if (otp.ExpiresAt <= now)
        {
            otp.Consumed = true;
            await _db.SaveChangesAsync(ct);
            return VerifyResult.Expired;
        }

        otp.AttemptCount++;
        if (otp.AttemptCount >= maxAttempts)
        {
            otp.Consumed = true;
            await _db.SaveChangesAsync(ct);
            return VerifyResult.TooManyAttempts;
        }

        if (!CryptographicOperations.FixedTimeEquals(
                Encoding.UTF8.GetBytes(Hash(code)),
                Encoding.UTF8.GetBytes(otp.CodeHash)))
        {
            await _db.SaveChangesAsync(ct);
            return VerifyResult.Invalid;
        }

        if (_db.Database.IsRelational())
        {
            var affected = await _db.OtpCodes
                .Where(o => o.Id == otp.Id
                         && !o.Consumed
                         && o.Purpose == purpose
                         && o.ExpiresAt > now
                         && o.AttemptCount <= maxAttempts
                         && (expectedSubject == null || o.Subject == expectedSubject))
                .ExecuteUpdateAsync(s => s.SetProperty(o => o.Consumed, true), ct);

            if (affected != 1)
            {
                return VerifyResult.Invalid;
            }
        }
        else
        {
            if (otp.Consumed) return VerifyResult.Invalid;
            otp.Consumed = true;
            await _db.SaveChangesAsync(ct);
        }

        return VerifyResult.Success;
    }

    public async Task<VerifyResult> TryConsumeOtpAsync(
        string phone,
        string code,
        OtpPurpose purpose = OtpPurpose.Login,
        string? expectedSubject = null,
        CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        var maxAttempts = _config.GetValue("Otp:MaxAttempts", 5);

        var otp = await _db.OtpCodes
            .Where(o => o.PhoneNumber == phone && o.Purpose == purpose && !o.Consumed)
            .OrderByDescending(o => o.CreatedAt)
            .FirstOrDefaultAsync(ct);

        if (otp == null) return VerifyResult.Invalid;

        if (expectedSubject != null && !string.Equals(otp.Subject, expectedSubject, StringComparison.Ordinal))
        {
            return VerifyResult.Invalid;
        }

        if (otp.ExpiresAt <= now)
        {
            otp.Consumed = true;
            await _db.SaveChangesAsync(ct);
            return VerifyResult.Expired;
        }

        otp.AttemptCount++;
        if (otp.AttemptCount >= maxAttempts)
        {
            otp.Consumed = true;
            await _db.SaveChangesAsync(ct);
            return VerifyResult.TooManyAttempts;
        }

        if (!CryptographicOperations.FixedTimeEquals(
                Encoding.UTF8.GetBytes(Hash(code)),
                Encoding.UTF8.GetBytes(otp.CodeHash)))
        {
            await _db.SaveChangesAsync(ct);
            return VerifyResult.Invalid;
        }

        if (_db.Database.IsRelational())
        {
            var affected = await _db.OtpCodes
                .Where(o => o.Id == otp.Id
                         && !o.Consumed
                         && o.Purpose == purpose
                         && o.ExpiresAt > now
                         && o.AttemptCount <= maxAttempts
                         && (expectedSubject == null || o.Subject == expectedSubject))
                .ExecuteUpdateAsync(s => s.SetProperty(o => o.Consumed, true), ct);

            if (affected != 1)
            {
                return VerifyResult.Invalid;
            }
        }
        else
        {
            if (otp.Consumed) return VerifyResult.Invalid;
            otp.Consumed = true;
            await _db.SaveChangesAsync(ct);
        }

        return VerifyResult.Success;
    }

    private string Hash(string code)
    {
        var pepper = _config["Otp:Pepper"] ?? throw new InvalidOperationException("Otp:Pepper tanımlı değil");
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(pepper));
        return Convert.ToHexString(hmac.ComputeHash(Encoding.UTF8.GetBytes(code)));
    }
}
