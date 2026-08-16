namespace Berbergelsin.Api.Dtos;

public sealed record NotificationDto(Guid Id, string Type, string Title, string Body,
    string EntityType, Guid EntityId, string Route, bool IsRead, DateTime? ReadAt, DateTime CreatedAt);
public sealed record NotificationPageDto(IReadOnlyList<NotificationDto> Items, int Page,
    int PageSize, int TotalCount, bool HasNextPage);
public sealed record RegisterDeviceRequest(string Platform, string Token, string DeviceId);
