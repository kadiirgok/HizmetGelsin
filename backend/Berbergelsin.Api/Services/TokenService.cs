using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Entities;
using Berbergelsin.Api.Enums;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

namespace Berbergelsin.Api.Services;

public class TokenService
{
    public sealed record RefreshRotationResult(User? User, string? NewRefreshToken, string? ErrorCode)
    {
        public bool Success => User != null && NewRefreshToken != null;
    }
    private readonly AppDbContext _db;
    private readonly IConfiguration _config;

    public TokenService(AppDbContext db, IConfiguration config)
    {
        _db = db;
        _config = config;
    }

    public string CreateAccessToken(User user, Guid? barberProfileId)
    {
        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new("phone", user.PhoneNumber),
            new(ClaimTypes.Role, user.Role.ToString()),
            new("accountRole", user.Role.ToString()),
            new("tokenVersion", user.TokenVersion.ToString(System.Globalization.CultureInfo.InvariantCulture)),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString())
        };

        if (user.Role == UserRole.Berber)
        {
            claims.Add(new Claim(ClaimTypes.Role, UserRole.Musteri.ToString()));
        }
        else if (user.Role == UserRole.Admin)
        {
            claims.Add(new Claim(ClaimTypes.Role, UserRole.Musteri.ToString()));
            claims.Add(new Claim(ClaimTypes.Role, UserRole.Berber.ToString()));
        }

        if (barberProfileId.HasValue)
            claims.Add(new Claim("barberProfileId", barberProfileId.Value.ToString()));

        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_config["Jwt:Key"]!));
        var token = new JwtSecurityToken(
            issuer: _config["Jwt:Issuer"],
            audience: _config["Jwt:Audience"],
            claims: claims,
            notBefore: DateTime.UtcNow,
            expires: DateTime.UtcNow.AddMinutes(_config.GetValue("Jwt:AccessTokenMinutes", 15)),
            signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256));

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    public async Task<string> CreateRefreshTokenAsync(User user, string? ip, CancellationToken ct = default)
    {
        // En fazla 5 aktif refresh token tut, eskileri iptal et
        const int maxTokens = 5;
        var activeCount = await _db.RefreshTokens
            .CountAsync(t => t.UserId == user.Id && t.RevokedAt == null && t.ExpiresAt > DateTime.UtcNow, ct);
        if (activeCount >= maxTokens)
        {
            var oldest = await _db.RefreshTokens
                .Where(t => t.UserId == user.Id && t.RevokedAt == null)
                .OrderBy(t => t.CreatedAt)
                .Take(activeCount - maxTokens + 1)
                .ToListAsync(ct);
            foreach (var t in oldest) t.RevokedAt = DateTime.UtcNow;
        }

        var raw = Convert.ToBase64String(RandomNumberGenerator.GetBytes(64))
            .Replace('+', '-').Replace('/', '_').TrimEnd('=');

        _db.RefreshTokens.Add(new RefreshToken
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            TokenHash = Hash(raw),
            ExpiresAt = DateTime.UtcNow.AddDays(_config.GetValue("Jwt:RefreshTokenDays", 30)),
            CreatedAt = DateTime.UtcNow,
            CreatedByIp = ip
        });
        await _db.SaveChangesAsync(ct);
        return raw;
    }

    /// <summary>Rotasyon: eski token revoke edilir, yenisi verilir. Revoke edilmiş token
    /// tekrar kullanılırsa kullanıcının tüm aktif tokenları iptal edilir (çalıntı tespiti).</summary>
    public async Task<RefreshRotationResult> RotateRefreshTokenAsync(
        string rawToken, string? ip, CancellationToken ct = default)
    {
        var hash = Hash(rawToken);
        var token = await _db.RefreshTokens
            .Include(t => t.User).ThenInclude(u => u.BarberProfile)
            .FirstOrDefaultAsync(t => t.TokenHash == hash, ct);

        if (token == null) return new(null, null, "auth_refresh_invalid");

        if (token.User.AccountStatus is not (AccountStatus.Active or AccountStatus.Pending))
        {
            await RevokeActiveRowsAsync(token.UserId, ct);
            return new(null, null, token.User.AccountStatus == AccountStatus.Deleted
                ? "auth_account_deleted" : "auth_account_inactive");
        }

        if (token.RevokedAt != null)
        {
            // Çalıntı şüphesi: bu kullanıcının tüm aktif tokenlarını iptal et
            await RevokeActiveRowsAsync(token.UserId, ct);
            return new(null, null, "auth_refresh_reused");
        }

        if (token.ExpiresAt <= DateTime.UtcNow) return new(null, null, "auth_refresh_invalid");

        var raw = Convert.ToBase64String(RandomNumberGenerator.GetBytes(64))
            .Replace('+', '-').Replace('/', '_').TrimEnd('=');
        var newHash = Hash(raw);

        token.RevokedAt = DateTime.UtcNow;
        token.ReplacedByTokenHash = newHash;
        _db.RefreshTokens.Add(new RefreshToken
        {
            Id = Guid.NewGuid(),
            UserId = token.UserId,
            TokenHash = newHash,
            ExpiresAt = DateTime.UtcNow.AddDays(_config.GetValue("Jwt:RefreshTokenDays", 30)),
            CreatedAt = DateTime.UtcNow,
            CreatedByIp = ip
        });
        await _db.SaveChangesAsync(ct);
        return new(token.User, raw, null);
    }

    public async Task RevokeRefreshTokenAsync(Guid userId, string rawToken, CancellationToken ct = default)
    {
        var hash = Hash(rawToken);
        var token = await _db.RefreshTokens
            .FirstOrDefaultAsync(t => t.UserId == userId && t.TokenHash == hash && t.RevokedAt == null, ct);
        if (token != null)
        {
            token.RevokedAt = DateTime.UtcNow;
            await _db.SaveChangesAsync(ct);
        }
    }

    public async Task RevokeAllAsync(Guid userId, bool incrementTokenVersion, CancellationToken ct = default)
    {
        await RevokeActiveRowsAsync(userId, ct);
        if (incrementTokenVersion)
        {
            var user = await _db.Users.FirstOrDefaultAsync(u => u.Id == userId, ct);
            if (user != null)
            {
                user.TokenVersion++;
                await _db.SaveChangesAsync(ct);
            }
        }
    }

    private async Task RevokeActiveRowsAsync(Guid userId, CancellationToken ct)
    {
        var active = await _db.RefreshTokens.Where(t => t.UserId == userId && t.RevokedAt == null).ToListAsync(ct);
        var now = DateTime.UtcNow;
        foreach (var row in active) row.RevokedAt = now;
        if (active.Count > 0) await _db.SaveChangesAsync(ct);
    }

    private static string Hash(string raw)
        => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(raw)));
}
