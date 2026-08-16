using Berbergelsin.Api.Data;
using FirebaseAdmin;
using FirebaseAdmin.Messaging;
using Google.Apis.Auth.OAuth2;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Berbergelsin.Api.Services;

public sealed record PushNotificationMessage(Guid NotificationId, Guid UserId, string Type, string Title,
    string Body, string EntityType, Guid EntityId, string Route)
{
    public PushNotificationMessage(Guid userId, string type, string title, string body,
        string entityType, Guid entityId, string route)
        : this(Guid.Empty, userId, type, title, body, entityType, entityId, route) { }
}

public interface IPushNotificationSender
{
    Task SendAsync(PushNotificationMessage message, CancellationToken cancellationToken = default);
}

public sealed class NoOpPushNotificationSender : IPushNotificationSender
{
    public Task SendAsync(PushNotificationMessage message, CancellationToken cancellationToken = default)
        => Task.CompletedTask;
}

public sealed class PushNotificationOptions
{
    public const string Section = "PushNotifications";
    public string Provider { get; set; } = "NoOp";
    public string FirebaseProjectId { get; set; } = "";
    public string CredentialPath { get; set; } = "";
    public bool Enabled { get; set; }
}

public sealed class PushDeliveryException(string code, bool permanent) : Exception(code)
{
    public string Code { get; } = code;
    public bool Permanent { get; } = permanent;
}

public static class PushPayloadPolicy
{
    public static IReadOnlyDictionary<string, string> Data(PushNotificationMessage message)
    {
        if (!NotificationOutboxProcessor.IsValidRoute(message.Route))
            throw new PushDeliveryException("push_provider_permanent", true);
        return new Dictionary<string, string>
        {
            ["notificationId"] = message.NotificationId.ToString(),
            ["type"] = message.Type.Length <= 80 ? message.Type : message.Type[..80],
            ["route"] = message.Route
        };
    }
}

public sealed class FirebasePushNotificationSender : IPushNotificationSender, IDisposable
{
    private readonly AppDbContext db;
    private readonly FirebaseApp app;
    private readonly ILogger<FirebasePushNotificationSender>? _logger;

    public FirebasePushNotificationSender(AppDbContext db, IOptions<PushNotificationOptions> options,
        IWebHostEnvironment environment, ILogger<FirebasePushNotificationSender>? logger = null)
    {
        _logger = logger;
        this.db = db;
        var value = options.Value;
        var path = Path.IsPathRooted(value.CredentialPath)
            ? value.CredentialPath : Path.Combine(environment.ContentRootPath, value.CredentialPath);
        app = FirebaseApp.Create(new AppOptions
        {
            Credential = CredentialFactory.FromFile<ServiceAccountCredential>(path).ToGoogleCredential(),
            ProjectId = value.FirebaseProjectId
        }, $"push-{Guid.NewGuid():N}");
        _logger?.LogInformation("FirebasePushNotificationSender initialized for project {ProjectId}", value.FirebaseProjectId);
    }

    public async Task SendAsync(PushNotificationMessage message, CancellationToken cancellationToken = default)
    {
        var tokens = await db.DevicePushTokens
            .Where(x => x.UserId == message.UserId && x.IsActive)
            .ToListAsync(cancellationToken);

        _logger?.LogInformation("Push send: UserId={UserId}, Tokens={TokenCount}, Title={Title}",
            message.UserId, tokens.Count, message.Title);

        if (tokens.Count == 0)
        {
            // Cihaz token'ı yok → push gönderilemez. Kullanıcı uygulamaya giriş yapınca
            // PushService.bindUser() token'ı kaydeder.
            _logger?.LogWarning("Push skipped: no device tokens for UserId={UserId}", message.UserId);
            return;
        }

        PushDeliveryException? deferred = null;
        foreach (var device in tokens)
        {
            try
            {
                await FirebaseMessaging.GetMessaging(app).SendAsync(new Message
                {
                    Fid = device.Token,
                    Notification = new Notification
                    {
                        Title = SafeText(message.Title, "Yeni bildirim", 80),
                        Body = SafeText(message.Body, "Uygulamada yeni bir gelişme var.", 160)
                    },
                    Data = PushPayloadPolicy.Data(message),
                    Android = new AndroidConfig { Notification = new AndroidNotification { ChannelId = "hizmetgelsin_updates" } }
                }, cancellationToken);
            }
            catch (FirebaseMessagingException ex)
            {
                var classified = Classify(ex.MessagingErrorCode);
                if (classified.Code == "push_token_invalid")
                {
                    device.IsActive = false;
                    device.UpdatedAt = DateTime.UtcNow;
                }
                else deferred ??= classified;
            }
        }
        await db.SaveChangesAsync(cancellationToken);
        if (deferred != null) throw deferred;
    }

    internal static PushDeliveryException Classify(MessagingErrorCode? code) => code switch
    {
        MessagingErrorCode.Unregistered or MessagingErrorCode.InvalidArgument or MessagingErrorCode.SenderIdMismatch
            => new("push_token_invalid", true),
        MessagingErrorCode.ThirdPartyAuthError => new("push_provider_auth_failed", true),
        MessagingErrorCode.QuotaExceeded => new("push_provider_rate_limited", false),
        MessagingErrorCode.Unavailable or MessagingErrorCode.Internal => new("push_provider_transient", false),
        _ => new("push_provider_permanent", true)
    };

    private static string SafeText(string value, string fallback, int max) =>
        string.IsNullOrWhiteSpace(value) ? fallback : value.Trim()[..Math.Min(value.Trim().Length, max)];

    public void Dispose() => app.Delete();
}

public static class PushNotificationRegistration
{
    public static IServiceCollection AddPushNotifications(this IServiceCollection services,
        IConfiguration configuration, IWebHostEnvironment environment)
    {
        services.Configure<PushNotificationOptions>(configuration.GetSection(PushNotificationOptions.Section));
        services.AddSingleton<NoOpPushNotificationSender>();
        var options = configuration.GetSection(PushNotificationOptions.Section).Get<PushNotificationOptions>() ?? new();
        var credentialPath = Path.IsPathRooted(options.CredentialPath)
            ? options.CredentialPath : Path.Combine(environment.ContentRootPath, options.CredentialPath);
        var ready = options.Enabled && options.Provider.Equals("Firebase", StringComparison.OrdinalIgnoreCase)
            && !string.IsNullOrWhiteSpace(options.FirebaseProjectId)
            && !string.IsNullOrWhiteSpace(options.CredentialPath) && File.Exists(credentialPath);
        if (ready)
        {
            Console.WriteLine("### PUSH: FirebasePushNotificationSender kullanılıyor. ProjectId={0}, CredentialPath={1}", options.FirebaseProjectId, credentialPath);
            services.AddScoped<FirebasePushNotificationSender>();
            services.AddScoped<IPushNotificationSender>(sp => sp.GetRequiredService<FirebasePushNotificationSender>());
        }
        else
        {
            Console.WriteLine("### PUSH: NoOpPushNotificationSender kullanılıyor. Enabled={0}, Provider={1}, ProjectId={2}, CredentialPath={3}, FileExists={4}",
                options.Enabled, options.Provider, options.FirebaseProjectId, credentialPath, File.Exists(credentialPath));
            services.AddScoped<IPushNotificationSender>(sp => sp.GetRequiredService<NoOpPushNotificationSender>());
        }
        return services;
    }
}
