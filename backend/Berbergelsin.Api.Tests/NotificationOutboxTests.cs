using Berbergelsin.Api.Data;
using Berbergelsin.Api.Entities;
using Berbergelsin.Api.Enums;
using Berbergelsin.Api.Hubs;
using Berbergelsin.Api.Services;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Berbergelsin.Api.Tests;

public sealed class NotificationOutboxTests
{
    [Fact]
    public async Task Domain_notification_and_outbox_commit_and_rollback_together()
    {
        await using var fixture = await Fixture.Create();
        await using (var tx = await fixture.Db.Database.BeginTransactionAsync())
        {
            fixture.User.FirstName = "committed";
            await fixture.Notifier.EnqueueAsync(fixture.User.Id, "RequestUpdated",
                new { requestId = Guid.NewGuid(), status = "Accepted" });
            await fixture.Db.SaveChangesAsync();
            await tx.CommitAsync();
        }
        Assert.Equal("committed", (await fixture.Db.Users.SingleAsync()).FirstName);
        Assert.Single(await fixture.Db.Notifications.ToListAsync());
        Assert.Single(await fixture.Db.NotificationOutbox.ToListAsync());

        await using (var tx = await fixture.Db.Database.BeginTransactionAsync())
        {
            fixture.User.LastName = "rolled-back";
            await fixture.Notifier.EnqueueAsync(fixture.User.Id, "NewRequest",
                new { requestId = Guid.NewGuid() });
            await fixture.Db.SaveChangesAsync();
            await tx.RollbackAsync();
        }
        fixture.Db.ChangeTracker.Clear();
        Assert.Null((await fixture.Db.Users.SingleAsync()).LastName);
        Assert.Single(await fixture.Db.Notifications.ToListAsync());
        Assert.Single(await fixture.Db.NotificationOutbox.ToListAsync());
    }

    [Fact]
    public async Task Duplicate_deduplication_key_creates_one_inbox_and_one_outbox()
    {
        await using var fixture = await Fixture.Create();
        var requestId = Guid.NewGuid();
        await fixture.Notifier.EnqueueAsync(fixture.User.Id, "RequestUpdated", new { requestId, status = "Started" });
        await fixture.Notifier.EnqueueAsync(fixture.User.Id, "RequestUpdated", new { requestId, status = "Started" });
        await fixture.Db.SaveChangesAsync();
        Assert.Single(await fixture.Db.Notifications.ToListAsync());
        Assert.Single(await fixture.Db.NotificationOutbox.ToListAsync());
    }

    [Fact]
    public async Task SignalR_and_push_are_independent_and_completed_channel_is_not_repeated()
    {
        await using var fixture = await Fixture.Create(pushFailures: 1);
        await fixture.Enqueue();
        Assert.Equal(1, await fixture.Processor.ProcessBatchAsync("worker-a"));
        var row = await fixture.Db.NotificationOutbox.SingleAsync();
        Assert.Equal(DeliveryStatus.Completed, row.SignalRStatus);
        Assert.Equal(DeliveryStatus.Failed, row.PushStatus);
        Assert.Equal(OutboxStatus.Failed, row.Status);
        Assert.Equal(1, fixture.Hub.Proxy.NotificationCreatedCount);

        row.NextAttemptAt = DateTime.UtcNow.AddSeconds(-1);
        await fixture.Db.SaveChangesAsync();
        Assert.Equal(1, await fixture.Processor.ProcessBatchAsync("worker-b"));
        Assert.Equal(OutboxStatus.Completed, row.Status);
        Assert.Equal(DeliveryStatus.Completed, row.PushStatus);
        Assert.Equal(1, fixture.Hub.Proxy.NotificationCreatedCount);
        Assert.Equal(2, fixture.Push.Attempts);
    }

