namespace Berbergelsin.Api.Dtos;

public record ServiceCatalogItemDto(Guid Id, string Name, Guid? CategoryId, string CategoryName, bool IsActive);
