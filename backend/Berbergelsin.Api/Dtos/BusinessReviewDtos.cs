namespace Berbergelsin.Api.Dtos;

public record BusinessReviewItemDto(
    Guid Id,
    int Rating,
    string? Comment,
    DateTime CreatedAt,
    string CustomerDisplayName,
    string? CustomerAvatarUrl,
    string? ServiceName,
    Guid ServiceRequestId);

public record BusinessReviewsSummaryDto(
    double AverageRating,
    int TotalCount,
    IReadOnlyDictionary<int, int> RatingDistribution);

public record BusinessReviewsPageDto(
    IReadOnlyList<BusinessReviewItemDto> Items,
    int Page,
    int PageSize,
    int TotalCount,
    int TotalPages,
    BusinessReviewsSummaryDto Summary);