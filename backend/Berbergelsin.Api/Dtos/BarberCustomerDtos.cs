namespace Berbergelsin.Api.Dtos;

public record BarberCustomerDto(
    Guid CustomerId,
    string DisplayName,
    string? Phone,
    DateTimeOffset FirstVisit,
    DateTimeOffset LastVisit,
    int CompletedJobCount,
    decimal TotalSpent,
    decimal AverageTicket,
    IReadOnlyList<string> PreferredServices,
    IReadOnlyList<BarberCustomerRecentJobDto> RecentJobs);

public record BarberCustomerRecentJobDto(
    Guid RequestId,
    DateTimeOffset VisitDate,
    decimal TotalPrice,
    IReadOnlyList<string> Services);
