namespace Berbergelsin.Api.Dtos;

public record NearbyBarberDto(
    Guid BarberProfileId,
    string? BusinessName,
    string? FirstName,
    string? Category,
    string? Description,
    string? ServiceMode,
    string? City,
    string? District,
    string? Neighborhood,
    double Lat,
    double Lng,
    bool AcceptsOffers,
    bool AcceptsUrgentRequests,
    double DistanceMeters,
    double? AvgRating,
    int RatingCount,
    bool HasLogo,
    string? CoverPhotoUrl);

public sealed class NearbyDiscoveryQuery
{
    public double? Lat { get; init; }
    public double? Lng { get; init; }
    public double? RadiusKm { get; init; }
    public string? Q { get; init; }
    public string? Category { get; init; }
    public Guid? ServiceId { get; init; }
    public string? City { get; init; }
    public string? District { get; init; }
    public string? Neighborhood { get; init; }
    public decimal? MinPrice { get; init; }
    public decimal? MaxPrice { get; init; }
    public double? MinRating { get; init; }
    public string? ServiceMode { get; init; }
    public DateTimeOffset? AvailableAt { get; init; }
    public string? Sort { get; init; }
    public int Page { get; init; } = 1;
    public int PageSize { get; init; } = 20;
}

public record DiscoveryPageDto<T>(IReadOnlyList<T> Items, int Page, int PageSize, int TotalCount, bool HasNextPage);

public record TopServiceDto(string Name, decimal Price);

public record DiscoveryBarberDto(
    Guid Id, string? Name, string? Description, string? Category, string? District, string? City,
    string? Neighborhood,
    double DistanceKm, double? Rating, int ReviewCount, string? CoverImageUrl,
    string? ProfileImageUrl, int ServiceCount, decimal? MinimumPrice,
    bool IsOpenNow, int ServiceRadiusKm, double Lat, double Lng,
    List<TopServiceDto>? TopServices = null);

public record BarberDetailDto(
    Guid BarberProfileId,
    string? BusinessName,
    string? FirstName,
    string? LastName,
    string? Category,
    string? Description,
    string ServiceMode,
    string? City,
    string? District,
    string? Neighborhood,
    string? AddressLine,
    string WorkingHours,
    bool AcceptsOffers,
    bool AcceptsUrgentRequests,
    List<BarberServiceDto> Services,
    List<BusinessPhotoDto> Photos,
    double? Lat,
    double? Lng,
    double? AvgRating,
    int RatingCount,
    bool HasLogo,
    List<ReviewDto> Reviews,
    string? CoverImageUrl = null,
    string? ProfileImageUrl = null,
    bool IsOpenNow = false,
    int ServiceRadiusKm = 0);

public record ReviewDto(
    int Score,
    string? Comment,
    string? ClientName,
    DateTime CreatedAt,
    Guid Id = default,
    DateTime? UpdatedAt = null,
    string? CustomerDisplayName = null,
    string? CustomerAvatarUrl = null,
    bool IsOwn = false,
    string? Version = null);

public record BarberReviewsPageDto(
    IReadOnlyList<ReviewDto> Items, int Page, int PageSize, int TotalCount, bool HasNextPage,
    double? AverageRating);

public record AvailabilityIntervalDto(string Open, string Close);

public record BarberAvailabilitySummaryDto(
    Guid BarberProfileId, DateOnly Date, string TimeZone, bool IsWorkingDay,
    bool IsOpenNow, IReadOnlyList<AvailabilityIntervalDto> WorkingIntervals,
    string Precision);

public record BarberServiceDto(
    Guid Id,
    string Name,
    decimal Price,
    string? Description = null,
    string PriceType = "Fixed",
    int? DurationMinutes = null,
    bool IsPopular = false);

public record BusinessPhotoDto(Guid Id, string Url, string? Caption, bool IsCover, int SortOrder);

public record CategoryGroupDto(Guid Id, string Name, string? Icon, List<ServiceCategoryDto> Categories);
public record ServiceCategoryDto(Guid Id, string Name, int SortOrder);

public record BusinessDashboardDto(
    int TodayRequestCount,
    int PendingRequestCount,
    int PendingOfferCount,
    int ActiveRequestCount,
    int CompletedThisWeek,
    int CompletedTotal,
    decimal TodayRevenue,
    decimal WeekRevenue,
    decimal TotalRevenue,
    double? AvgRating,
    int RatingCount,
    int UniqueCustomerCount,
    string? TopServiceName,
    int TopServiceCount,
    int AverageResponseMinutes,
    int WeekAnsweredRequestCount,
    int ConversionRate,
    int OfferTotalCount);

public record UpdateOnlineRequest(bool IsOnline);

public record UpdateLocationRequest(double Lat, double Lng);

public record BarberProfileDto(
    Guid BarberProfileId,
    string? BusinessName,
    string? Category,
    string? Description,
    string ServiceMode,
    string? City,
    string? District,
    string? Neighborhood,
    string? AddressLine,
    string? FirstName,
    string? LastName,
    string Status,
    string? RejectionReason,
    bool SharePhone,
    bool AcceptsOffers,
    bool AcceptsUrgentRequests,
    int ServiceRadiusKm,
    bool IsOnline,
    string? WorkingHours,
    double? Lat,
    double? Lng,
    List<BusinessPhotoDto> Photos,
    List<BarberServiceDto> Services,
    string? PhoneNumber = null,
    string? Email = null,
    string? LogoUrl = null,
    string? CoverPhotoUrl = null,
    double? AvgRating = null,
    int RatingCount = 0,
    bool HasLogo = false);

public record UpdateBarberProfileRequest(
    string? BusinessName,
    string? Category,
    string? Description,
    string? ServiceMode,
    string? City,
    string? District,
    string? Neighborhood,
    string? AddressLine,
    bool SharePhone,
    bool AcceptsOffers,
    bool AcceptsUrgentRequests,
    int ServiceRadiusKm,
    List<WorkingHourDto>? WorkingHours);

public record UpsertServiceRequest(
    string Name,
    decimal Price,
    string? Description,
    string? PriceType,
    int? DurationMinutes,
    bool IsPopular);
