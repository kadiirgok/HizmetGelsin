using Berbergelsin.Api.Enums;

namespace Berbergelsin.Api.Dtos;

public record AdminBarberListItemDto(
    Guid BarberProfileId,
    string? FirstName,
    string? LastName,
    string Phone,
    string? BusinessName,
    BarberStatus Status,
    DateTime CreatedAt);

public record AdminBarberDetailDto(
    Guid BarberProfileId,
    string? FirstName,
    string? LastName,
    string Phone,
    string? Email,
    string? BusinessName,
    string? TcKimlikNo,
    BarberStatus Status,
    string? RejectionReason,
    bool SharePhone,
    bool AcceptsOffers,
    int ServiceRadiusKm,
    string WorkingHours,
    List<AdminDocumentDto> Documents,
    List<BarberServiceDto> Services,
    DateTime CreatedAt);

public record AdminDocumentDto(Guid Id, DocumentType Type, string OriginalFileName, string ContentType, long SizeBytes);

public record RejectBarberRequest(string Reason);
