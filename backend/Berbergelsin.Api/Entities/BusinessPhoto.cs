namespace Berbergelsin.Api.Entities;

public class BusinessPhoto
{
    public Guid Id { get; set; }
    public Guid BarberProfileId { get; set; }
    public BarberProfile BarberProfile { get; set; } = null!;
    public string StoredFileName { get; set; } = null!;
    public string OriginalFileName { get; set; } = null!;
    public string ContentType { get; set; } = null!;
    public long SizeBytes { get; set; }
    public string? Caption { get; set; }
    public bool IsCover { get; set; }
    public int SortOrder { get; set; }
    public DateTime CreatedAt { get; set; }
}
