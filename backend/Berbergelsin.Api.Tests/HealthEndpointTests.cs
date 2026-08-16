using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Xunit;

namespace Berbergelsin.Api.Tests;

public sealed class HealthEndpointTests : IClassFixture<HealthApiFactory>
{
    private readonly HttpClient _client;

    public HealthEndpointTests(HealthApiFactory factory)
    {
        _client = factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });
    }

    [Fact]
    public async Task Get_is_anonymous_safe_and_has_exact_contract()
    {
        using var response = await _client.GetAsync("/health");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("application/json", response.Content.Headers.ContentType?.MediaType);
        Assert.Null(response.Headers.WwwAuthenticate.FirstOrDefault());

        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var root = document.RootElement;
        Assert.Equal(JsonValueKind.Object, root.ValueKind);
        Assert.Equal("ok", root.GetProperty("status").GetString());
        Assert.Equal("Berbergelsin.Api", root.GetProperty("service").GetString());
        Assert.Equal(new[] { "service", "status" },
            root.EnumerateObject().Select(x => x.Name).OrderBy(x => x).ToArray());

        var body = root.GetRawText().ToLowerInvariant();
        Assert.DoesNotContain("secret", body);
        Assert.DoesNotContain("password", body);
        Assert.DoesNotContain("connection", body);
        Assert.DoesNotContain("stack", body);
        Assert.DoesNotContain("exception", body);
    }

    [Fact]
    public async Task Post_is_rejected_without_executing_health_handler()
    {
        using var response = await _client.PostAsJsonAsync("/health", new { });

        Assert.Equal(HttpStatusCode.MethodNotAllowed, response.StatusCode);
    }
}

public sealed class HealthApiFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.UseSetting("Jwt:Key", "integration-test-key-with-at-least-32-characters");
        builder.UseSetting("Jwt:Issuer", "integration-tests");
        builder.UseSetting("Jwt:Audience", "integration-tests");
        builder.UseSetting("ConnectionStrings:Default",
            "Host=127.0.0.1;Port=1;Database=unused;Username=unused;Password=unused");
        builder.ConfigureAppConfiguration((_, configuration) =>
        {
            configuration.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Jwt:Key"] = "integration-test-key-with-at-least-32-characters",
                ["Jwt:Issuer"] = "integration-tests",
                ["Jwt:Audience"] = "integration-tests",
                ["ConnectionStrings:Default"] =
                    "Host=127.0.0.1;Port=1;Database=unused;Username=unused;Password=unused"
            });
        });
    }
}
