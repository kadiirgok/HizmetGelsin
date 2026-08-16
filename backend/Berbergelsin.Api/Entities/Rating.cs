using Berbergelsin.Api.Enums;
namespace Berbergelsin.Api.Entities;

/// <summary>Tamamlanan randevu sonrası karşılıklı puanlama (müşteri↔işletme).</summary>
public class Rating
{
    public Guid Id { get; set; }
    public Guid ServiceRequestId { get; set; }
    public ServiceRequest ServiceRequest { get; set; } = null!;
    /// <summary>Puanı veren kullanıcı</summary>
    public Guid RaterUserId { get; set; }
    public User RaterUser { get; set; } = null!;
    /// <summary>Puanı alan kullanıcı (karşı taraf)</summary>
    public Guid RatedUserId { get; set; }
    public User RatedUser { get; set; } = null!;
    /// <summary>1-5</summary>
    public int Score { get; set; }
    public string? Comment { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public bool IsDeleted { get; set; }
    public DateTime? DeletedAt { get; set; }
    public Guid? DeletedByUserId { get; set; }
    public RatingModerationStatus ModerationStatus { get; set; } = RatingModerationStatus.Visible;
    public Guid Version { get; set; } = Guid.NewGuid();
}
