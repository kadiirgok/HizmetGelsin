using Berbergelsin.Api.Enums;

namespace Berbergelsin.Api.Dtos;

public record CreateServiceRequestDto(
    Guid BarberProfileId,
    List<Guid> ServiceIds,
    DateTimeOffset RequestedTime,
    double? Lat,
    double? Lng,
    string? AddressNote,
    Guid? AddressId = null,
    string? ServiceLocationType = null,
    string? AddressSnapshot = null,
    decimal? ProposedPrice = null);

public record ServiceRequestDto(
    Guid Id,
    Guid BarberProfileId,
    string? BarberBusinessName,
    string? ClientName,
    string? ClientPhone,
    string? BarberPhone,
    RequestStatus Status,
    DateTimeOffset RequestedTime,
    double? Lat,
    double? Lng,
    string? AddressNote,
    decimal TotalPrice,
    List<RequestItemDto> Items,
    DateTime CreatedAt,
    DateTime? OnTheWayAt,
    DateTime? StartedAt,
    DateTime? CompletedAt,
    double? BarberLat,
    double? BarberLng,
    bool CanRate,
    int? MyScore,
    Guid? AddressId,
    string? AddressSnapshot,
    string ServiceLocationType,
    DateTime UpdatedAt,
    Guid ConcurrencyToken,
    DateTime? RespondedAt,
    DateTime? CancelledAt,
    object? Cancellation,
    object? Reschedule);

public record RateRequestDto(int Score, string? Comment);

public record UpdateRequestNoteDto(string? Note);

public record RequestItemDto(string ServiceName, decimal Price);

public record CreatePriceOfferDto(
    Guid BarberProfileId,
    decimal ProposedPrice,
    DateTimeOffset RequestedTime,
    double Lat,
    double Lng,
    string? Note);

public record CounterOfferDto(decimal CounterPrice);

public record CreateBarberOfferDto(
    Guid ServiceRequestId,
    decimal Price,
    DateTimeOffset? RequestedTime,
    string? Note);

public record PriceOfferDto(
    Guid Id,
    Guid BarberProfileId,
    string? BarberBusinessName,
    string? ClientName,
    decimal ProposedPrice,
    decimal? CounterPrice,
    OfferStatus Status,
    DateTimeOffset RequestedTime,
    string? Note,
    DateTime CreatedAt,
    DateTime ExpiresAt,
    decimal? AcceptedPrice);

public record RejectRequestDto(string? Reason);

public record CancelRequestDto(string? ReasonCode, string? ReasonText);
public record RescheduleRequestDto(DateTimeOffset RequestedStartAt, string? Reason);
public record VerifyCodeDto(string Code);
public record RequestTimelineDto(Guid Id, RequestStatus FromStatus, RequestStatus ToStatus,
    string ChangedByRole, string? ReasonCode, string? ReasonText, DateTime CreatedAt);
