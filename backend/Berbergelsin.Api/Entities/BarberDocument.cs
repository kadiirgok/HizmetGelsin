using Berbergelsin.Api.Enums;

namespace Berbergelsin.Api.Entities;

public class BarberDocument
{
    public Guid Id { get; set; }
    public Guid BarberProfileId { get; set; }
    public BarberProfile BarberProfile { get; set; } = null!;
    public DocumentType Type { get; set; }
    public string StoredFileName { get; set; } = null!;
    public string OriginalFileName { get; set; } = null!;
    public string ContentType { get; set; } = null!;
    public long SizeBytes { get; set; }
    public DateTime UploadedAt { get; set; }
}
