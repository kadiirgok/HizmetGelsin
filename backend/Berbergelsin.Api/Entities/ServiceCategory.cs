namespace Berbergelsin.Api.Entities;

public class ServiceCategory
{
    public Guid Id { get; set; }
    public Guid GroupId { get; set; }
    public CategoryGroup Group { get; set; } = null!;
    public string Name { get; set; } = null!;
    public int SortOrder { get; set; }
}
