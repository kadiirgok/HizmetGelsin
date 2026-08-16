namespace Berbergelsin.Api.Services;

public record FirebaseVerifiedUser(
    string Uid,
    string? Email,
    bool EmailVerified,
    string? PhoneNumber = null,
    string? SignInProvider = null
);

public record FirebaseVerificationResult(
    bool Success,
    FirebaseVerifiedUser? User = null,
    string? ErrorCode = null
)
{
    public static FirebaseVerificationResult Ok(FirebaseVerifiedUser user) => new(true, user, null);
    public static FirebaseVerificationResult Failed(string errorCode) => new(false, null, errorCode);
}

public interface IFirebaseIdTokenVerifier
{
    Task<FirebaseVerificationResult> VerifyIdTokenAsync(string idToken, CancellationToken ct = default);
}
