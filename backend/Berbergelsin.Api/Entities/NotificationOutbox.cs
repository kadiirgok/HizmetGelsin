namespace Berbergelsin.Api.Entities;

public enum OutboxStatus { Pending = 1, Processing = 2, Completed = 3, Failed = 4, DeadLetter = 5 }
public enum DeliveryStatus { Pending = 1, Completed = 2, Failed = 3, Skipped = 4 }

public sealed class NotificationOutbox
{
    public Guid Id { get; set; }
    public Guid NotificationId { get; set; }
    public Notification Notification { get; set; } = null!;
    public Guid UserId { get; set; }
    public string EventType { get; set; } = null!;
    public string PayloadJson { get; set; } = null!;
    public OutboxStatus Status { get; set; } = OutboxStatus.Pending;
    public DeliveryStatus SignalRStatus { get; set; } = DeliveryStatus.Pending;
    public DeliveryStatus PushStatus { get; set; } = DeliveryStatus.Pending;
    public int AttemptCount { get; set; }
    public int SignalRAttemptCount { get; set; }
    public int PushAttemptCount { get; set; }
    public DateTime NextAttemptAt { get; set; }
    public DateTime? LockedAt { get; set; }
    public string? LockedBy { get; set; }
    public DateTime? LastAttemptAt { get; set; }
    public DateTime? CompletedAt { get; set; }
    public DateTime? FailedAt { get; set; }
    public string? LastErrorCode { get; set; }
    public DateTime CreatedAt { get; set; }
    public Guid ConcurrencyToken { get; set; } = Guid.NewGuid();
}
