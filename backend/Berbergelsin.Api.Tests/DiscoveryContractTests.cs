using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Berbergelsin.Api.Controllers;
using Berbergelsin.Api.Dtos;
using Xunit;

namespace Berbergelsin.Api.Tests;

public sealed class DiscoveryContractTests : IClassFixture<ClientProfileApiFactory>
{
    private readonly ClientProfileApiFactory _factory;
    public DiscoveryContractTests(ClientProfileApiFactory factory) => _factory = factory;

    [Fact]
    public async Task Unauthenticated_is_401()
        => Assert.Equal(HttpStatusCode.Unauthorized, (await _factory.CreateClient().GetAsync("/api/barbers/nearby?lat=41&lng=29&page=1")).StatusCode);

    [Fact]
    public async Task Barber_is_403()
        => Assert.Equal(HttpStatusCode.Forbidden, (await _factory.Client(_factory.BarberId, "Berber").GetAsync("/api/barbers/nearby?lat=41&lng=29&page=1")).StatusCode);

    [Theory]
    [InlineData("?lng=29&page=1", "discovery_invalid_location")]
    [InlineData("?lat=91&lng=29&page=1", "discovery_invalid_location")]
    [InlineData("?lat=41&lng=29&radiusKm=51&page=1", "discovery_invalid_location")]
    [InlineData("?lat=41&lng=29&page=-1", "discovery_invalid_query")]
    [InlineData("?lat=41&lng=29&page=1&minPrice=-1", "discovery_invalid_filter")]
    [InlineData("?lat=41&lng=29&page=1&minPrice=20&maxPrice=10", "discovery_invalid_filter")]
    [InlineData("?lat=41&lng=29&page=1&minRating=6", "discovery_invalid_filter")]
    [InlineData("?lat=41&lng=29&page=1&sort=random", "discovery_invalid_filter")]
    [InlineData("?lat=41&lng=29&page=1&serviceMode=teleport", "discovery_invalid_filter")]
    public async Task Invalid_query_has_safe_code(string query, string code)
    {
        var response = await _factory.Client(_factory.ClientId, "Musteri").GetAsync("/api/barbers/nearby" + query);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(code, (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("code").GetString());
    }

    [Theory]
    [InlineData("%_", "%\\%\\_%")]
    [InlineData("  İstanbul  ", "%İstanbul%")]
    public void Search_escapes_wildcards_and_trims(string input, string expected)
        => Assert.Equal(expected, BarbersController.NormalizeSearch(input));

    [Theory]
    [InlineData("atBusiness", "Onsite")]
    [InlineData("atCustomerLocation", "Mobile")]
    [InlineData("both", "Both")]
    public void Service_mode_maps_to_existing_model(string input, string expected)
        => Assert.Equal(expected, BarbersController.NormalizeDiscoveryServiceMode(input));

    [Fact]
    public void Working_hours_use_istanbul_local_time()
    {
        const string hours = "[{\"day\":4,\"open\":\"09:00\",\"close\":\"18:00\",\"closed\":false}]";
        Assert.True(BarbersController.IsOpenAt(hours, new DateTimeOffset(2026, 7, 16, 12, 0, 0, TimeSpan.FromHours(3))));
        Assert.False(BarbersController.IsOpenAt(hours, new DateTimeOffset(2026, 7, 16, 19, 0, 0, TimeSpan.FromHours(3))));
    }

    [Theory]
    [InlineData("POST")]
    [InlineData("PUT")]
    [InlineData("DELETE")]
    public async Task Mutating_verbs_are_not_supported(string method)
    {
        var request = new HttpRequestMessage(new HttpMethod(method), "/api/barbers/nearby?lat=41&lng=29&page=1");
        var response = await _factory.Client(_factory.ClientId, "Musteri").SendAsync(request);
        Assert.Equal(HttpStatusCode.MethodNotAllowed, response.StatusCode);
    }
}
