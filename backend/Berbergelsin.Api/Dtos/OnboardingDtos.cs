namespace Berbergelsin.Api.Dtos;

public record ClientOnboardingRequest(string FirstName, string LastName, string Email, string Phone, bool KvkkAccepted);

public record BarberProfileStepRequest(
    string FirstName,
    string LastName,
    string Email,
    string Phone,
    string TcKimlikNo,
    string? BusinessName,
    string? Category,
    bool KvkkAccepted);

public record ServiceItemDto(string Name, decimal Price);

public record BarberServicesStepRequest(List<ServiceItemDto> Services, bool AcceptsOffers);

public record WorkingHourDto(int Day, string Open, string Close, bool Closed);

public record BarberCompleteStepRequest(
    bool SharePhone,
    int ServiceRadiusKm,
    List<WorkingHourDto>? WorkingHours);

public record OnboardingStatusResponse(
    bool OnboardingCompleted,
    string Role,
    string? BarberStatus,
    string? RejectionReason,
    bool HasProfileStep,
    List<string> UploadedDocuments,
    bool HasServices);
