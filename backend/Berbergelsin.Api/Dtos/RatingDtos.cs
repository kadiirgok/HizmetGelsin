namespace Berbergelsin.Api.Dtos;
public sealed record UpdateRatingRequest(int Score,string? Comment,string Version);
public sealed record ReportRatingRequest(string ReasonCode,string? Description);
public sealed record ClientRatingDto(Guid Id,Guid RequestId,Guid BarberId,string? BusinessName,int Rating,string? Comment,DateTime CreatedAt,DateTime? UpdatedAt,string ModerationStatus,string Version);
public sealed record ClientRatingsPageDto(IReadOnlyList<ClientRatingDto> Items,int Page,int PageSize,int TotalCount,bool HasNextPage);
