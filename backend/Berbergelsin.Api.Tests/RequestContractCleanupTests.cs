using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Berbergelsin.Api.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Berbergelsin.Api.Tests;

public sealed class RequestContractCleanupTests
{
    [Fact]
    public async Task Detail_is_available_only_to_request_parties_and_contains_safe_contract()
    {
        using var f = new RequestApiFactory(); f.SeedAddress();
        var id = await Create(f, "detail-create-122");

        Assert.Equal(HttpStatusCode.Unauthorized, (await f.CreateClient().GetAsync($"/api/requests/{id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await f.Client(f.OtherClientId, "Musteri").GetAsync($"/api/requests/{id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await f.Client(f.OtherClientId, "Berber").GetAsync($"/api/requests/{id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await f.Client(f.ClientId, "Musteri").GetAsync($"/api/requests/{Guid.NewGuid()}")).StatusCode);

        foreach (var party in new[] { f.Client(f.ClientId, "Musteri"), f.Client(f.BarberUserId, "Berber") })
        {
            var response = await party.GetAsync($"/api/requests/{id}");
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            var body = await response.Content.ReadFromJsonAsync<JsonElement>();
            Assert.Equal(id, body.GetProperty("id").GetGuid());
            Assert.True(body.TryGetProperty("concurrencyToken", out _));
            var raw = body.GetRawText().ToLowerInvariant();
            Assert.DoesNotContain("phonenumber", raw);
            Assert.DoesNotContain("email", raw);
        }
        Assert.Equal(HttpStatusCode.OK, (await f.Client(f.ClientId, "Musteri").GetAsync($"/api/requests/{id}/timeline")).StatusCode);
    }

    [Fact]
    public async Task Saved_address_is_owned_and_backend_snapshot_ignores_client_values()
    {
        using var f = new RequestApiFactory(); f.SeedAddress();
        var id = await Create(f, "address-create-122", f.AddressId, lat: 1, lng: 2, snapshot: "MANIPULATED");
        using var scope = f.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var saved = await db.ServiceRequests.SingleAsync(x => x.Id == id);
        Assert.Equal(f.AddressId, saved.ClientAddressId);
        Assert.Contains("Bağdat Caddesi 1", saved.AddressSnapshot);
        Assert.DoesNotContain("MANIPULATED", saved.AddressSnapshot);
        Assert.Equal(41.0002, saved.ClientLocation!.Y, 4);
        Assert.Equal(29.0002, saved.ClientLocation.X, 4);

        var address = await db.ClientAddresses.SingleAsync(a => a.Id == f.AddressId);
        address.AddressLine = "Yeni adres"; address.IsDeleted = true; await db.SaveChangesAsync();
        db.ChangeTracker.Clear();
        saved = await db.ServiceRequests.SingleAsync(x => x.Id == id);
        Assert.Contains("Bağdat Caddesi 1", saved.AddressSnapshot);
    }

    [Fact]
    public async Task Unknown_foreign_deleted_and_wrong_location_addresses_are_rejected()
    {
        using var f = new RequestApiFactory(); f.SeedAddress();
        Assert.Contains("request_address_not_found", await Body(CreateResponse(f, "unknown-address-122", Guid.NewGuid())));
        Assert.Contains("request_invalid_location", await Body(CreateResponse(f, "wrong-location-122", f.AddressId, "business")));
        using (var scope = f.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var address = await db.ClientAddresses.SingleAsync(a => a.Id == f.AddressId);
            address.UserId = f.OtherClientId; await db.SaveChangesAsync();
        }
        Assert.Contains("request_address_forbidden", await Body(CreateResponse(f, "foreign-address-122", f.AddressId)));
    }

    [Fact]
    public async Task Address_retry_returns_original_snapshot_and_manual_flow_still_works()
    {
        using var f = new RequestApiFactory(); f.SeedAddress();
        var first = await Create(f, "address-retry-122", f.AddressId);
        using (var scope = f.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            (await db.ClientAddresses.SingleAsync(a => a.Id == f.AddressId)).AddressLine = "Changed";
            await db.SaveChangesAsync();
        }
        Assert.Equal(first, await Create(f, "address-retry-122", f.AddressId));

        using var f2 = new RequestApiFactory(); f2.Seed();
        var manual = await Create(f2, "manual-address-122");
        using var scope2 = f2.Services.CreateScope();
        Assert.Null((await scope2.ServiceProvider.GetRequiredService<AppDbContext>().ServiceRequests.SingleAsync(x => x.Id == manual)).ClientAddressId);
    }

    private static async Task<Guid> Create(RequestApiFactory f, string key, Guid? addressId = null,
        double lat = 41.0001, double lng = 29.0001, string snapshot = "Manuel adres")
    {
        var response = await CreateResponse(f, key, addressId, "customerAddress", lat, lng, snapshot);
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
    }

    private static Task<HttpResponseMessage> CreateResponse(RequestApiFactory f, string key, Guid? addressId,
        string location = "customerAddress", double lat = 41.0001, double lng = 29.0001, string snapshot = "Manuel adres")
    {
        var client = f.Client(f.ClientId, "Musteri"); client.DefaultRequestHeaders.Add("Idempotency-Key", key);
        return client.PostAsJsonAsync("/api/requests", new { barberProfileId=f.ProfileId, serviceIds=new[]{f.ServiceId},
            requestedTime=f.ValidTime, addressId, serviceLocationType=location, addressSnapshot=snapshot, lat, lng, addressNote="not" });
    }

    private static async Task<string> Body(Task<HttpResponseMessage> response) => await (await response).Content.ReadAsStringAsync();
}
