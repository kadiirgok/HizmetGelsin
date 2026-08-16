using System.Text.Json;
using Berbergelsin.Api.Auth;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Entities;
using Berbergelsin.Api.Enums;
using Berbergelsin.Api.Hubs;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace Berbergelsin.Api.Services;

public sealed class OutboxPermanentException(string code) : Exception(code);

public sealed class NotificationOutboxProcessor(
    AppDbContext db,
    IHubContext<AppHub> hub,
    IPushNotificationSender push,
    IConfiguration configuration,
    ILogger<NotificationOutboxProcessor> logger)
{
    private static readonly SemaphoreSlim InMemoryClaimLock = new(1, 1);
    private readonly int batchSize = Math.Clamp(configuration.GetValue("NotificationOutbox:BatchSize", 50), 1, 500);
    private readonly int maxAttempts = Math.Clamp(configuration.GetValue("NotificationOutbox:MaxAttempts", 8), 1, 50);
    private readonly TimeSpan lockTimeout = TimeSpan.FromSeconds(Math.Clamp(configuration.GetValue("NotificationOutbox:LockTimeoutSeconds", 60), 10, 3600));

    public async Task<int> ProcessBatchAsync(string workerId, CancellationToken ct = default)
    {
        var rows = await ClaimAsync(workerId, ct);
        foreach (var row in rows)
            await DeliverAsync(row.Id, ct);
        return rows.Count;
    }

    private async Task<List<NotificationOutbox>> ClaimAsync(string workerId, CancellationToken ct)
    {
        var now = DateTime.UtcNow;
        var stale = now - lockTimeout;
        if (db.Database.ProviderName?.Contains("Npgsql", StringComparison.OrdinalIgnoreCase) == true)
        {
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var claimed = await db.NotificationOutbox.FromSqlInterpolated($$"""
                SELECT * FROM "NotificationOutbox"
                WHERE (("Status" IN (1, 4) AND "NextAttemptAt" <= {{now}})
                    OR ("Status" = 2 AND "LockedAt" < {{stale}}))
                ORDER BY "NextAttemptAt", "CreatedAt"
                FOR UPDATE SKIP LOCKED
                LIMIT {{batchSize}}
                """).ToListAsync(ct);
            MarkClaimed(claimed, workerId, now);
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return claimed;
        }

        await InMemoryClaimLock.WaitAsync(ct);
        try
        {
            var claimed = await db.NotificationOutbox
                .Where(o => ((o.Status == OutboxStatus.Pending || o.Status == OutboxStatus.Failed) && o.NextAttemptAt <= now)
                    || (o.Status == OutboxStatus.Processing && o.LockedAt < stale))
                .OrderBy(o => o.NextAttemptAt).ThenBy(o => o.CreatedAt).Take(batchSize).ToListAsync(ct);
            MarkClaimed(claimed, workerId, now);
            await db.SaveChangesAsync(ct);
            return claimed;
        }
        finally { InMemoryClaimLock.Release(); }
    }

    private static void MarkClaimed(IEnumerable<NotificationOutbox> rows, string workerId, DateTime now)
    {
        foreach (var row in rows)
        {
            row.Status = OutboxStatus.Processing;
            row.LockedAt = now;
            row.LockedBy = workerId[..Math.Min(workerId.Length, 100)];
            row.ConcurrencyToken = Guid.NewGuid();
        }
    }

    private async Task DeliverAsync(Guid id, CancellationToken ct)
    {
        var row = await db.NotificationOutbox.Include(o => o.Notification).SingleAsync(o => o.Id == id, ct);
        var now = DateTime.UtcNow;
        row.AttemptCount++;
        row.LastAttemptAt = now;
        try
        {
            Validate(row);
            if (row.SignalRStatus != DeliveryStatus.Completed)
            {
                row.SignalRAttemptCount++;
                await SendSignalRAsync(row, ct);
                row.SignalRStatus = DeliveryStatus.Completed;
            }
            if (row.PushStatus is not (DeliveryStatus.Completed or DeliveryStatus.Skipped))
            {
                row.PushAttemptCount++;
                if (push is NoOpPushNotificationSender)
                    row.PushStatus = DeliveryStatus.Skipped;
                else
                {
                    await push.SendAsync(new PushNotificationMessage(row.NotificationId, row.UserId, row.Notification.Type,
                        row.Notification.Title, row.Notification.Body, row.Notification.EntityType,
                        row.Notification.EntityId, row.Notification.Route), ct);
                    row.PushStatus = DeliveryStatus.Completed;
                }
            }
            row.Status = OutboxStatus.Completed;
            row.CompletedAt = now;
            row.LastErrorCode = null;
            logger.LogInformation("Outbox delivery {OutboxId} {NotificationId} {EventType} attempt {Attempt} result {Result}",
                row.Id, row.NotificationId, row.EventType, row.AttemptCount, "completed");
        }
        catch (PushDeliveryException ex) when (ex.Permanent)
        {
            row.Status = OutboxStatus.DeadLetter;
            row.FailedAt = now;
            row.LastErrorCode = SafeCode(ex.Code);
            MarkPendingChannelsFailed(row);
        }
        catch (OutboxPermanentException ex)
        {
            row.Status = OutboxStatus.DeadLetter;
            row.FailedAt = now;
            row.LastErrorCode = SafeCode(ex.Message);
            MarkPendingChannelsFailed(row);
            logger.LogWarning("Outbox delivery {OutboxId} {NotificationId} {EventType} attempt {Attempt} result {Result} code {ErrorCode}",
                row.Id, row.NotificationId, row.EventType, row.AttemptCount, "deadletter", row.LastErrorCode);
        }
        catch (Exception ex)
        {
            row.LastErrorCode = ex is PushDeliveryException pushError ? SafeCode(pushError.Code) : "delivery_transient";
            MarkPendingChannelsFailed(row);
            if (row.AttemptCount >= maxAttempts)
            {
                row.Status = OutboxStatus.DeadLetter;
                row.FailedAt = now;
            }
            else
            {
                row.Status = OutboxStatus.Failed;
                row.NextAttemptAt = now + Backoff(row.AttemptCount);
            }
            logger.LogWarning("Outbox delivery {OutboxId} {NotificationId} {EventType} attempt {Attempt} result {Result} code {ErrorCode}",
                row.Id, row.NotificationId, row.EventType, row.AttemptCount,
                row.Status == OutboxStatus.DeadLetter ? "deadletter" : "retry", row.LastErrorCode);
        }
        finally
        {
            row.LockedAt = null;
            row.LockedBy = null;
            row.ConcurrencyToken = Guid.NewGuid();
            await db.SaveChangesAsync(ct);
        }
    }

    private async Task SendSignalRAsync(NotificationOutbox row, CancellationToken ct)
    {
        var version = await db.Users.AsNoTracking()
            .Where(u => u.Id == row.UserId && u.AccountStatus == AccountStatus.Active)
            .Select(u => (int?)u.TokenVersion).SingleOrDefaultAsync(ct);
        if (version == null) throw new OutboxPermanentException("delivery_user_inactive");
        var summary = new
        {
            eventId = row.Id,
            notificationId = row.NotificationId,
            type = row.EventType,
            createdAt = row.CreatedAt
        };
        var group = SessionGroups.User(row.UserId, version.Value);
        await hub.Clients.Group(group).SendAsync("NotificationCreated", summary, ct);
        var unread = await db.Notifications.CountAsync(n => n.UserId == row.UserId && !n.IsRead, ct);
        await hub.Clients.Group(group).SendAsync("NotificationUnreadCountChanged", new { unreadCount = unread }, ct);
    }

    private static void Validate(NotificationOutbox row)
    {
        if (!RealtimeNotifier.PersistentTypes.Contains(row.EventType)) throw new OutboxPermanentException("delivery_event_unsupported");
        JsonDocument payload;
        try { payload = JsonDocument.Parse(row.PayloadJson); }
        catch (JsonException) { throw new OutboxPermanentException("delivery_payload_malformed"); }
        using (payload)
        {
            var root = payload.RootElement;
            var allowed = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "entityType", "entityId", "route" };
            if (root.ValueKind != JsonValueKind.Object || root.EnumerateObject().Any(p => !allowed.Contains(p.Name)))
                throw new OutboxPermanentException("delivery_payload_invalid");
            if (!root.TryGetProperty("route", out var route) || route.ValueKind != JsonValueKind.String ||
                route.GetString() != row.Notification.Route || !IsValidRoute(row.Notification.Route))
                throw new OutboxPermanentException("delivery_route_invalid");
        }
    }

    internal static bool IsValidRoute(string route) =>
        System.Text.RegularExpressions.Regex.IsMatch(route, @"^/(talepler|teklifler)/[0-9a-fA-F-]{36}$") || route == "/yorumlarim";

    private static void MarkPendingChannelsFailed(NotificationOutbox row)
    {
        if (row.SignalRStatus != DeliveryStatus.Completed) row.SignalRStatus = DeliveryStatus.Failed;
        if (row.PushStatus is not (DeliveryStatus.Completed or DeliveryStatus.Skipped)) row.PushStatus = DeliveryStatus.Failed;
    }

    private static TimeSpan Backoff(int attempt) => attempt switch
    {
        <= 1 => TimeSpan.FromMinutes(1),
        2 => TimeSpan.FromMinutes(5),
        3 => TimeSpan.FromMinutes(15),
        4 => TimeSpan.FromHours(1),
        _ => TimeSpan.FromHours(6)
    };

    private static string SafeCode(string value) => value.Length <= 80 && value.All(c => char.IsAsciiLetterOrDigit(c) || c == '_')
        ? value : "delivery_permanent";
}

public sealed class NotificationOutboxWorker(
    IServiceScopeFactory scopeFactory,
    IConfiguration configuration,
    ILogger<NotificationOutboxWorker> logger) : BackgroundService
{
    private readonly TimeSpan interval = TimeSpan.FromSeconds(Math.Clamp(
        configuration.GetValue("NotificationOutbox:PollingIntervalSeconds", 5), 1, 300));
    private readonly string workerId = $"{Environment.MachineName}:{Guid.NewGuid():N}";

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        logger.LogInformation("Notification outbox worker started {WorkerId}", workerId);
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = scopeFactory.CreateScope();
                var processor = scope.ServiceProvider.GetRequiredService<NotificationOutboxProcessor>();
                var count = await processor.ProcessBatchAsync(workerId, stoppingToken);
                if (count == 0) await Task.Delay(interval, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { }
            catch (Exception)
            {
                logger.LogError("Notification outbox worker iteration failed {WorkerId} {ErrorCode}", workerId, "worker_iteration_failed");
                await Task.Delay(interval, stoppingToken);
            }
        }
    }
}
