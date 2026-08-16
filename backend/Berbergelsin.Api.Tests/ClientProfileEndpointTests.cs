using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Entities;
using Berbergelsin.Api.Enums;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using NetTopologySuite.Geometries;
using Xunit;

namespace Berbergelsin.Api.Tests;

public sealed class ClientProfileEndpointTests
{
    [Fact]
    public async Task Get_requires_authentication_and_customer_session_and_account_role()
    {
        using var f = new ClientProfileApiFactory();
        Assert.Equal(HttpStatusCode.Unauthorized, (await f.CreateClient().GetAsync("/api/client/profile")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await f.Client(f.BarberId, "Berber").GetAsync("/api/client/profile")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await f.Client(f.BarberId, "Musteri").GetAsync("/api/client/profile")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await f.Client(f.ClientId, "Musteri").GetAsync("/api/client/profile")).StatusCode);
    }

    [Fact]
    public async Task Get_returns_only_own_safe_contract()
    {
        using var f = new ClientProfileApiFactory();
        using var json = JsonDocument.Parse(await f.Client(f.ClientId, "Musteri").GetStringAsync("/api/client/profile"));
        var root = json.RootElement;
        Assert.Equal(f.ClientId, root.GetProperty("id").GetGuid());
        Assert.Equal(new[] { "createdAt", "email", "firstName", "id", "isPhoneVerified", "lastName", "phoneNumber", "profileImageUrl", "version" },
            root.EnumerateObject().Select(x => x.Name).Order().ToArray());
        Assert.DoesNotContain("refresh", root.GetRawText(), StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(f.OtherClientId.ToString(), root.GetRawText());
    }

    [Fact]
    public async Task Update_trims_normalizes_and_rotates_version()
    {
        using var f = new ClientProfileApiFactory();
        var c = f.Client(f.ClientId, "Musteri");
        var version = await Version(c);
        using var response = await c.PutAsJsonAsync("/api/client/profile", new
        {
            firstName = "  Ayşe ", lastName = " Yılmaz  ", email = " AYSE@EXAMPLE.COM ",
            profileImageUrl = "https://cdn.example.com/Ayse.JPG", version
        });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var json = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("Ayşe", json.GetProperty("firstName").GetString());
        Assert.Equal("ayse@example.com", json.GetProperty("email").GetString());
        Assert.Equal("https://cdn.example.com/Ayse.JPG", json.GetProperty("profileImageUrl").GetString());
        Assert.NotEqual(version, json.GetProperty("version").GetString());
    }

    [Theory]
    [InlineData(" ", "Soyad", "a@b.com", "https://cdn.example.com/a.jpg")]
    [InlineData("Ad", " ", "a@b.com", "https://cdn.example.com/a.jpg")]
    [InlineData("Ad", "Soyad", "not-email", "https://cdn.example.com/a.jpg")]
    [InlineData("Ad", "Soyad", "a@b.com", "http://cdn.example.com/a.jpg")]
    public async Task Update_rejects_invalid_values(string first, string last, string email, string image)
    {
        using var f = new ClientProfileApiFactory(); var c = f.Client(f.ClientId, "Musteri");
        using var response = await c.PutAsJsonAsync("/api/client/profile", new { firstName = first, lastName = last, email, profileImageUrl = image, version = await Version(c) });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Contains("client_profile_invalid", await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task Update_rejects_long_and_duplicate_email()
    {
        using var f = new ClientProfileApiFactory(); var c = f.Client(f.ClientId, "Musteri");
        Assert.Equal(HttpStatusCode.BadRequest, (await c.PutAsJsonAsync("/api/client/profile", new { firstName = new string('x', 101), lastName = "Y", version = await Version(c) })).StatusCode);
        using var duplicate = await c.PutAsJsonAsync("/api/client/profile", new { firstName = "A", lastName = "Y", email = "other@example.com", version = await Version(c) });
        Assert.Equal(HttpStatusCode.Conflict, duplicate.StatusCode);
        Assert.Contains("client_profile_email_in_use", await duplicate.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task Update_blocks_stale_concurrency_version()
    {
        using var f = new ClientProfileApiFactory(); var c = f.Client(f.ClientId, "Musteri");
        var version = await Version(c);
        Assert.Equal(HttpStatusCode.OK, (await c.PutAsJsonAsync("/api/client/profile", new { firstName = "A", lastName = "B", version })).StatusCode);
        using var stale = await c.PutAsJsonAsync("/api/client/profile", new { firstName = "C", lastName = "D", version });
        Assert.Equal(HttpStatusCode.Conflict, stale.StatusCode);
        Assert.Contains("client_profile_conflict", await stale.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task Overposting_cannot_change_identity_phone_role_or_verification()
    {
        using var f = new ClientProfileApiFactory(); var c = f.Client(f.ClientId, "Musteri");
        using var response = await c.PutAsJsonAsync("/api/client/profile", new { firstName = "A", lastName = "B", version = await Version(c), id = f.OtherClientId, role = "Admin", phoneNumber = "90000000000", isPhoneVerified = false, accountStatus = "Active", unknown = "ignored" });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var json = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(f.ClientId, json.GetProperty("id").GetGuid());
        Assert.Equal("905551111111", json.GetProperty("phoneNumber").GetString());
        Assert.True(json.GetProperty("isPhoneVerified").GetBoolean());
    }

    [Fact]
    public async Task Delete_is_authorized_idempotent_preserves_user_and_revokes_sessions()
    {
        using var f = new ClientProfileApiFactory();
        Assert.Equal(HttpStatusCode.Unauthorized, (await f.CreateClient().DeleteAsync("/api/client/profile")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await f.Client(f.BarberId, "Berber").DeleteAsync("/api/client/profile")).StatusCode);
        var c = f.Client(f.ClientId, "Musteri");
        Assert.Equal(HttpStatusCode.OK, (await c.DeleteAsync("/api/client/profile")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await c.DeleteAsync("/api/client/profile")).StatusCode);
        using var scope = f.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var user = await db.Users.SingleAsync(x => x.Id == f.ClientId);
        Assert.Equal(AccountStatus.DeletionPending, user.AccountStatus);
        Assert.NotNull(user.DeletionRequestedAt);
        Assert.True(await db.RefreshTokens.Where(x => x.UserId == f.ClientId).AllAsync(x => x.RevokedAt != null));
        Assert.True(await db.ServiceRequests.AnyAsync(x => x.ClientUserId == f.ClientId));
        var pending = await c.GetAsync("/api/client/profile");
        Assert.Equal(HttpStatusCode.Conflict, pending.StatusCode);
        Assert.Contains("client_profile_deletion_pending", await pending.Content.ReadAsStringAsync());
    }

    private static async Task<string> Version(HttpClient c) => (await c.GetFromJsonAsync<JsonElement>("/api/client/profile")).GetProperty("version").GetString()!;
}

public sealed class ClientProfileApiFactory : WebApplicationFactory<Program>
{
    private bool _seeded;
    public Guid ClientId { get; } = Guid.NewGuid();
    public Guid OtherClientId { get; } = Guid.NewGuid();
    public Guid BarberId { get; } = Guid.NewGuid();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.UseSetting("Jwt:Key", "integration-test-key-with-at-least-32-characters");
        builder.UseSetting("Jwt:Issuer", "integration-tests"); builder.UseSetting("Jwt:Audience", "integration-tests");
        builder.UseSetting("SmsSettings:UseConsoleSender", "true");
        builder.ConfigureServices(services =>
        {
            var databaseName = $"client-profile-{ClientId}";
            services.RemoveAll<DbContextOptions<AppDbContext>>();
            services.AddDbContext<AppDbContext>(o => o.UseInMemoryDatabase(databaseName));
            services.AddAuthentication(o => { o.DefaultAuthenticateScheme = "ClientProfileTest"; o.DefaultChallengeScheme = "ClientProfileTest"; o.DefaultForbidScheme = "ClientProfileTest"; }).AddScheme<AuthenticationSchemeOptions, ClientProfileTestAuthHandler>("ClientProfileTest", _ => { });
        });
    }

    public HttpClient Client(Guid id, string role)
    {
        var c = CreateClient();
        if (!_seeded)
        {
            using var scope = Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var client = new User { Id = ClientId, PhoneNumber = "905551111111", Role = UserRole.Musteri, FirstName = "Client", LastName = "One", Email = "client@example.com", OnboardingCompleted = true, CreatedAt = DateTime.UtcNow };
            var other = new User { Id = OtherClientId, PhoneNumber = "905552222222", Role = UserRole.Musteri, FirstName = "Other", LastName = "Client", Email = "other@example.com", CreatedAt = DateTime.UtcNow };
            var barber = new User { Id = BarberId, PhoneNumber = "905553333333", Role = UserRole.Berber, CreatedAt = DateTime.UtcNow };
            var profile = new BarberProfile { Id = Guid.NewGuid(), UserId = BarberId, User = barber, Status = BarberStatus.Approved, CreatedAt = DateTime.UtcNow };
            db.Users.AddRange(client, other, barber); db.BarberProfiles.Add(profile);
            db.ServiceRequests.Add(new ServiceRequest { Id = Guid.NewGuid(), ClientUserId = ClientId, ClientUser = client, BarberProfileId = profile.Id, BarberProfile = profile, Status = RequestStatus.Accepted, RequestedTime = DateTimeOffset.UtcNow.AddHours(1), ClientLocation = new Point(29, 41) { SRID = 4326 }, CreatedAt = DateTime.UtcNow });
            db.RefreshTokens.Add(new RefreshToken { Id = Guid.NewGuid(), UserId = ClientId, TokenHash = Guid.NewGuid().ToString("N"), CreatedAt = DateTime.UtcNow, ExpiresAt = DateTime.UtcNow.AddDays(1) });
            db.SaveChanges(); _seeded = true;
        }
        c.DefaultRequestHeaders.Add("X-Test-UserId", id.ToString()); c.DefaultRequestHeaders.Add("X-Test-Role", role); return c;
    }
}

public sealed class ClientProfileTestAuthHandler(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue("X-Test-UserId", out var id)) return Task.FromResult(AuthenticateResult.NoResult());
        var role = Request.Headers["X-Test-Role"].ToString();
        var claims = new[] { new Claim(ClaimTypes.NameIdentifier, id.ToString()), new Claim(ClaimTypes.Role, role) };
        return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(new ClaimsIdentity(claims, Scheme.Name)), Scheme.Name)));
    }
}
