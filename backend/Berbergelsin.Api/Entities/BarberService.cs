namespace Berbergelsin.Api.Entities;

public class BarberService
{
    public Guid Id { get; set; }
    public Guid BarberProfileId { get; set; }
    public BarberProfile BarberProfile { get; set; } = null!;
    public Guid? ServiceDefinitionId { get; set; }
    public ServiceDefinition? ServiceDefinition { get; set; }
    public string Name { get; set; } = null!;
    public string? Description { get; set; }
    public decimal Price { get; set; }
    public string PriceType { get; set; } = "Fixed";
    public int? DurationMinutes { get; set; }
    public bool IsPopular { get; set; }
    public int SortOrder { get; set; }
    public bool IsActive { get; set; } = true;
}
