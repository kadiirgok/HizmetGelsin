namespace Berbergelsin.Api.Entities;

public enum OtpPurpose
{
    Login = 0,
    GooglePhoneLink = 1,
    EmailVerification = 2,
    PhoneVerification = 3
}

public class OtpCode
{
    public Guid Id { get; set; }
    public string? PhoneNumber { get; set; }
    public string? Email { get; set; }
    public OtpPurpose Purpose { get; set; } = OtpPurpose.Login;
    public string? Subject { get; set; }
    /// <summary>HMAC-SHA256(kod, Otp:Pepper)</summary>
    public string CodeHash { get; set; } = null!;
    public DateTime ExpiresAt { get; set; }
    public int AttemptCount { get; set; }
    public bool Consumed { get; set; }
    public string? RequestIp { get; set; }
    public DateTime CreatedAt { get; set; }
}
