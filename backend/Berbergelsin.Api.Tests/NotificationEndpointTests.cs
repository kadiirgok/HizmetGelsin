using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Entities;
using Berbergelsin.Api.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Berbergelsin.Api.Tests;

public sealed class NotificationEndpointTests
{
    [Fact]
    public async Task Inbox_is_private_paged_filtered_and_contains_no_internal_fields()
    {
        using var f = new RequestApiFactory(); f.Seed();
        Seed(f, f.ClientId, false, DateTime.UtcNow.AddMinutes(-1));
        Seed(f, f.ClientId, true, DateTime.UtcNow.AddMinutes(-2));
        Seed(f, f.OtherClientId, false, DateTime.UtcNow);
        Assert.Equal(HttpStatusCode.Unauthorized, (await f.CreateClient().GetAsync("/api/notifications")).StatusCode);
        var json = await f.Client(f.ClientId, "Musteri").GetFromJsonAsync<JsonElement>("/api/notifications?page=1&pageSize=1&isRead=false");
        Assert.Single(json.GetProperty("items").EnumerateArray());
        Assert.Equal(1, json.GetProperty("totalCount").GetInt32());
        var item = json.GetProperty("items")[0];
        Assert.False(item.TryGetProperty("userId", out _));
        Assert.False(item.TryGetProperty("deduplicationKey", out _));
        Assert.False(item.TryGetProperty("dataJson", out _));
    }

    [Fact]
    public async Task Read_is_idempotent_and_foreign_notification_is_hidden()
    {
        using var f = new RequestApiFactory(); f.Seed();
        var own = Seed(f, f.ClientId, false, DateTime.UtcNow);
        var foreign = Seed(f, f.OtherClientId, false, DateTime.UtcNow);
        var c = f.Client(f.ClientId, "Musteri");
        var first = await c.PostAsync($"/api/notifications/{own}/read", null);
        var firstJson = await first.Content.ReadFromJsonAsync<JsonElement>();
        var firstReadAt = firstJson.GetProperty("readAt").GetDateTime();
        var secondJson = await (await c.PostAsync($"/api/notifications/{own}/read", null)).Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(firstReadAt, secondJson.GetProperty("readAt").GetDateTime());
        Assert.Equal(HttpStatusCode.NotFound, (await c.PostAsync($"/api/notifications/{foreign}/read", null)).StatusCode);
        Assert.Equal(0, (await c.GetFromJsonAsync<JsonElement>("/api/notifications/unread-count")).GetProperty("unreadCount").GetInt32());
    }

    [Fact]
    public async Task Read_all_changes_only_current_users_unread_rows()
    {
        using var f = new RequestApiFactory(); f.Seed();
        Seed(f, f.ClientId, false, DateTime.UtcNow); Seed(f, f.ClientId, false, DateTime.UtcNow.AddSeconds(-1));
        Seed(f, f.OtherClientId, false, DateTime.UtcNow);
        var result = await f.Client(f.ClientId, "Musteri").PostAsync("/api/notifications/read-all", null);
        Assert.Equal(2, (await result.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("updatedCount").GetInt32());
        using var scope = f.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        Assert.Equal(1, await db.Notifications.CountAsync(n => !n.IsRead));
    }

    [Fact]
    public async Task Device_registration_is_idempotent_rebinds_and_never_returns_token()
    {
        using var f = new RequestApiFactory(); f.Seed();
        var c1 = f.Client(f.ClientId, "Musteri");
        var body = new { platform = "android", token = "opaque-push-token-value", deviceId = "device-1" };
        var first = await c1.PostAsJsonAsync("/api/notifications/devices", body);
        var repeat = await c1.PostAsJsonAsync("/api/notifications/devices", body);
        Assert.Equal(HttpStatusCode.OK, first.StatusCode); Assert.Equal(HttpStatusCode.OK, repeat.StatusCode);
        Assert.DoesNotContain("opaque-push-token-value", await first.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.BadRequest, (await c1.PostAsJsonAsync("/api/notifications/devices", new { platform = "web", token = "x", deviceId = "d" })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await f.Client(f.OtherClientId, "Musteri").PostAsJsonAsync("/api/notifications/devices", body)).StatusCode);
        using var scope = f.Services.CreateScope();
        var token = await scope.ServiceProvider.GetRequiredService<AppDbContext>().DevicePushTokens.SingleAsync();
        Assert.Equal(f.OtherClientId, token.UserId);
        Assert.Equal(HttpStatusCode.OK, (await f.Client(f.OtherClientId, "Musteri").DeleteAsync("/api/notifications/devices/device-1")).StatusCode);
    }

    [Fact]
    public async Task Persistent_notifier_deduplicates_and_uses_allowlisted_route_data()
    {
        using var f = new RequestApiFactory(); f.Seed();
        var requestId = Guid.NewGuid();
        using var scope = f.Services.CreateScope();
        var notifier = scope.ServiceProvider.GetRequiredService<RealtimeNotifier>();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await notifier.EnqueueAsync(f.ClientId, "RequestUpdated", new { requestId, status = "Accepted", phone = "must-not-persist" });
        await notifier.EnqueueAsync(f.ClientId, "RequestUpdated", new { requestId, status = "Accepted", phone = "must-not-persist" });
        await db.SaveChangesAsync();
        var row = await db.Notifications.SingleAsync();
        Assert.Single(await db.NotificationOutbox.ToListAsync());
        Assert.Equal($"/talepler/{requestId}", row.Route);
        Assert.DoesNotContain("phone", row.DataJson, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("must-not-persist", row.Body);
    }

    [Fact]
    public async Task NoOp_push_sender_does_not_fail_startup_or_send()
    {
        IPushNotificationSender sender = new NoOpPushNotificationSender();
        await sender.SendAsync(new PushNotificationMessage(Guid.NewGuid(), "RequestUpdated", "Genel", "Güncellendi", "request", Guid.NewGuid(), "/talepler/x"));
    }

    static Guid Seed(RequestApiFactory f, Guid userId, bool read, DateTime created)
    {
        using var scope = f.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var id = Guid.NewGuid();
        db.Notifications.Add(new Notification { Id = id, UserId = userId, Type = "RequestUpdated", Title = "Talep güncellendi", Body = "Durum değişti.", EntityType = "request", EntityId = Guid.NewGuid(), Route = "/talepler/x", IsRead = read, ReadAt = read ? created : null, CreatedAt = created, DeduplicationKey = Guid.NewGuid().ToString("N"), DataJson = "{}" });
        db.SaveChanges(); return id;
    }
}
