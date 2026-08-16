using Berbergelsin.Api.Enums;

namespace Berbergelsin.Api.Entities;

public sealed class RequestStatusHistory
{
    public Guid Id { get; set; }
    public Guid RequestId { get; set; }
    public ServiceRequest Request { get; set; } = null!;
    public RequestStatus FromStatus { get; set; }
    public RequestStatus ToStatus { get; set; }
    public Guid ChangedByUserId { get; set; }
    public string ChangedByRole { get; set; } = null!;
    public string? ReasonCode { get; set; }
    public string? ReasonText { get; set; }
    public DateTime CreatedAt { get; set; }
}
