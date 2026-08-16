using System.Text.Json;
using Berbergelsin.Api.Auth;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Entities;
using Berbergelsin.Api.Enums;
using Berbergelsin.Api.Hubs;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace Berbergelsin.Api.Services;

/// <summary>Notification ve outbox entitylerini mevcut domain unit-of-work'üne ekler; commit etmez.</summary>
public sealed class RealtimeNotifier(AppDbContext db, IHubContext<AppHub> hub, ILogger<RealtimeNotifier> logger)
{
    internal static readonly HashSet<string> PersistentTypes =
        ["NewRequest", "NewOffer", "OfferUpdated", "RequestUpdated", "RequestTimelineUpdated", "RatingReceived"];

    public async Task<Notification?> EnqueueAsync(Guid userId, string eventName, object payload,
        CancellationToken cancellationToken = default)
    {
        if (!PersistentTypes.Contains(eventName))
            throw new InvalidOperationException("outbox_event_unsupported");
        using var json = JsonDocument.Parse(JsonSerializer.Serialize(payload));
        var (entityType, entityId) = Entity(json.RootElement);
        if (entityId == Guid.Empty) throw new InvalidOperationException("outbox_payload_invalid");
        var status = Text(json.RootElement, "status") ?? "created";

        // Bildirim tercihi kontrolü
        var prefKey = NotificationPreferenceKey(eventName, status);
        if (prefKey != null)
        {
            var prefs = await db.UserNotificationPreferences
                .AsNoTracking()
                .FirstOrDefaultAsync(p => p.UserId == userId, cancellationToken);
            if (prefs != null && !prefs.IsEnabled(prefKey))
                return null; // Kullanıcı bu bildirimi kapatmış
        }

        var dedup = $"{eventName}:{entityType}:{entityId:N}:{status}";
        var existing = db.Notifications.Local.FirstOrDefault(n => n.UserId == userId && n.DeduplicationKey == dedup)
            ?? await db.Notifications.AsNoTracking()
            .FirstOrDefaultAsync(n => n.UserId == userId && n.DeduplicationKey == dedup, cancellationToken);
        if (existing != null) return existing;

        var now = DateTime.UtcNow;
        var (title, body) = Copy(eventName, status);
        var route = entityType switch
        {
            "request" => $"/talepler/{entityId}",
            "offer" => $"/teklifler/{entityId}",
            "rating" => "/yorumlarim",
            _ => throw new InvalidOperationException("outbox_route_invalid")
        };
        var notification = new Notification
        {
            Id = Guid.NewGuid(), UserId = userId, Type = eventName, Title = title, Body = body,
            EntityType = entityType, EntityId = entityId, Route = route, CreatedAt = now,
            DeduplicationKey = dedup,
            DataJson = JsonSerializer.Serialize(new { entityType, entityId, route })
        };
        var outbox = new NotificationOutbox
        {
            Id = Guid.NewGuid(), NotificationId = notification.Id, Notification = notification,
            UserId = userId, EventType = eventName, CreatedAt = now, NextAttemptAt = now,
            PayloadJson = JsonSerializer.Serialize(new { entityType, entityId, route })
        };
        db.Notifications.Add(notification);
        db.NotificationOutbox.Add(outbox);
        return notification;
    }

    // Persistent user events must use EnqueueAsync. These remain best-effort non-inbox broadcasts.
    public async Task ToUserAsync(Guid userId, string eventName, object payload)
    {
        if (PersistentTypes.Contains(eventName)) throw new InvalidOperationException("outbox_required");
        try
        {
            var version = await db.Users.AsNoTracking()
                .Where(u => u.Id == userId && u.AccountStatus == AccountStatus.Active)
                .Select(u => (int?)u.TokenVersion).SingleOrDefaultAsync();
            if (version != null)
                await hub.Clients.Group(SessionGroups.User(userId, version.Value)).SendAsync(eventName, payload);
        }
        catch (Exception ex) { logger.LogWarning(ex, "SignalR ToUserAsync failed"); }
    }

