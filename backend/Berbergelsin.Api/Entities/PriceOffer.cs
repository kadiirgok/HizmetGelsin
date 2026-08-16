using Berbergelsin.Api.Enums;
using NetTopologySuite.Geometries;

namespace Berbergelsin.Api.Entities;

public class PriceOffer
{
    public Guid Id { get; set; }
    public Guid ClientUserId { get; set; }
    public User ClientUser { get; set; } = null!;
    public Guid BarberProfileId { get; set; }
    public BarberProfile BarberProfile { get; set; } = null!;
    public Guid? SourceServiceRequestId { get; set; }
    public ServiceRequest? SourceServiceRequest { get; set; }
    public decimal ProposedPrice { get; set; }
    public decimal? CounterPrice { get; set; }
    public decimal? AcceptedPrice { get; set; }
    public OfferStatus Status { get; set; }
    public string? Note { get; set; }
    public DateTimeOffset RequestedTime { get; set; }
    public Point ClientLocation { get; set; } = null!;
    public DateTime CreatedAt { get; set; }
    public DateTime ExpiresAt { get; set; }
    public Guid Version { get; set; } = Guid.NewGuid();
    public DateTime? RespondedAt { get; set; }
}
