using FirebaseAdmin.Auth;

namespace Berbergelsin.Api.Services;

public class FirebaseAdminIdTokenVerifier : IFirebaseIdTokenVerifier
{
    private readonly IFirebaseAppProvider _appProvider;
    private readonly ILogger<FirebaseAdminIdTokenVerifier> _logger;

    public FirebaseAdminIdTokenVerifier(IFirebaseAppProvider appProvider, ILogger<FirebaseAdminIdTokenVerifier> logger)
    {
        _appProvider = appProvider;
        _logger = logger;
    }

    public async Task<FirebaseVerificationResult> VerifyIdTokenAsync(string firebaseIdToken, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(firebaseIdToken))
        {
            return FirebaseVerificationResult.Failed("auth_google_invalid_token");
        }

        var app = _appProvider.GetApp();
        if (app == null)
        {
            _logger.LogWarning("FirebaseApp is not configured or unavailable.");
            return FirebaseVerificationResult.Failed("auth_google_configuration_error");
        }

        try
        {
            var auth = FirebaseAuth.GetAuth(app);
            var decodedToken = await auth.VerifyIdTokenAsync(firebaseIdToken, ct);

            string? email = FirebaseClaimsReader.ExtractEmail(decodedToken.Claims);
            bool emailVerified = FirebaseClaimsReader.ExtractEmailVerified(decodedToken.Claims);
            string? provider = FirebaseClaimsReader.ExtractSignInProvider(decodedToken.Claims);
            string? phoneNumber = FirebaseClaimsReader.ExtractPhoneNumber(decodedToken.Claims);

            return FirebaseVerificationResult.Ok(new FirebaseVerifiedUser(
                Uid: decodedToken.Uid,
                Email: email,
                EmailVerified: emailVerified,
                PhoneNumber: phoneNumber,
                SignInProvider: provider
            ));
        }
        catch (FirebaseAuthException ex)
        {
            _logger.LogWarning("Firebase token verification failed with error code: {ErrorCode}", ex.AuthErrorCode);
            if (ex.AuthErrorCode is AuthErrorCode.ExpiredIdToken or AuthErrorCode.InvalidIdToken or AuthErrorCode.RevokedIdToken)
            {
                return FirebaseVerificationResult.Failed("auth_google_invalid_token");
            }
            return FirebaseVerificationResult.Failed("auth_google_service_error");
        }
        catch (Exception ex)
        {
            _logger.LogWarning("Firebase token verification failed unexpectedly: {Message}", ex.Message);
            return FirebaseVerificationResult.Failed("auth_google_service_error");
        }
    }
}
