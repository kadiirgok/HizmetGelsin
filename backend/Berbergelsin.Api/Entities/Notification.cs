namespace Berbergelsin.Api.Entities;

public sealed class Notification
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public User User { get; set; } = null!;
    public string Type { get; set; } = null!;
    public string Title { get; set; } = null!;
    public string Body { get; set; } = null!;
    public string EntityType { get; set; } = null!;
    public Guid EntityId { get; set; }
    public string Route { get; set; } = null!;
    public bool IsRead { get; set; }
    public DateTime? ReadAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public string DeduplicationKey { get; set; } = null!;
    public string DataJson { get; set; } = "{}";
}

public sealed class DevicePushToken
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public User User { get; set; } = null!;
    public string Platform { get; set; } = null!;
    public string Token { get; set; } = null!;
    public string DeviceId { get; set; } = null!;
    public bool IsActive { get; set; } = true;
    public DateTime LastSeenAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
