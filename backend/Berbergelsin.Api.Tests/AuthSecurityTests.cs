using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Entities;
using Berbergelsin.Api.Enums;
using Berbergelsin.Api.Services;
using Berbergelsin.Api.Auth;
using Berbergelsin.Api.Hubs;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;
using Xunit;

namespace Berbergelsin.Api.Tests;

public sealed class AuthSecurityTests
{
    private const string Key = "task-118-integration-test-key-at-least-32-chars";
    private const string Issuer = "task118-tests";
    private const string Audience = "task118-mobile";

    [Fact]
    public async Task Admin_bootstrap_is_not_available_outside_development()
    {
        using var factory = new RealJwtFactory();
        using var client = factory.CreateClient();

        var response = await client.PostAsJsonAsync("/api/auth/admin-bootstrap", new { phone = "synthetic" });

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public void SignalR_groups_are_token_version_scoped_and_no_arbitrary_group_api_is_exposed()
    {
        var user = Guid.NewGuid();
        Assert.NotEqual(SessionGroups.User(user, 1), SessionGroups.User(user, 2));
        Assert.DoesNotContain(typeof(AppHub).GetMethods(), method =>
            method.DeclaringType == typeof(AppHub) && method.GetParameters().Any(p => p.Name?.Contains("group", StringComparison.OrdinalIgnoreCase) == true));
    }

    [Fact]
    public async Task Valid_token_is_accepted_but_role_version_and_status_are_checked_against_database()
    {
        using var factory = new RealJwtFactory();
        var user = factory.Seed(UserRole.Musteri, AccountStatus.Active, tokenVersion: 3);
        Assert.Equal(HttpStatusCode.OK, (await Get(factory, Token(user, "Musteri", 3))).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await Get(factory, Token(user, "Berber", 3))).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await Get(factory, Token(user, "Musteri", 2))).StatusCode);
        factory.SetStatus(user, AccountStatus.Blocked);
        Assert.Equal(HttpStatusCode.Unauthorized, (await Get(factory, Token(user, "Musteri", 3))).StatusCode);

        var pending = factory.Seed(UserRole.Musteri, AccountStatus.Pending);
        Assert.Equal(HttpStatusCode.Unauthorized, (await Get(factory, Token(pending, "Musteri", 0))).StatusCode);
        var pendingClient = factory.CreateClient();
        pendingClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", Token(pending, "Musteri", 0));
        Assert.Equal(HttpStatusCode.OK, (await pendingClient.GetAsync("/api/auth/me")).StatusCode);
    }

    [Fact]
    public async Task Jwt_rejects_expired_wrong_issuer_audience_signature_and_missing_required_claims()
    {
        using var factory = new RealJwtFactory();
        var user = factory.Seed(UserRole.Musteri, AccountStatus.Active);
        var invalid = new[]
        {
            Token(user, "Musteri", 0, expires: DateTime.UtcNow.AddMinutes(-2)),
            Token(user, "Musteri", 0, issuer: "wrong"),
            Token(user, "Musteri", 0, audience: "wrong"),
            Token(user, "Musteri", 0, key: "different-integration-test-key-at-least-32"),
            Token(null, "Musteri", 0),
            Token(user, null, 0),
            "malformed.jwt"
        };
        foreach (var token in invalid)
            Assert.Equal(HttpStatusCode.Unauthorized, (await Get(factory, token)).StatusCode);
    }

    [Fact]
    public async Task Refresh_tokens_are_hashed_rotated_reuse_detected_and_logout_all_invalidates_access_version()
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase($"auth-token-{Guid.NewGuid()}").Options;
        await using var db = new AppDbContext(options);
        var user = new User { Id = Guid.NewGuid(), PhoneNumber = "905550001118", Role = UserRole.Musteri,
            AccountStatus = AccountStatus.Active, CreatedAt = DateTime.UtcNow };
        db.Users.Add(user); await db.SaveChangesAsync();
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Jwt:Key"] = Key, ["Jwt:Issuer"] = Issuer, ["Jwt:Audience"] = Audience,
            ["Jwt:RefreshTokenDays"] = "30"
        }).Build();
        var service = new TokenService(db, config);
        var raw = await service.CreateRefreshTokenAsync(user, "test-device");
        Assert.DoesNotContain(raw, db.RefreshTokens.Single().TokenHash);
        var rotated = await service.RotateRefreshTokenAsync(raw, "test-device");
        Assert.True(rotated.Success);
        Assert.Equal("auth_refresh_reused", (await service.RotateRefreshTokenAsync(raw, "test-device")).ErrorCode);
        Assert.All(db.RefreshTokens, token => Assert.NotNull(token.RevokedAt));

        var next = await service.CreateRefreshTokenAsync(user, "test-device");
        await service.RevokeRefreshTokenAsync(user.Id, next);
        Assert.Equal("auth_refresh_reused", (await service.RotateRefreshTokenAsync(next, "test-device")).ErrorCode);
        var before = user.TokenVersion;
        await service.RevokeAllAsync(user.Id, true);
        Assert.Equal(before + 1, user.TokenVersion);
    }

    private static async Task<HttpResponseMessage> Get(RealJwtFactory factory, string token)
    {
        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return await client.GetAsync("/api/notifications/unread-count");
    }

    private static string Token(Guid? subject, string? role, int version, DateTime? expires = null,
        string issuer = Issuer, string audience = Audience, string key = Key)
    {
        var claims = new List<Claim>();
        if (subject.HasValue) claims.Add(new Claim(JwtRegisteredClaimNames.Sub, subject.Value.ToString()));
        if (role != null)
        {
            claims.Add(new Claim(ClaimTypes.Role, role));
            claims.Add(new Claim("accountRole", role));
        }
        claims.Add(new Claim("tokenVersion", version.ToString()));
        var jwt = new JwtSecurityToken(issuer, audience, claims, DateTime.UtcNow.AddMinutes(-3),
            expires ?? DateTime.UtcNow.AddMinutes(5),
            new SigningCredentials(new SymmetricSecurityKey(Encoding.UTF8.GetBytes(key)), SecurityAlgorithms.HmacSha256));
        return new JwtSecurityTokenHandler().WriteToken(jwt);
    }

    private sealed class RealJwtFactory : WebApplicationFactory<Program>
    {
        private readonly string database = $"task118-{Guid.NewGuid()}";
        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment("Testing");
            builder.UseSetting("Jwt:Key", Key);
            builder.UseSetting("Jwt:Issuer", Issuer);
            builder.UseSetting("Jwt:Audience", Audience);
            builder.ConfigureServices(services =>
            {
                services.RemoveAll<DbContextOptions<AppDbContext>>();
                services.AddDbContext<AppDbContext>(o => o.UseInMemoryDatabase(database));
            });
        }

        public Guid Seed(UserRole role, AccountStatus status, int tokenVersion = 0)
        {
            using var scope = Services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var id = Guid.NewGuid();
            db.Users.Add(new User { Id = id, PhoneNumber = $"905{id.ToString("N")[..10]}", Role = role,
                AccountStatus = status, TokenVersion = tokenVersion, CreatedAt = DateTime.UtcNow });
            db.SaveChanges();
            return id;
        }

        public void SetStatus(Guid id, AccountStatus status)
        {
            using var scope = Services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            db.Users.Single(u => u.Id == id).AccountStatus = status;
            db.SaveChanges();
        }
    }
}
