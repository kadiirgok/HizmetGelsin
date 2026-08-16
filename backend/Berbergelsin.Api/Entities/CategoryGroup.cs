namespace Berbergelsin.Api.Entities;

public class CategoryGroup
{
    public Guid Id { get; set; }
    public string Name { get; set; } = null!;
    public string? Icon { get; set; }
    public int SortOrder { get; set; }
    public List<ServiceCategory> Categories { get; set; } = new();
}
