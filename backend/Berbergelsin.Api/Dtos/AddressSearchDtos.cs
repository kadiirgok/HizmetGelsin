using System.ComponentModel.DataAnnotations;
namespace Berbergelsin.Api.Dtos;
public sealed record AddressPredictionDto(string PlaceId,string PrimaryText,string SecondaryText,string DisplayText);
public sealed record ResolvedAddressDto(string PlaceId,string? FormattedAddress,string? Province,string? District,string? Neighborhood,string? Street,string? StreetNumber,string? PostalCode,double Latitude,double Longitude,string CountryCode);
public sealed class AddressAutocompleteRequest { [Required,StringLength(120,MinimumLength=3)] public string Q {get;init;}=""; [Required] public string SessionToken {get;init;}=""; public string? Province {get;init;} public string? District {get;init;} [Range(-90,90)] public double? Latitude {get;init;} [Range(-180,180)] public double? Longitude {get;init;} }
public sealed record AddressErrorDto(string Code);