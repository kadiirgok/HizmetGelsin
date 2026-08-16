namespace Berbergelsin.Api.Entities;

public sealed class RequestOperation
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string IdempotencyKey { get; set; } = null!;
    public string PayloadHash { get; set; } = null!;
    public Guid RequestId { get; set; }
    public string ResultJson { get; set; } = null!;
    public DateTime CreatedAt { get; set; }
}
