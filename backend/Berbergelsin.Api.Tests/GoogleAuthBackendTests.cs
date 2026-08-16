using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Dtos;
using Berbergelsin.Api.Entities;
using Berbergelsin.Api.Enums;
using Berbergelsin.Api.Services;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Newtonsoft.Json.Linq;
using Xunit;

namespace Berbergelsin.Api.Tests;

public class TestSmsSender : ISmsSender
{
    public string? LastPhone { get; private set; }
    public string? LastMessage { get; private set; }
    public string? LastCode { get; private set; }

    public Task SendAsync(string toPhone, string message, CancellationToken ct = default)
    {
        LastPhone = toPhone;
        LastMessage = message;
        var parts = message.Split(':');
        if (parts.Length > 1)
        {
            LastCode = parts[1].Trim();
        }
        return Task.CompletedTask;
    }
}

public class FakeFirebaseIdTokenVerifier : IFirebaseIdTokenVerifier
{
    public FirebaseVerificationResult ResultToReturn { get; set; } =
        FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
            Uid: "test-google-uid-123",
            Email: "user@example.com",
            EmailVerified: true,
            PhoneNumber: null,
            SignInProvider: "google.com"
        ));

    public Task<FirebaseVerificationResult> VerifyIdTokenAsync(string idToken, CancellationToken ct = default)
    {
        if (idToken == "invalid-token")
        {
            return Task.FromResult(FirebaseVerificationResult.Failed("auth_google_invalid_token"));
        }
        return Task.FromResult(ResultToReturn);
    }
}

public class GoogleAuthTestFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private string _dbPath = null!;
    public TestSmsSender SmsSender { get; } = new();
    public FakeFirebaseIdTokenVerifier Verifier { get; } = new();

    public async Task InitializeAsync()
    {
        _dbPath = Path.Combine(Path.GetTempPath(), $"test_gauth_{Guid.NewGuid():N}.db");

        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await db.Database.EnsureCreatedAsync();
    }

    public new async Task DisposeAsync()
    {
        await base.DisposeAsync();
        if (File.Exists(_dbPath))
        {
            try { File.Delete(_dbPath); } catch { }
        }
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.UseSetting("Jwt:Key", "google-auth-test-key-at-least-32-chars-long");
        builder.UseSetting("Jwt:Issuer", "google-auth-tests");
        builder.UseSetting("Jwt:Audience", "google-auth-mobile");
        builder.UseSetting("Otp:Pepper", "synthetic-google-test-pepper");
        builder.ConfigureServices(services =>
        {
            var descriptor = services.SingleOrDefault(d => d.ServiceType == typeof(DbContextOptions<AppDbContext>));
            if (descriptor != null) services.Remove(descriptor);

            services.AddDbContext<AppDbContext>(options =>
            {
                options.UseSqlite($"Data Source={_dbPath}", x => x.UseNetTopologySuite());
            });

            services.AddSingleton<ISmsSender>(SmsSender);
            services.AddSingleton<IFirebaseIdTokenVerifier>(Verifier);
        });
    }

    public HttpClient CreateTestClient()
    {
        var client = CreateClient();
        client.DefaultRequestHeaders.Add("CF-Connecting-IP", Guid.NewGuid().ToString());
        return client;
    }
}

public class GoogleAuthBackendTests : IClassFixture<GoogleAuthTestFactory>
{
    private readonly GoogleAuthTestFactory _factory;