    public async Task ToAdminsAsync(string eventName, object payload)
    {
        try
        {
            var versions = await db.Users.AsNoTracking()
                .Where(u => u.Role == UserRole.Admin && u.AccountStatus == AccountStatus.Active)
                .Select(u => u.TokenVersion).Distinct().ToListAsync();
            foreach (var version in versions)
                await hub.Clients.Group($"admins:v{version}").SendAsync(eventName, payload);
        }
        catch (Exception ex) { logger.LogWarning(ex, "SignalR ToAdminsAsync failed"); }
    }

    public async Task ToMapWatchersAsync(string eventName, object payload)
    { try { await hub.Clients.Group("map-watchers").SendAsync(eventName, payload); } catch (Exception ex) { logger.LogWarning(ex, "SignalR ToMapWatchersAsync failed"); } }

    internal static (string Type, Guid Id) Entity(JsonElement root)
    {
        foreach (var pair in new[] { ("requestId", "request"), ("offerId", "offer"), ("ratingId", "rating") })
            if (Guid.TryParse(Text(root, pair.Item1), out var id)) return (pair.Item2, id);
        return ("unknown", Guid.Empty);
    }

    private static string? Text(JsonElement root, string name)
    {
        foreach (var property in root.EnumerateObject())
            if (property.Name.Equals(name, StringComparison.OrdinalIgnoreCase)) return property.Value.ToString();
        return null;
    }

    private static (string, string) Copy(string type, string? status = null) => type switch
    {
        "NewRequest" => ("🔔 Yeni Talep Geldi", "Bir müşteri hizmet talebi gönderdi. Hemen yanıtlayın."),
        "NewOffer" => ("Yeni teklif", "Hizmet talebiniz için yeni bir teklif var."),
        "OfferUpdated" => ("Teklif güncellendi", "Bir teklifin durumu güncellendi."),
        "RatingReceived" => ("⭐ Yeni Değerlendirme", "Bir müşteri sizi değerlendirdi."),
        "RequestUpdated" => RequestUpdatedCopy(status),
        "RequestTimelineUpdated" => ("Talep güncellendi", "Talebinizde yeni bir hareket var."),
        _ => ("Talep güncellendi", "Hizmet talebinizin durumu güncellendi.")
    };

    private static (string, string) RequestUpdatedCopy(string? status) => status switch
    {
        "Accepted" => ("✅ Talep Kabul Edildi", "Talebiniz işletme tarafından kabul edildi. Randevu tarihini kontrol edin."),
        "Rejected" => ("❌ Talep Reddedildi", "Talebiniz işletme tarafından reddedildi. Başka bir işletmeyi deneyebilirsiniz."),
        "OnTheWay" => ("🚗 Berber Yola Çıktı", "Berber konumunuza doğru yola çıktı. Canlı takip aktif."),
        "Started" => ("💈 Hizmet Başladı", "Berber hizmet vermeye başladı."),
        "Completed" => ("🎉 İşlem Tamamlandı", "Hizmet başarıyla tamamlandı. İşletmeyi değerlendirebilirsiniz."),
        "Cancelled" => ("🚫 Talep İptal Edildi", "Talebiniz iptal edildi."),
        _ => ("📋 Talep Güncellendi", "Talebinizin durumu güncellendi.")
    };

    /// <summary>Bildirim olayını tercih anahtarına çevirir. Null dönerse tercih kontrolü gerekmez.</summary>
    internal static string? NotificationPreferenceKey(string eventName, string? status) => eventName switch
    {
        "NewRequest" => "new_request",
        "RatingReceived" => "new_review",
        "RequestUpdated" => status switch
        {
            "Accepted" => "request_accepted",
            "Rejected" => "request_rejected",
            "OnTheWay" => "on_the_way",
            "Started" => "started",
            "Completed" => "completed",
            "Cancelled" => "cancelled",
            _ => null
        },
        _ => null
    };
}
