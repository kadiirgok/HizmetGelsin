namespace Berbergelsin.Api.Entities;

public class ServiceDefinition
{
    public Guid Id { get; set; }
    public string Name { get; set; } = null!;
    public string NormalizedName { get; set; } = null!;
    public string CategoryName { get; set; } = null!;
    public string NormalizedCategoryName { get; set; } = null!;
    public bool IsActive { get; set; } = true;
    public int SortOrder { get; set; }
    public DateTime CreatedAt { get; set; }
    public List<BarberService> BusinessServices { get; set; } = new();
}
