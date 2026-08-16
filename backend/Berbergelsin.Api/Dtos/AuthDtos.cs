using Berbergelsin.Api.Enums;

namespace Berbergelsin.Api.Dtos;

public record SendOtpRequest(string Phone, string? Role);

public record VerifyOtpRequest(string Phone, string Code, string? Role);

public record SendEmailOtpRequest(string Email, string? Role);

public record VerifyEmailOtpRequest(string Email, string Code, string? Phone, string? Role);

public record RefreshTokenRequest(string RefreshToken, string? Role = null);

public record UserDto(
    Guid Id,
    string Phone,
    string Role,
    string? FirstName,
    string? LastName,
    string? Email,
    bool OnboardingCompleted,
    BarberStatus? BarberStatus,
    string? RejectionReason,
    double? AvgRating,
    int RatingCount,
    bool EmailVerified,
    bool IsPhoneVerified);

public record AuthResponse(string AccessToken, string RefreshToken, UserDto User);

public record RegisterRequest(string Email, string Phone, string Password, string Role, string? FirstName = null, string? LastName = null);

public record LoginRequest(string Credential, string Password, string? Role);

public record SendVerificationCodeRequest(string Subject);

public record VerifyCodeRequest(string Code);

public record FirebaseTokenRequest(string FirebaseIdToken);

public record ForgotPasswordRequest(string Credential, string? Role);

public record ResetPasswordRequest(string Credential, string Code, string NewPassword, string? Role);
