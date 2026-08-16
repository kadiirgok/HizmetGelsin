using FirebaseAdmin;
using Google.Apis.Auth.OAuth2;

namespace Berbergelsin.Api.Services;

public interface IFirebaseAppProvider
{
    FirebaseApp? GetApp();
}

public class FirebaseAppProvider : IFirebaseAppProvider
{
    private readonly FirebaseApp? _app;
    private readonly ILogger<FirebaseAppProvider> _logger;

    public FirebaseAppProvider(IConfiguration configuration, IWebHostEnvironment environment, ILogger<FirebaseAppProvider> logger)
    {
        _logger = logger;
        try
        {
            var credPath = configuration["Firebase:CredentialPath"] ?? configuration["PushNotifications:CredentialPath"];
            var projectId = configuration["Firebase:ProjectId"] ?? configuration["PushNotifications:FirebaseProjectId"];

            if (string.IsNullOrWhiteSpace(credPath))
            {
                return;
            }

            var fullPath = Path.IsPathRooted(credPath)
                ? credPath
                : Path.Combine(environment.ContentRootPath, credPath);

            if (!File.Exists(fullPath))
            {
                return;
            }

            if (FirebaseApp.DefaultInstance != null)
            {
                _app = FirebaseApp.DefaultInstance;
                return;
            }

            var credential = CredentialFactory.FromFile<ServiceAccountCredential>(fullPath).ToGoogleCredential();

            _app = FirebaseApp.Create(new AppOptions
            {
                Credential = credential,
                ProjectId = string.IsNullOrWhiteSpace(projectId) ? null : projectId
            });
        }
        catch (Exception ex)
        {
            _logger.LogWarning("FirebaseApp initialization skipped or failed safely: {Message}", ex.Message);
            _app = null;
        }
    }

    public FirebaseApp? GetApp() => _app;
}
