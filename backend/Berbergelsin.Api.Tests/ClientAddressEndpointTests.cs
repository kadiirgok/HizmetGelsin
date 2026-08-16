using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Berbergelsin.Api.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Berbergelsin.Api.Tests;

public sealed class ClientAddressEndpointTests
{
    [Fact]
    public async Task Authentication_and_customer_role_are_required()
    {
        using var f = new RequestApiFactory(); f.Seed();
        Assert.Equal(HttpStatusCode.Unauthorized, (await f.CreateClient().GetAsync("/api/client/addresses")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await f.Client(f.BarberUserId, "Berber").GetAsync("/api/client/addresses")).StatusCode);
    }

    [Fact]
    public async Task First_address_is_default_and_second_default_demotes_first()
    {
        using var f = new RequestApiFactory(); f.Seed(); var c = f.Client(f.ClientId, "Musteri");
        var first = await Create(c, "Ev", isDefault: false);
        Assert.True(first.GetProperty("isDefault").GetBoolean());
        var second = await Create(c, "İş", isDefault: true);
        var list = await c.GetFromJsonAsync<JsonElement>("/api/client/addresses");
        Assert.Equal(second.GetProperty("id").GetGuid(), list[0].GetProperty("id").GetGuid());
        Assert.False(list[1].GetProperty("isDefault").GetBoolean());
        Assert.False(list[0].TryGetProperty("userId", out _));
        Assert.False(list[0].TryGetProperty("isDeleted", out _));
    }

    [Fact]
    public async Task Manual_address_is_supported_and_validation_rejects_bad_input()
    {
        using var f = new RequestApiFactory(); f.Seed(); var c = f.Client(f.ClientId, "Musteri");
        var manual = await Create(c, "Diğer", placeId: null);
        Assert.Equal(JsonValueKind.Null, manual.GetProperty("placeId").ValueKind);
        var bad = await c.PostAsJsonAsync("/api/client/addresses", Body("", latitude: 100));
        Assert.Equal(HttpStatusCode.BadRequest, bad.StatusCode);
        Assert.Contains("client_address_invalid", await bad.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task Owner_updates_but_stale_version_and_other_customer_are_rejected()
    {
        using var f = new RequestApiFactory(); f.Seed(); var owner = f.Client(f.ClientId, "Musteri");
        var created = await Create(owner, "Ev"); var id = created.GetProperty("id").GetGuid();
        var version = created.GetProperty("version").GetString();
        var updatedResponse = await owner.PutAsJsonAsync($"/api/client/addresses/{id}", Body("Yeni Ev", version: version));
        Assert.Equal(HttpStatusCode.OK, updatedResponse.StatusCode);
        Assert.Equal(HttpStatusCode.Conflict,
            (await owner.PutAsJsonAsync($"/api/client/addresses/{id}", Body("Eski", version: version))).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound,
            (await f.Client(f.OtherClientId, "Musteri").PutAsJsonAsync($"/api/client/addresses/{id}", Body("Çalma", version: version))).StatusCode);
    }

    [Fact]
    public async Task Delete_is_soft_idempotent_and_reassigns_default()
    {
        using var f = new RequestApiFactory(); f.Seed(); var c = f.Client(f.ClientId, "Musteri");
        var first = await Create(c, "Ev"); await Task.Delay(2); var second = await Create(c, "İş");
        var id = first.GetProperty("id").GetGuid();
        Assert.Equal(HttpStatusCode.OK, (await c.DeleteAsync($"/api/client/addresses/{id}")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await c.DeleteAsync($"/api/client/addresses/{id}")).StatusCode);
        var list = await c.GetFromJsonAsync<JsonElement>("/api/client/addresses");
        Assert.Single(list.EnumerateArray()); Assert.Equal(second.GetProperty("id").GetGuid(), list[0].GetProperty("id").GetGuid());
        Assert.True(list[0].GetProperty("isDefault").GetBoolean());
        using var scope = f.Services.CreateScope(); var saved = await scope.ServiceProvider.GetRequiredService<AppDbContext>().ClientAddresses.SingleAsync(a => a.Id == id);
        Assert.True(saved.IsDeleted); Assert.NotNull(saved.DeletedAt);
    }

    [Fact]
    public async Task Active_address_limit_is_ten()
    {
        using var f = new RequestApiFactory(); f.Seed(); var c = f.Client(f.ClientId, "Musteri");
        for (var i = 0; i < 10; i++) await Create(c, $"Adres {i}");
        var response = await c.PostAsJsonAsync("/api/client/addresses", Body("Fazla"));
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Contains("client_address_limit_reached", await response.Content.ReadAsStringAsync());
    }

    private static async Task<JsonElement> Create(HttpClient c, string label, bool isDefault = false, string? placeId = "place-1")
    {
        var response = await c.PostAsJsonAsync("/api/client/addresses", Body(label, isDefault: isDefault, placeId: placeId));
        response.EnsureSuccessStatusCode(); return await response.Content.ReadFromJsonAsync<JsonElement>();
    }
    private static object Body(string label, double latitude = 41, bool isDefault = false,
        string? placeId = "place-1", string? version = null) => new { label, placeId,
        formattedAddress = "Kadıköy, İstanbul", province = "İstanbul", district = "Kadıköy",
        neighborhood = "Caferağa", street = "Moda", streetNumber = "1", postalCode = "34710",
        addressLine = "Moda Caddesi No: 1", latitude, longitude = 29d, isDefault, version,
        userId = Guid.NewGuid(), isDeleted = true, createdAt = DateTime.UtcNow };
}
