using Berbergelsin.Api.Enums;

namespace Berbergelsin.Api.Entities;

public class User
{
    public Guid Id { get; set; }
    /// <summary>Normalize edilmiş format: "905XXXXXXXXX"</summary>
    public string PhoneNumber { get; set; } = string.Empty;
    public UserRole Role { get; set; }
    public string? FirstName { get; set; }
    public string? LastName { get; set; }
    public string? Email { get; set; }
    public string? ProfileImageUrl { get; set; }
    public string? FirebaseUid { get; set; }
    public string? PasswordHash { get; set; }
    public bool IsPhoneVerified { get; set; }
    public bool EmailVerified { get; set; }
    public AccountStatus AccountStatus { get; set; } = AccountStatus.Active;
    public DateTime? DeletionRequestedAt { get; set; }
    public Guid ProfileVersion { get; set; } = Guid.NewGuid();
    public int TokenVersion { get; set; }
    public DateTime? KvkkAcceptedAt { get; set; }
    public bool OnboardingCompleted { get; set; }
    public int FailedLoginAttempts { get; set; }
    public DateTime? LockoutEnd { get; set; }
    public DateTime CreatedAt { get; set; }

    public BarberProfile? BarberProfile { get; set; }
    public List<RefreshToken> RefreshTokens { get; set; } = new();
}