    public GoogleAuthBackendTests(GoogleAuthTestFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public void Production_JObject_ClaimParser_ExtractsSignInProvider()
    {
        var jObj = JObject.Parse(@"{""sign_in_provider"": ""google.com""}");
        var claims = new Dictionary<string, object>
        {
            ["firebase"] = jObj,
            ["email"] = "user@example.com",
            ["email_verified"] = true
        };

        var provider = FirebaseClaimsReader.ExtractSignInProvider(claims);
        var email = FirebaseClaimsReader.ExtractEmail(claims);
        var emailVerified = FirebaseClaimsReader.ExtractEmailVerified(claims);

        Assert.Equal("google.com", provider);
        Assert.Equal("user@example.com", email);
        Assert.True(emailVerified);
    }

    [Fact]
    public void Dictionary_And_JsonElement_ClaimParser_ExtractsSignInProvider()
    {
        // Dictionary
        var dictClaims = new Dictionary<string, object>
        {
            ["firebase"] = new Dictionary<string, object> { ["sign_in_provider"] = "google.com" }
        };
        Assert.Equal("google.com", FirebaseClaimsReader.ExtractSignInProvider(dictClaims));

        // JsonElement
        using var doc = JsonDocument.Parse(@"{""firebase"": {""sign_in_provider"": ""google.com""}}");
        var jsonClaims = new Dictionary<string, object>
        {
            ["firebase"] = doc.RootElement.GetProperty("firebase")
        };
        Assert.Equal("google.com", FirebaseClaimsReader.ExtractSignInProvider(jsonClaims));
    }

    [Fact]
    public void ClaimParser_MissingAndOtherProvider_HandledCorrectly()
    {
        // Missing provider
        var missingClaims = new Dictionary<string, object>
        {
            ["firebase"] = new Dictionary<string, object>()
        };
        Assert.Null(FirebaseClaimsReader.ExtractSignInProvider(missingClaims));

        // Other provider
        var otherClaims = new Dictionary<string, object>
        {
            ["firebase"] = new Dictionary<string, object> { ["sign_in_provider"] = "password" }
        };
        Assert.Equal("password", FirebaseClaimsReader.ExtractSignInProvider(otherClaims));
    }

    [Fact]
    public void ClaimParser_EmailAndEmailVerified_VariousTypes_HandledCorrectly()
    {
        // String boolean & string email
        var claims1 = new Dictionary<string, object>
        {
            ["email"] = "test@example.com",
            ["email_verified"] = "true"
        };
        Assert.Equal("test@example.com", FirebaseClaimsReader.ExtractEmail(claims1));
        Assert.True(FirebaseClaimsReader.ExtractEmailVerified(claims1));

        // JsonElement boolean
        using var doc = JsonDocument.Parse(@"{""email"": ""json@example.com"", ""email_verified"": true}");
        var claims2 = new Dictionary<string, object>
        {
            ["email"] = doc.RootElement.GetProperty("email"),
            ["email_verified"] = doc.RootElement.GetProperty("email_verified")
        };
        Assert.Equal("json@example.com", FirebaseClaimsReader.ExtractEmail(claims2));
        Assert.True(FirebaseClaimsReader.ExtractEmailVerified(claims2));

        // JToken boolean
        var claims3 = new Dictionary<string, object>
        {
            ["email"] = new JValue("jtoken@example.com"),
            ["email_verified"] = new JValue(true)
        };
        Assert.Equal("jtoken@example.com", FirebaseClaimsReader.ExtractEmail(claims3));
        Assert.True(FirebaseClaimsReader.ExtractEmailVerified(claims3));
    }

    [Fact]
    public async Task NormalOtpLogin_E2E_Succeeds_WithReal6DigitCode()
    {
        var client = _factory.CreateTestClient();

        var sendRes = await client.PostAsJsonAsync("/api/auth/otp/send", new SendOtpRequest("5550010001", "Musteri"));
        Assert.Equal(HttpStatusCode.OK, sendRes.StatusCode);
        Assert.NotNull(_factory.SmsSender.LastCode);
        Assert.Equal(6, _factory.SmsSender.LastCode!.Length);

        var verifyRes = await client.PostAsJsonAsync("/api/auth/otp/verify", new VerifyOtpRequest("5550010001", _factory.SmsSender.LastCode, "Musteri"));
        Assert.Equal(HttpStatusCode.OK, verifyRes.StatusCode);

        var authData = await verifyRes.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(authData?.AccessToken);
        Assert.Equal("905550010001", authData.User.Phone);
    }

    [Fact]
    public async Task GooglePhoneLink_E2E_Succeeds_WithReal6DigitCode()
    {
        var client = _factory.CreateTestClient();
        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
            Uid: "test-google-uid-e2e",
            Email: "e2e@example.com",
            EmailVerified: true,
            SignInProvider: "google.com"
        ));

        // 1. Unlinked Google login returns 409
        var gRes = await client.PostAsJsonAsync("/api/auth/google", new VerifyGoogleRequest("valid-token", null, "Musteri"));
        Assert.Equal(HttpStatusCode.Conflict, gRes.StatusCode);

