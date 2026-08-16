using Berbergelsin.Api.Enums;
using NetTopologySuite.Geometries;

namespace Berbergelsin.Api.Entities;

public class BarberProfile
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public User User { get; set; } = null!;
    public string? BusinessName { get; set; }
    public string? Category { get; set; }
    public Guid? CategoryId { get; set; }
    public ServiceCategory? ServiceCategory { get; set; }
    public string? Description { get; set; }
    public string ServiceMode { get; set; } = "Mobile";
    public string? City { get; set; }
    public string? District { get; set; }
    public string? Neighborhood { get; set; }
    public string? AddressLine { get; set; }
    public string? TcKimlikNo { get; set; }
    public BarberStatus Status { get; set; }
    public string? RejectionReason { get; set; }
    public bool SharePhone { get; set; }
    public bool AcceptsOffers { get; set; }
    public bool AcceptsUrgentRequests { get; set; }
    public int ServiceRadiusKm { get; set; } = 5;
    /// <summary>geography(Point,4326) — X=lng, Y=lat</summary>
    public Point? Location { get; set; }
    public bool IsOnline { get; set; }
    public DateTime? LastLocationAt { get; set; }
    /// <summary>İşletme logosu (FileStorage içindeki dosya adı)</summary>
    public string? LogoFileName { get; set; }
    /// <summary>jsonb: [{"day":1,"open":"09:00","close":"20:00","closed":false},...]</summary>
    public string WorkingHours { get; set; } = "[]";
    public DateTime CreatedAt { get; set; }
    public DateTime? ApprovedAt { get; set; }

    public List<BarberDocument> Documents { get; set; } = new();
    public List<BarberService> Services { get; set; } = new();
    public List<BusinessPhoto> Photos { get; set; } = new();
}