    [Fact]
    public async Task Noop_push_completes_without_retry_and_payload_is_safe_summary()
    {
        await using var fixture = await Fixture.Create(noOp: true);
        await fixture.Enqueue();
        await fixture.Processor.ProcessBatchAsync("worker");
        var row = await fixture.Db.NotificationOutbox.SingleAsync();
        Assert.Equal(OutboxStatus.Completed, row.Status);
        Assert.Equal(DeliveryStatus.Skipped, row.PushStatus);
        Assert.DoesNotContain("phone", row.PayloadJson, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("email", row.PayloadJson, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("address", row.PayloadJson, StringComparison.OrdinalIgnoreCase);
        Assert.NotNull(fixture.Hub.Proxy.LastNotificationPayload);
        var text = System.Text.Json.JsonSerializer.Serialize(fixture.Hub.Proxy.LastNotificationPayload);
        Assert.Contains(row.NotificationId.ToString(), text, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("title", text, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Future_rows_are_skipped_and_stale_processing_lock_is_recovered()
    {
        await using var fixture = await Fixture.Create(batchSize: 1);
        await fixture.Enqueue();
        var first = await fixture.Db.NotificationOutbox.SingleAsync();
        first.Status = OutboxStatus.Processing;
        first.LockedAt = DateTime.UtcNow.AddMinutes(-5);
        first.LockedBy = "crashed";
        await fixture.Db.SaveChangesAsync();
        await fixture.Enqueue("NewOffer", new { offerId = Guid.NewGuid() });
        var future = await fixture.Db.NotificationOutbox.OrderByDescending(x => x.CreatedAt).FirstAsync();
        future.NextAttemptAt = DateTime.UtcNow.AddHours(1);
        await fixture.Db.SaveChangesAsync();
        Assert.Equal(1, await fixture.Processor.ProcessBatchAsync("recovery"));
        Assert.Equal(OutboxStatus.Completed, first.Status);
        Assert.Equal(OutboxStatus.Pending, future.Status);
    }

    [Fact]
    public async Task Malformed_payload_goes_directly_to_deadletter()
    {
        await using var fixture = await Fixture.Create();
        await fixture.Enqueue();
        var row = await fixture.Db.NotificationOutbox.SingleAsync();
        row.PayloadJson = "{malformed";
        await fixture.Db.SaveChangesAsync();
        await fixture.Processor.ProcessBatchAsync("worker");
        Assert.Equal(OutboxStatus.DeadLetter, row.Status);
        Assert.Equal("delivery_payload_malformed", row.LastErrorCode);
        Assert.Single(await fixture.Db.Notifications.ToListAsync());
    }

    [Fact]
    public async Task All_supported_domain_events_create_exactly_one_outbox()
    {
        await using var fixture = await Fixture.Create();
        var events = new[] { "NewRequest", "NewOffer", "OfferUpdated", "RequestUpdated", "RequestTimelineUpdated", "RatingReceived" };
        foreach (var eventType in events)
        {
            var entityId = Guid.NewGuid();
            object payload = eventType switch
            {
                "NewOffer" or "OfferUpdated" => new { offerId = entityId, status = "Created" },
                "RatingReceived" => new { ratingId = entityId },
                _ => new { requestId = entityId, status = "Created" }
            };
            await fixture.Notifier.EnqueueAsync(fixture.User.Id, eventType, payload);
        }
        await fixture.Db.SaveChangesAsync();
        Assert.Equal(events.Length, await fixture.Db.Notifications.CountAsync());
        Assert.Equal(events.Length, await fixture.Db.NotificationOutbox.CountAsync());
    }

    [Fact]
    public async Task Maximum_attempts_moves_delivery_to_deadletter()
    {
        await using var fixture = await Fixture.Create(pushFailures: 10);
        await fixture.Enqueue();
        for (var attempt = 0; attempt < 3; attempt++)
        {
            await fixture.Processor.ProcessBatchAsync($"worker-{attempt}");
            var current = await fixture.Db.NotificationOutbox.SingleAsync();
            current.NextAttemptAt = DateTime.UtcNow.AddSeconds(-1);
            await fixture.Db.SaveChangesAsync();
        }
        var row = await fixture.Db.NotificationOutbox.SingleAsync();
        Assert.Equal(OutboxStatus.DeadLetter, row.Status);
        Assert.Equal(DeliveryStatus.Completed, row.SignalRStatus);
        Assert.Equal(3, row.PushAttemptCount);
        Assert.Equal(1, fixture.Hub.Proxy.NotificationCreatedCount);
    }

    private sealed class Fixture : IAsyncDisposable
    {
        private readonly SqliteConnection connection;
        public AppDbContext Db { get; }
        public User User { get; }
        public RealtimeNotifier Notifier { get; }
        public FakeHubContext Hub { get; }
        public FakePush Push { get; }
        public NotificationOutboxProcessor Processor { get; }

        private Fixture(SqliteConnection connection, AppDbContext db, User user, RealtimeNotifier notifier,
            FakeHubContext hub, FakePush push, NotificationOutboxProcessor processor)
        { this.connection = connection; Db = db; User = user; Notifier = notifier; Hub = hub; Push = push; Processor = processor; }

        public static async Task<Fixture> Create(int pushFailures = 0, bool noOp = false, int batchSize = 50)
        {
            var connection = new SqliteConnection("Data Source=:memory:"); await connection.OpenAsync();
            var db = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>()
                .UseSqlite(connection, sqlite => sqlite.UseNetTopologySuite()).Options);
            await db.Database.EnsureCreatedAsync();
            var user = new User { Id = Guid.NewGuid(), PhoneNumber = "905550001200", Role = UserRole.Musteri,
                AccountStatus = AccountStatus.Active, CreatedAt = DateTime.UtcNow };
            db.Users.Add(user); await db.SaveChangesAsync();
            var hub = new FakeHubContext();
            var notifier = new RealtimeNotifier(db, hub);
            var push = new FakePush(pushFailures);
            IPushNotificationSender sender = noOp ? new NoOpPushNotificationSender() : push;
            var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
            { ["NotificationOutbox:BatchSize"] = batchSize.ToString(), ["NotificationOutbox:MaxAttempts"] = "3",
              ["NotificationOutbox:LockTimeoutSeconds"] = "10" }).Build();
            var processor = new NotificationOutboxProcessor(db, hub, sender, config,
                NullLogger<NotificationOutboxProcessor>.Instance);
            return new Fixture(connection, db, user, notifier, hub, push, processor);
        }

        public async Task Enqueue(string type = "RequestUpdated", object? payload = null)
        {
            payload ??= new { requestId = Guid.NewGuid(), status = "Accepted", phone = "discard" };
            await Notifier.EnqueueAsync(User.Id, type, payload);
            await Db.SaveChangesAsync();
        }

        public async ValueTask DisposeAsync() { await Db.DisposeAsync(); await connection.DisposeAsync(); }
    }

    private sealed class FakePush(int failures) : IPushNotificationSender
    {
        public int Attempts { get; private set; }
        public Task SendAsync(PushNotificationMessage message, CancellationToken cancellationToken = default)
        { Attempts++; if (Attempts <= failures) throw new HttpRequestException("temporary"); return Task.CompletedTask; }
    }

    private sealed class FakeHubContext : IHubContext<AppHub>
    {
        public FakeProxy Proxy { get; } = new();
        public IHubClients Clients => new FakeClients(Proxy);
        public IGroupManager Groups { get; } = new FakeGroups();
    }

    private sealed class FakeProxy : IClientProxy
    {
        public int NotificationCreatedCount { get; private set; }
        public object? LastNotificationPayload { get; private set; }
        public Task SendCoreAsync(string method, object?[] args, CancellationToken cancellationToken = default)
        { if (method == "NotificationCreated") { NotificationCreatedCount++; LastNotificationPayload = args.FirstOrDefault(); } return Task.CompletedTask; }
    }

    private sealed class FakeClients(IClientProxy proxy) : IHubClients
    {
        public IClientProxy All => proxy;
        public IClientProxy AllExcept(IReadOnlyList<string> excludedConnectionIds) => proxy;
        public IClientProxy Client(string connectionId) => proxy;
        public IClientProxy Clients(IReadOnlyList<string> connectionIds) => proxy;
        public IClientProxy Group(string groupName) => proxy;
        public IClientProxy GroupExcept(string groupName, IReadOnlyList<string> excludedConnectionIds) => proxy;
        public IClientProxy Groups(IReadOnlyList<string> groupNames) => proxy;
        public IClientProxy User(string userId) => proxy;
        public IClientProxy Users(IReadOnlyList<string> userIds) => proxy;
    }

    private sealed class FakeGroups : IGroupManager
    {
        public Task AddToGroupAsync(string connectionId, string groupName, CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task RemoveFromGroupAsync(string connectionId, string groupName, CancellationToken cancellationToken = default) => Task.CompletedTask;
    }
}
