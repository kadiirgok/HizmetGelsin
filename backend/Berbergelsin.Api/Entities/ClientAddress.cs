namespace Berbergelsin.Api.Entities;

public sealed class ClientAddress
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public User User { get; set; } = null!;
    public string Label { get; set; } = null!;
    public string? PlaceId { get; set; }
    public string? FormattedAddress { get; set; }
    public string? Province { get; set; }
    public string? District { get; set; }
    public string? Neighborhood { get; set; }
    public string? Street { get; set; }
    public string? StreetNumber { get; set; }
    public string? PostalCode { get; set; }
    public string AddressLine { get; set; } = null!;
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public bool IsDefault { get; set; }
    public bool IsDeleted { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public DateTime? DeletedAt { get; set; }
    public Guid Version { get; set; } = Guid.NewGuid();
}
