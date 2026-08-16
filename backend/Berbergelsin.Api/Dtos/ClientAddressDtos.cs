namespace Berbergelsin.Api.Dtos;

public sealed class SaveClientAddressRequest
{
    public string Label { get; init; } = "";
    public string? PlaceId { get; init; }
    public string? FormattedAddress { get; init; }
    public string? Province { get; init; }
    public string? District { get; init; }
    public string? Neighborhood { get; init; }
    public string? Street { get; init; }
    public string? StreetNumber { get; init; }
    public string? PostalCode { get; init; }
    public string AddressLine { get; init; } = "";
    public double Latitude { get; init; }
    public double Longitude { get; init; }
    public bool IsDefault { get; init; }
    public string? Version { get; init; }
}

public sealed record ClientAddressDto(Guid Id, string Label, string? PlaceId,
    string? FormattedAddress, string? Province, string? District, string? Neighborhood,
    string? Street, string? StreetNumber, string? PostalCode, string AddressLine,
    double Latitude, double Longitude, bool IsDefault, DateTime CreatedAt,
    DateTime UpdatedAt, string Version);
