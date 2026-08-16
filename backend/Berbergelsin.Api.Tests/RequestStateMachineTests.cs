using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Entities;
using Berbergelsin.Api.Enums;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Berbergelsin.Api.Tests;

public sealed class RequestStateMachineTests
{
    [Fact]
    public async Task Allowed_transition_is_idempotent_and_appends_one_timeline_row()
    {
        using var f = new RequestApiFactory(); f.Seed();
        var id = await Create(f);
        var barber = f.Client(f.BarberUserId, "Berber");
        var first = await Post(barber, $"/api/requests/{id}/accept", "accept-key-107");
        var replay = await Post(barber, $"/api/requests/{id}/accept", "accept-key-107");
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        Assert.Equal(HttpStatusCode.OK, replay.StatusCode);
        using var scope = f.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        Assert.Single(await db.RequestStatusHistories.Where(x => x.RequestId == id).ToListAsync());
        Assert.Single(await db.RequestOperations.Where(x => x.RequestId == id).ToListAsync());
    }

    [Fact]
    public async Task Invalid_transition_and_changed_idempotency_payload_return_conflict()
    {
        using var f = new RequestApiFactory(); f.Seed(); var id = await Create(f);
        var barber = f.Client(f.BarberUserId, "Berber");
        Assert.Equal(HttpStatusCode.Conflict,
            (await Post(barber, $"/api/requests/{id}/start", "invalid-key-107")).StatusCode);
        Assert.Equal(HttpStatusCode.OK,
            (await Post(barber, $"/api/requests/{id}/accept", "shared-key-107")).StatusCode);
        var conflict = await Post(barber, $"/api/requests/{id}/on-the-way", "shared-key-107");
        Assert.Equal(HttpStatusCode.Conflict, conflict.StatusCode);
        Assert.Contains("request_idempotency_conflict", await conflict.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task Cancellation_requires_reason_and_persists_structured_audit()
    {
        using var f = new RequestApiFactory(); f.Seed(); var id = await Create(f);
        var client = f.Client(f.ClientId, "Musteri");
        client.DefaultRequestHeaders.Add("Idempotency-Key", "cancel-key-107");
        var invalid = await client.PostAsJsonAsync($"/api/requests/{id}/cancel", new { reasonCode = "", reasonText = "x" });
        Assert.Equal(HttpStatusCode.BadRequest, invalid.StatusCode);
        client.DefaultRequestHeaders.Remove("Idempotency-Key"); client.DefaultRequestHeaders.Add("Idempotency-Key", "cancel-valid-107");
        var ok = await client.PostAsJsonAsync($"/api/requests/{id}/cancel", new { reasonCode = "plans_changed", reasonText = "Plan değişti" });
        Assert.Equal(HttpStatusCode.OK, ok.StatusCode);
        using var scope = f.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var saved = await db.ServiceRequests.SingleAsync(x => x.Id == id);
        Assert.Equal(RequestStatus.Cancelled, saved.Status); Assert.Equal("Musteri", saved.CancelledByRole);
        Assert.Equal("plans_changed", saved.CancellationReasonCode);
        Assert.Single(await db.RequestStatusHistories.Where(x => x.RequestId == id).ToListAsync());
    }

    [Fact]
    public async Task Reschedule_requires_counterparty_and_preserves_previous_time()
    {
        using var f = new RequestApiFactory(); f.Seed(); var id = await Create(f);
        var old = f.ValidTime;
        var proposed = old.AddDays(7);
        var client = f.Client(f.ClientId, "Musteri");
        client.DefaultRequestHeaders.Add("Idempotency-Key", "reschedule-key-107");
        var request = await client.PostAsJsonAsync($"/api/requests/{id}/reschedule", new { requestedStartAt = proposed, reason = "Uygun değil" });
        Assert.Equal(HttpStatusCode.OK, request.StatusCode);
        var self = await Post(client, $"/api/requests/{id}/reschedule/accept", "self-accept-key-107");
        Assert.Equal(HttpStatusCode.Forbidden, self.StatusCode);
        var barber = f.Client(f.BarberUserId, "Berber");
        Assert.Equal(HttpStatusCode.OK,
            (await Post(barber, $"/api/requests/{id}/reschedule/accept", "other-accept-key-107")).StatusCode);
        using var scope = f.Services.CreateScope(); var saved = await scope.ServiceProvider.GetRequiredService<AppDbContext>().ServiceRequests.SingleAsync(x => x.Id == id);
        Assert.Equal(RequestStatus.Accepted, saved.Status); Assert.Equal(old.ToUniversalTime(), saved.PreviousRequestedTime);
        Assert.Equal(proposed.ToUniversalTime(), saved.RequestedTime);
    }

    [Fact]
    public async Task Timeline_is_deterministic_and_ownership_is_enforced()
    {
        using var f = new RequestApiFactory(); f.Seed(); var id = await Create(f);
        await Post(f.Client(f.BarberUserId, "Berber"), $"/api/requests/{id}/accept", "timeline-key-107");
        var own = await f.Client(f.ClientId, "Musteri").GetAsync($"/api/requests/{id}/timeline");
        Assert.Equal(HttpStatusCode.OK, own.StatusCode);
        var rows = await own.Content.ReadFromJsonAsync<JsonElement>(); Assert.Equal(1, rows.GetArrayLength());
        var other = await f.Client(f.OtherClientId, "Musteri").GetAsync($"/api/requests/{id}/timeline");
        Assert.True(other.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Other_customer_and_other_business_cannot_mutate_request()
    {
        using var f = new RequestApiFactory(); f.Seed(); var id = await Create(f);
        var otherCustomer = f.Client(f.OtherClientId, "Musteri");
        otherCustomer.DefaultRequestHeaders.Add("Idempotency-Key", "foreign-cancel-107");
        var denied = await otherCustomer.PostAsJsonAsync($"/api/requests/{id}/cancel",
            new { reasonCode = "plans_changed", reasonText = "x" });
        Assert.Equal(HttpStatusCode.NotFound, denied.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound,
            (await Post(f.Client(f.OtherClientId, "Berber"), $"/api/requests/{id}/accept", "foreign-business-107")).StatusCode);
    }

    [Fact]
    public async Task Concurrent_start_and_cancel_have_one_winner_and_one_conflict()
    {
        using var f = new RequestApiFactory(); f.Seed(); var id = await Create(f);
        Assert.Equal(HttpStatusCode.OK,
            (await Post(f.Client(f.BarberUserId, "Berber"), $"/api/requests/{id}/accept", "race-accept-107")).StatusCode);
        var barber = f.Client(f.BarberUserId, "Berber");
        var client = f.Client(f.ClientId, "Musteri");
        barber.DefaultRequestHeaders.Add("Idempotency-Key", "race-start-107");
        client.DefaultRequestHeaders.Add("Idempotency-Key", "race-cancel-107");
        var start = barber.PostAsync($"/api/requests/{id}/start", null);
        var cancel = client.PostAsJsonAsync($"/api/requests/{id}/cancel",
            new { reasonCode = "plans_changed", reasonText = "race" });
        var results = await Task.WhenAll(start, cancel);
        Assert.Single(results, x => x.StatusCode == HttpStatusCode.OK);
        Assert.Single(results, x => x.StatusCode == HttpStatusCode.Conflict);
        using var scope = f.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        Assert.Equal(2, await db.RequestStatusHistories.CountAsync(x => x.RequestId == id));
    }

    private static async Task<Guid> Create(RequestApiFactory f)
    {
        var client = f.Client(f.ClientId, "Musteri"); client.DefaultRequestHeaders.Add("Idempotency-Key", "create-state-107");
        var response = await client.PostAsJsonAsync("/api/requests", new { barberProfileId = f.ProfileId,
            serviceIds = new[] { f.ServiceId }, requestedTime = f.ValidTime, lat = 41.0001, lng = 29.0001, addressNote = "test" });
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
    }

    private static Task<HttpResponseMessage> Post(HttpClient client, string route, string key)
    {
        client.DefaultRequestHeaders.Remove("Idempotency-Key"); client.DefaultRequestHeaders.Add("Idempotency-Key", key);
        return client.PostAsync(route, null);
    }
}
