namespace Berbergelsin.Api.Dtos;

public sealed record ClientProfileDto(
    Guid Id,
    string? FirstName,
    string? LastName,
    string PhoneNumber,
    string? Email,
    string? ProfileImageUrl,
    bool IsPhoneVerified,
    DateTime CreatedAt,
    string Version);

public sealed class UpdateClientProfileRequest
{
    public string FirstName { get; init; } = "";
    public string LastName { get; init; } = "";
    public string? Email { get; init; }
    public string? ProfileImageUrl { get; init; }
    public string Version { get; init; } = "";
}