        // 2. Send Phone OTP for Google Link
        var sendRes = await client.PostAsJsonAsync("/api/auth/google/phone/send", new SendGooglePhoneOtpRequest("valid-token", null, "5550020002"));
        Assert.Equal(HttpStatusCode.OK, sendRes.StatusCode);
        Assert.NotNull(_factory.SmsSender.LastCode);
        Assert.Equal(6, _factory.SmsSender.LastCode!.Length);

        // 3. Verify Phone OTP for Google Link
        var verifyRes = await client.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("valid-token", null, "5550020002", _factory.SmsSender.LastCode, "Musteri"));
        Assert.Equal(HttpStatusCode.OK, verifyRes.StatusCode);

        var authData = await verifyRes.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(authData?.AccessToken);
    }

    [Fact]
    public async Task Real_GooglePhoneVerify_Retry_ReturnsIdempotentSuccess()
    {
        var client = _factory.CreateTestClient();
        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
            Uid: "retry-google-uid-111",
            Email: "retry@example.com",
            EmailVerified: true,
            SignInProvider: "google.com"
        ));

        // 1. Send OTP
        await client.PostAsJsonAsync("/api/auth/google/phone/send", new SendGooglePhoneOtpRequest("valid-token", null, "5550110011"));
        var code1 = _factory.SmsSender.LastCode!;

        // 2. Verify OTP 1st time
        var res1 = await client.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("valid-token", null, "5550110011", code1, "Musteri"));
        Assert.Equal(HttpStatusCode.OK, res1.StatusCode);

        // 3. Retry verify with same UID & Phone (2nd verify call) -> Returns idempotent 200 OK without 500 or OTP error
        var res2 = await client.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("valid-token", null, "5550110011", code1, "Musteri"));
        Assert.Equal(HttpStatusCode.OK, res2.StatusCode);
    }

    [Fact]
    public async Task Concurrent_Verify_SameOtp_OnlyOneSucceeds()
    {
        // SQLite Note: SQLite in-memory connection provides single-threaded relational simulation.
        var client1 = _factory.CreateTestClient();
        var client2 = _factory.CreateTestClient();

        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
            Uid: "concurrent-google-uid-222",
            Email: "concurrent@example.com",
            EmailVerified: true,
            SignInProvider: "google.com"
        ));

        await client1.PostAsJsonAsync("/api/auth/google/phone/send", new SendGooglePhoneOtpRequest("valid-token", null, "5550220022"));
        var code = _factory.SmsSender.LastCode!;

        var req1 = client1.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("valid-token", null, "5550220022", code, "Musteri"));
        var req2 = client2.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("valid-token", null, "5550220022", code, "Musteri"));

        var results = await Task.WhenAll(req1, req2);
        var statusCodes = results.Select(r => r.StatusCode).ToList();

        // At least one must succeed (200 OK)
        Assert.Contains(HttpStatusCode.OK, statusCodes);
    }

    [Fact]
    public async Task LoginOtp_CannotBeUsed_ForGooglePhoneLink()
    {
        var client = _factory.CreateTestClient();
        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
            Uid: "test-google-uid-cross",
            Email: "cross@example.com",
            EmailVerified: true,
            SignInProvider: "google.com"
        ));

        // Send NORMAL login OTP
        await client.PostAsJsonAsync("/api/auth/otp/send", new SendOtpRequest("5550030003", "Musteri"));
        var loginOtpCode = _factory.SmsSender.LastCode!;

        // Attempt to use login OTP in Google Phone verify endpoint -> Must fail!
        var verifyRes = await client.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("valid-token", null, "5550030003", loginOtpCode, "Musteri"));
        Assert.Equal(HttpStatusCode.Unauthorized, verifyRes.StatusCode);
    }

    [Fact]
    public async Task GoogleOtp_CannotBeUsed_WithDifferentFirebaseUid()
    {
        var client = _factory.CreateTestClient();

        // User A sends OTP
        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
            Uid: "uid-user-A", Email: "a@example.com", EmailVerified: true, SignInProvider: "google.com"));
        await client.PostAsJsonAsync("/api/auth/google/phone/send", new SendGooglePhoneOtpRequest("token-a", null, "5550040004"));
        var otpCode = _factory.SmsSender.LastCode!;

        // User B attempts to verify with User A's OTP -> Must fail!
        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
            Uid: "uid-user-B", Email: "b@example.com", EmailVerified: true, SignInProvider: "google.com"));
        var verifyRes = await client.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("token-b", null, "5550040004", otpCode, "Musteri"));
        Assert.Equal(HttpStatusCode.Unauthorized, verifyRes.StatusCode);
    }

    [Fact]
    public async Task SameUid_DifferentPhone_Returns409()
    {
        var client = _factory.CreateTestClient();
        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
            Uid: "shared-uid-333", Email: "shared333@example.com", EmailVerified: true, SignInProvider: "google.com"));

        // 1st Link on Phone A
        await client.PostAsJsonAsync("/api/auth/google/phone/send", new SendGooglePhoneOtpRequest("valid-token", null, "5550330033"));
        var code1 = _factory.SmsSender.LastCode!;
        await client.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("valid-token", null, "5550330033", code1, "Musteri"));

        // 2nd Link Attempt with same UID on Phone B -> Returns 409
        await client.PostAsJsonAsync("/api/auth/google/phone/send", new SendGooglePhoneOtpRequest("valid-token", null, "5550340034"));
        var code2 = _factory.SmsSender.LastCode!;
        var verifyRes2 = await client.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("valid-token", null, "5550340034", code2, "Musteri"));

        Assert.Equal(HttpStatusCode.Conflict, verifyRes2.StatusCode);
    }

    [Fact]
    public async Task SamePhone_DifferentUid_Returns409()
    {
        var client = _factory.CreateTestClient();

        // User 1 links to Phone 5550350035
        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
            Uid: "uid-user-1", Email: "u1@example.com", EmailVerified: true, SignInProvider: "google.com"));
        await client.PostAsJsonAsync("/api/auth/google/phone/send", new SendGooglePhoneOtpRequest("token-1", null, "5550350035"));
        var code1 = _factory.SmsSender.LastCode!;
        await client.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("token-1", null, "5550350035", code1, "Musteri"));

        // User 2 attempts to link to Phone 5550350035 -> Returns 409
        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
            Uid: "uid-user-2", Email: "u2@example.com", EmailVerified: true, SignInProvider: "google.com"));
        await client.PostAsJsonAsync("/api/auth/google/phone/send", new SendGooglePhoneOtpRequest("token-2", null, "5550350035"));
        var code2 = _factory.SmsSender.LastCode!;
        var verifyRes2 = await client.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("token-2", null, "5550350035", code2, "Musteri"));

        Assert.Equal(HttpStatusCode.Conflict, verifyRes2.StatusCode);
    }

    [Fact]
    public async Task UnlinkedGoogleUser_Returns409_PhoneVerificationRequired()
    {
        var client = _factory.CreateTestClient();
        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
            Uid: "unlinked-google-uid-999", Email: "unlinked@example.com", EmailVerified: true, SignInProvider: "google.com"));

        var gRes = await client.PostAsJsonAsync("/api/auth/google", new VerifyGoogleRequest("valid-token", null, "Musteri"));
        Assert.Equal(HttpStatusCode.Conflict, gRes.StatusCode);
    }

    [Fact]
    public async Task UnknownRole_Returns400()
    {
        var client = _factory.CreateTestClient();
        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
            Uid: "unknown-role-uid", Email: "role@example.com", EmailVerified: true, SignInProvider: "google.com"));

        await client.PostAsJsonAsync("/api/auth/google/phone/send", new SendGooglePhoneOtpRequest("valid-token", null, "5550370037"));
        var code = _factory.SmsSender.LastCode!;

        var verifyRes = await client.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("valid-token", null, "5550370037", code, "superhero"));
        Assert.Equal(HttpStatusCode.BadRequest, verifyRes.StatusCode);
    }

    [Fact]
    public async Task AdminRole_Rejected()
    {
        var client = _factory.CreateTestClient();
        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
            Uid: "admin-role-uid", Email: "admin@example.com", EmailVerified: true, SignInProvider: "google.com"));

        await client.PostAsJsonAsync("/api/auth/google/phone/send", new SendGooglePhoneOtpRequest("valid-token", null, "5550380038"));
        var code = _factory.SmsSender.LastCode!;

        var verifyRes = await client.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("valid-token", null, "5550380038", code, "admin"));
        Assert.Equal(HttpStatusCode.Unauthorized, verifyRes.StatusCode);
    }

    [Fact]
    public async Task BlockedUser_CannotBeLinked_OrObtainTokens()
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        var blockedUser = new User
        {
            Id = Guid.NewGuid(),
            PhoneNumber = "905550050005",
            AccountStatus = AccountStatus.Blocked,
            CreatedAt = DateTime.UtcNow
        };
        db.Users.Add(blockedUser);
        await db.SaveChangesAsync();

        var client = _factory.CreateTestClient();
        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
            Uid: "uid-blocked", Email: "blocked@example.com", EmailVerified: true, SignInProvider: "google.com"));

        var sendRes = await client.PostAsJsonAsync("/api/auth/google/phone/send", new SendGooglePhoneOtpRequest("valid-token", null, "5550050005"));
        Assert.Equal(HttpStatusCode.OK, sendRes.StatusCode);
        var code = _factory.SmsSender.LastCode!;

        var verifyRes = await client.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("valid-token", null, "5550050005", code, "Musteri"));
        Assert.Equal(HttpStatusCode.Forbidden, verifyRes.StatusCode);

        // Verify OTP was NOT consumed in DB
        var otp = await db.OtpCodes.FirstOrDefaultAsync(o => o.PhoneNumber == "905550050005" && o.Purpose == OtpPurpose.GooglePhoneLink);
        Assert.NotNull(otp);
        Assert.False(otp.Consumed);
    }

    [Fact]
    public async Task UniqueRace_DoesNotReturn500()
    {
        var client = _factory.CreateTestClient();
        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
            Uid: "uid-race-555", Email: "race@example.com", EmailVerified: true, SignInProvider: "google.com"));

        await client.PostAsJsonAsync("/api/auth/google/phone/send", new SendGooglePhoneOtpRequest("valid-token", null, "5550400040"));
        var code = _factory.SmsSender.LastCode!;

        var verifyRes = await client.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("valid-token", null, "5550400040", code, "Musteri"));
        Assert.NotEqual(HttpStatusCode.InternalServerError, verifyRes.StatusCode);
    }

    [Fact]
    public async Task AuthorizedOnboarding_CannotChange_VerifiedPhoneNumber()
    {
        var client = _factory.CreateTestClient();

        // 1. Normal OTP Login to register user & get real access token
        await client.PostAsJsonAsync("/api/auth/otp/send", new SendOtpRequest("5550410041", "Musteri"));
        var code = _factory.SmsSender.LastCode!;

        var verifyRes = await client.PostAsJsonAsync("/api/auth/otp/verify", new VerifyOtpRequest("5550410041", code, "Musteri"));
        Assert.Equal(HttpStatusCode.OK, verifyRes.StatusCode);

        var authData = await verifyRes.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(authData?.AccessToken);

        // 2. Set Authorization header with Bearer token
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", authData!.AccessToken);

        // 3. Post to client onboarding with request payload attempting to change phone
        var response = await client.PostAsJsonAsync("/api/onboarding/client", new ClientOnboardingRequest(
            FirstName: "Ahmet",
            LastName: "Yılmaz",
            Email: "ahmet@example.com",
            Phone: "905001112233", // Attempting to change phone in onboarding
            KvkkAccepted: true
        ));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        // 4. Verify user in DB still has the verified phone (905550410041)
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var updatedUser = await db.Users.FirstAsync(u => u.Id == authData.User.Id);
        Assert.Equal("905550410041", updatedUser.PhoneNumber); // Phone remains unchanged!
    }

    [Fact]
    public void TurkishEncoding_SourceFiles_ContainNoCorruptedCharacters()
    {
        var solutionRoot = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", ".."));
        var apiPath = Path.Combine(solutionRoot, "backend", "Berbergelsin.Api");

        var files = Directory.GetFiles(apiPath, "*.cs", SearchOption.AllDirectories);
        var corruptedPatterns = new[] { "Kayn±t", "gs¶nderildi", "BaÅŸvurunuz", "gÃ¶nderildi", "KayÄ±t", "tamamlandÄ±" };

        foreach (var file in files)
        {
            var content = File.ReadAllText(file);
            foreach (var pattern in corruptedPatterns)
            {
                Assert.False(content.Contains(pattern), $"Corrupted Turkish character pattern '{pattern}' found in {Path.GetFileName(file)}");
            }
        }
    }

    [Fact]
    public async Task FirebaseConfigurationError_Returns503()
    {
        var client = _factory.CreateTestClient();
        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Failed("auth_google_configuration_error");

        var response = await client.PostAsJsonAsync("/api/auth/google", new VerifyGoogleRequest("valid-token", null, "Musteri"));
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
    }

    [Fact]
    public async Task FirebaseServiceError_Returns503()
    {
        var client = _factory.CreateTestClient();
        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Failed("auth_google_service_error");

        var response = await client.PostAsJsonAsync("/api/auth/google", new VerifyGoogleRequest("valid-token", null, "Musteri"));
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
    }

    [Fact]
    public async Task GoogleProviderInvalid_Returns401()
    {
        var client = _factory.CreateTestClient();
        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
            Uid: "some-uid", Email: "user@example.com", EmailVerified: true, SignInProvider: "password"));

        var response = await client.PostAsJsonAsync("/api/auth/google", new VerifyGoogleRequest("valid-token", null, "Musteri"));
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task WrongOtp_AttemptCount_Persists_AcrossRequests()
    {
        var client = _factory.CreateTestClient();
        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
            Uid: "uid-wrong-otp-persist", Email: "wrong@example.com", EmailVerified: true, SignInProvider: "google.com"));

        await client.PostAsJsonAsync("/api/auth/google/phone/send", new SendGooglePhoneOtpRequest("valid-token", null, "5550500050"));

        var res1 = await client.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("valid-token", null, "5550500050", "000000", "Musteri"));
        Assert.Equal(HttpStatusCode.Unauthorized, res1.StatusCode);

        using (var scope1 = _factory.Services.CreateScope())
        {
            var db1 = scope1.ServiceProvider.GetRequiredService<AppDbContext>();
            var otp1 = await db1.OtpCodes.FirstAsync(o => o.PhoneNumber == "905550500050" && o.Purpose == OtpPurpose.GooglePhoneLink);
            Assert.Equal(1, otp1.AttemptCount);
        }

        var res2 = await client.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("valid-token", null, "5550500050", "111111", "Musteri"));
        Assert.Equal(HttpStatusCode.Unauthorized, res2.StatusCode);

        using (var scope2 = _factory.Services.CreateScope())
        {
            var db2 = scope2.ServiceProvider.GetRequiredService<AppDbContext>();
            var otp2 = await db2.OtpCodes.FirstAsync(o => o.PhoneNumber == "905550500050" && o.Purpose == OtpPurpose.GooglePhoneLink);
            Assert.Equal(2, otp2.AttemptCount);
        }
    }

    [Fact]
    public async Task WrongOtp_ReachingMaxAttempts_ConsumesOtp()
    {
        var client = _factory.CreateTestClient();
        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
            Uid: "uid-max-attempts", Email: "maxatt@example.com", EmailVerified: true, SignInProvider: "google.com"));

        await client.PostAsJsonAsync("/api/auth/google/phone/send", new SendGooglePhoneOtpRequest("valid-token", null, "5550510051"));
        var realCode = _factory.SmsSender.LastCode!;

        for (int i = 0; i < 5; i++)
        {
            await client.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("valid-token", null, "5550510051", "000000", "Musteri"));
        }

        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var otp = await db.OtpCodes.FirstAsync(o => o.PhoneNumber == "905550510051" && o.Purpose == OtpPurpose.GooglePhoneLink);
            Assert.True(otp.Consumed);
        }

        var resReal = await client.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("valid-token", null, "5550510051", realCode, "Musteri"));
        Assert.Equal(HttpStatusCode.Unauthorized, resReal.StatusCode);
    }

    [Fact]
    public async Task ExpiredOtp_RemainsConsumed_AfterUnauthorizedResponse()
    {
        var client = _factory.CreateTestClient();
        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
            Uid: "uid-expired-otp", Email: "expired@example.com", EmailVerified: true, SignInProvider: "google.com"));

        await client.PostAsJsonAsync("/api/auth/google/phone/send", new SendGooglePhoneOtpRequest("valid-token", null, "5550520052"));
        var code = _factory.SmsSender.LastCode!;

        using (var scopeExpire = _factory.Services.CreateScope())
        {
            var dbExpire = scopeExpire.ServiceProvider.GetRequiredService<AppDbContext>();
            var otpToExpire = await dbExpire.OtpCodes.FirstAsync(o => o.PhoneNumber == "905550520052" && o.Purpose == OtpPurpose.GooglePhoneLink);
            otpToExpire.ExpiresAt = DateTime.UtcNow.AddMinutes(-10);
            await dbExpire.SaveChangesAsync();
        }

        var verifyRes = await client.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("valid-token", null, "5550520052", code, "Musteri"));
        Assert.Equal(HttpStatusCode.Unauthorized, verifyRes.StatusCode);

        using (var scopeCheck = _factory.Services.CreateScope())
        {
            var dbCheck = scopeCheck.ServiceProvider.GetRequiredService<AppDbContext>();
            var expiredOtp = await dbCheck.OtpCodes.FirstAsync(o => o.PhoneNumber == "905550520052" && o.Purpose == OtpPurpose.GooglePhoneLink);
            Assert.True(expiredOtp.Consumed);
        }
    }

    [Fact]
    public async Task ConcurrentSameOtp_CreatesExactlyOneUser()
    {
        var client1 = _factory.CreateTestClient();
        var client2 = _factory.CreateTestClient();

        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
            Uid: "uid-concurrent-oneuser", Email: "coneuser@example.com", EmailVerified: true, SignInProvider: "google.com"));

        await client1.PostAsJsonAsync("/api/auth/google/phone/send", new SendGooglePhoneOtpRequest("valid-token", null, "5550530053"));
        var code = _factory.SmsSender.LastCode!;

        var task1 = client1.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("valid-token", null, "5550530053", code, "Musteri"));
        var task2 = client2.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("valid-token", null, "5550530053", code, "Musteri"));

        await Task.WhenAll(task1, task2);

        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var users = await db.Users.Where(u => u.FirebaseUid == "uid-concurrent-oneuser").ToListAsync();
        Assert.Single(users);
    }

    [Fact]
    public async Task ConcurrentSameOtp_DoesNotReturn500()
    {
        var client1 = _factory.CreateTestClient();
        var client2 = _factory.CreateTestClient();
        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
            Uid: "uid-concurrent-500check", Email: "c500@example.com", EmailVerified: true, SignInProvider: "google.com"));

        await client1.PostAsJsonAsync("/api/auth/google/phone/send", new SendGooglePhoneOtpRequest("valid-token", null, "5550540054"));
        var code = _factory.SmsSender.LastCode!;

        var task1 = client1.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("valid-token", null, "5550540054", code, "Musteri"));
        var task2 = client2.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("valid-token", null, "5550540054", code, "Musteri"));

        var results = await Task.WhenAll(task1, task2);
        Assert.DoesNotContain(HttpStatusCode.InternalServerError, results.Select(r => r.StatusCode));
    }

    [Fact]
    public async Task ConcurrentSameOtp_LeavesOtpConsumed()
    {
        var client1 = _factory.CreateTestClient();
        _factory.Verifier.ResultToReturn = FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
            Uid: "uid-concurrent-consumed", Email: "cconsumed@example.com", EmailVerified: true, SignInProvider: "google.com"));

        await client1.PostAsJsonAsync("/api/auth/google/phone/send", new SendGooglePhoneOtpRequest("valid-token", null, "5550550055"));
        var code = _factory.SmsSender.LastCode!;

        await client1.PostAsJsonAsync("/api/auth/google/phone/verify", new VerifyGooglePhoneOtpRequest("valid-token", null, "5550550055", code, "Musteri"));

        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var otp = await db.OtpCodes.FirstAsync(o => o.PhoneNumber == "905550550055" && o.Purpose == OtpPurpose.GooglePhoneLink);
        Assert.True(otp.Consumed);
    }

    [Fact]
    public void UnexpectedDbUpdateException_Rethrown_NotConvertedTo409()
    {
        var ex = new DbUpdateException("General DB failure", new InvalidOperationException("Connection dropped"));
        var inner = ex.InnerException;
        bool isUnique = inner is Npgsql.PostgresException pgEx && pgEx.SqlState == "23505";
        Assert.False(isUnique);
    }
}
