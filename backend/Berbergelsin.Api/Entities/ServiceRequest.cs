using Berbergelsin.Api.Enums;
using NetTopologySuite.Geometries;

namespace Berbergelsin.Api.Entities;

public class ServiceRequest
{
    public Guid Id { get; set; }
    public Guid ClientUserId { get; set; }
    public User ClientUser { get; set; } = null!;
    public Guid BarberProfileId { get; set; }
    public BarberProfile BarberProfile { get; set; } = null!;
    public RequestStatus Status { get; set; }
    public DateTimeOffset RequestedTime { get; set; }
    public Point? ClientLocation { get; set; }
    public Guid? ClientAddressId { get; set; }
    public ClientAddress? ClientAddress { get; set; }
    public string? AddressSnapshot { get; set; }
    public string? AddressNote { get; set; }
    public decimal TotalPrice { get; set; }
    public Guid? OriginPriceOfferId { get; set; }
    public PriceOffer? OriginPriceOffer { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public Guid CreatedBy { get; set; }
    public DateTimeOffset ScheduledEndTime { get; set; }
    public string? IdempotencyKey { get; set; }
    public string? IdempotencyPayloadHash { get; set; }
    public DateTime? RespondedAt { get; set; }
    public DateTime? OnTheWayAt { get; set; }
    public DateTime? StartedAt { get; set; }
    public DateTime? CompletedAt { get; set; }
    public DateTime? CancelledAt { get; set; }
    public string? CancellationReasonCode { get; set; }
    public string? CancellationReasonText { get; set; }
    public string? CancelledByRole { get; set; }
    public DateTimeOffset? ProposedStartAt { get; set; }
    public DateTimeOffset? PreviousRequestedTime { get; set; }
    public string? RescheduleRequestedByRole { get; set; }
    public Guid Version { get; set; } = Guid.NewGuid();

    public List<ServiceRequestItem> Items { get; set; } = new();
    public List<RequestStatusHistory> StatusHistory { get; set; } = new();
}
