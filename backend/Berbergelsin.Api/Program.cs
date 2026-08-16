using System.Text;
using System.Threading.RateLimiting;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Services;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

// --- Veritabanı (PostgreSQL + PostGIS) ---
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(
        builder.Configuration.GetConnectionString("Default"),
        o => o.UseNetTopologySuite()));

// --- JWT Authentication ---
var jwtKey = builder.Configuration["Jwt:Key"]
    ?? throw new InvalidOperationException("Jwt:Key tanımlı değil");

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = builder.Configuration["Jwt:Issuer"],
            ValidateAudience = true,
            ValidAudience = builder.Configuration["Jwt:Audience"],
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            RequireSignedTokens = true,
            ValidAlgorithms = [SecurityAlgorithms.HmacSha256],
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtKey)),
            ClockSkew = TimeSpan.FromMinutes(1)
        };

        // SignalR: WebSocket bağlantısında token query string'den gelir
        options.Events = new JwtBearerEvents
        {
            OnMessageReceived = context =>
            {
                var accessToken = context.Request.Query["access_token"];
                if (!string.IsNullOrEmpty(accessToken) &&
                    context.HttpContext.Request.Path.StartsWithSegments("/hubs"))
                {
                    context.Token = accessToken;
                }
                return Task.CompletedTask;
            },
            OnTokenValidated = async context =>
            {
                var subject = context.Principal?.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
                var role = context.Principal?.FindFirst(System.Security.Claims.ClaimTypes.Role)?.Value;
                var accountRole = context.Principal?.FindFirst("accountRole")?.Value;
                var versionRaw = context.Principal?.FindFirst("tokenVersion")?.Value;
                if (!Guid.TryParse(subject, out var userId) ||
                    !int.TryParse(versionRaw, out var tokenVersion) || string.IsNullOrWhiteSpace(role))
                {
                    context.Fail("auth_invalid_token");
                    return;
                }

                var db = context.HttpContext.RequestServices.GetRequiredService<AppDbContext>();
                var account = await db.Users.AsNoTracking()
                    .Where(u => u.Id == userId)
                    .Select(u => new { u.Role, u.AccountStatus, u.TokenVersion })
                    .SingleOrDefaultAsync(context.HttpContext.RequestAborted);
                if (account == null)
                {
                    context.Fail("auth_account_inactive");
                    return;
                }
                if (account.AccountStatus == Berbergelsin.Api.Enums.AccountStatus.Pending)
                {
                    var path = context.HttpContext.Request.Path;
                    if (!path.StartsWithSegments("/api/onboarding") && !path.Equals("/api/auth/me"))
                    {
                        context.Fail("auth_account_pending");
                        return;
                    }
                }
                else if (account.AccountStatus != Berbergelsin.Api.Enums.AccountStatus.Active)
                {
                    context.Fail("auth_account_inactive");
                    return;
                }

                var persistentRole = account.Role.ToString();
                if (role != persistentRole || accountRole != persistentRole)
                {
                    context.Fail("auth_role_mismatch");
                    return;
                }
                if (tokenVersion != account.TokenVersion)
                    context.Fail("auth_session_revoked");
            },
            OnChallenge = async context =>
            {
                if (context.Response.HasStarted) return;
                context.HandleResponse();
                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                context.Response.ContentType = "application/json";
                var reason = context.AuthenticateFailure?.Message;
                var code = reason switch
                {
                    "auth_role_mismatch" => "auth_role_mismatch",
                    "auth_session_revoked" => "auth_session_revoked",
                    "auth_account_inactive" => "auth_account_inactive",
                    "auth_account_pending" => "auth_account_pending",
                    _ => "auth_invalid_token"
                };
                await context.Response.WriteAsJsonAsync(new { code });
            }
        };
    });

builder.Services.AddAuthorization();

// --- Rate Limiting (Cloudflare arkasında gerçek IP: CF-Connecting-IP) ---
static string ResolveClientIp(HttpContext ctx) =>
    ctx.Request.Headers["CF-Connecting-IP"].FirstOrDefault()
    ?? ctx.Connection.RemoteIpAddress?.ToString()
    ?? "unknown";

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.OnRejected = async (context, cancellationToken) =>
    {
        context.HttpContext.Response.ContentType = "application/json";
        if (context.Lease.TryGetMetadata(MetadataName.RetryAfter, out var retryAfter))
            context.HttpContext.Response.Headers.RetryAfter = Math.Ceiling(retryAfter.TotalSeconds).ToString(System.Globalization.CultureInfo.InvariantCulture);
        var code = context.HttpContext.Request.Path.StartsWithSegments("/api/barbers/nearby")
            ? "discovery_rate_limited"
            : context.HttpContext.Request.Path.StartsWithSegments("/api/client/addresses")
            ? "client_address_rate_limited"
            : context.HttpContext.Request.Path.StartsWithSegments("/api/client/favorites")
            ? "favorite_rate_limited"
            : context.HttpContext.Request.Path.Equals("/api/requests")
            ? "request_rate_limited"
            : context.HttpContext.Request.Path.StartsWithSegments("/api/offers")
            ? "offer_rate_limited"
            : context.HttpContext.Request.Path.StartsWithSegments("/api/notifications")
            ? "notification_rate_limited"
            : "address_search_rate_limited";
        await context.HttpContext.Response.WriteAsJsonAsync(new { code }, cancellationToken);
    };

    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(ctx =>
        RateLimitPartition.GetFixedWindowLimiter(ResolveClientIp(ctx), _ =>
            new FixedWindowRateLimiterOptions
            {
                PermitLimit = 300,
                Window = TimeSpan.FromMinutes(1)
            }));

    options.AddPolicy("otp", ctx =>
        RateLimitPartition.GetFixedWindowLimiter(ResolveClientIp(ctx), _ =>
            new FixedWindowRateLimiterOptions
            {
                PermitLimit = 10,
                Window = TimeSpan.FromMinutes(5)
            }));
    options.AddPolicy("address-search", ctx => RateLimitPartition.GetFixedWindowLimiter(ctx.User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value ?? ResolveClientIp(ctx), _ => new FixedWindowRateLimiterOptions { PermitLimit = builder.Configuration.GetValue("AddressSearch:PermitLimit", 30), Window = TimeSpan.FromSeconds(builder.Configuration.GetValue("AddressSearch:WindowSeconds", 60)), QueueLimit = 0, AutoReplenishment = true }));
    options.AddPolicy("discovery", ctx => RateLimitPartition.GetFixedWindowLimiter(ctx.User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value ?? ResolveClientIp(ctx), _ => new FixedWindowRateLimiterOptions { PermitLimit = builder.Configuration.GetValue("Discovery:PermitLimit", 60), Window = TimeSpan.FromSeconds(builder.Configuration.GetValue("Discovery:WindowSeconds", 60)), QueueLimit = 0, AutoReplenishment = true }));
    options.AddPolicy("service-request", ctx => RateLimitPartition.GetFixedWindowLimiter(ctx.User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value ?? ResolveClientIp(ctx), _ => new FixedWindowRateLimiterOptions { PermitLimit = builder.Configuration.GetValue("ServiceRequest:PermitLimit", 10), Window = TimeSpan.FromSeconds(builder.Configuration.GetValue("ServiceRequest:WindowSeconds", 60)), QueueLimit = 0, AutoReplenishment = true }));
    options.AddPolicy("offer-write", ctx => RateLimitPartition.GetFixedWindowLimiter(ctx.User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value ?? ResolveClientIp(ctx), _ => new FixedWindowRateLimiterOptions { PermitLimit = builder.Configuration.GetValue("Offer:PermitLimit", 20), Window = TimeSpan.FromSeconds(builder.Configuration.GetValue("Offer:WindowSeconds", 60)), QueueLimit = 0, AutoReplenishment = true }));
    options.AddPolicy("client-address", ctx => RateLimitPartition.GetFixedWindowLimiter(ctx.User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value ?? ResolveClientIp(ctx), _ => new FixedWindowRateLimiterOptions { PermitLimit = builder.Configuration.GetValue("ClientAddresses:PermitLimit", 60), Window = TimeSpan.FromSeconds(60), QueueLimit = 0, AutoReplenishment = true }));
    options.AddPolicy("client-favorite", ctx => RateLimitPartition.GetFixedWindowLimiter(ctx.User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value ?? ResolveClientIp(ctx), _ => new FixedWindowRateLimiterOptions { PermitLimit = builder.Configuration.GetValue("ClientFavorites:PermitLimit", 60), Window = TimeSpan.FromSeconds(60), QueueLimit = 0, AutoReplenishment = true }));
    options.AddPolicy("notification", ctx => RateLimitPartition.GetFixedWindowLimiter(ctx.User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value ?? ResolveClientIp(ctx), _ => new FixedWindowRateLimiterOptions { PermitLimit = builder.Configuration.GetValue("Notifications:PermitLimit", 120), Window = TimeSpan.FromSeconds(60), QueueLimit = 0, AutoReplenishment = true }));
});

// --- Servisler ---
if (builder.Environment.IsDevelopment() &&
    builder.Configuration.GetValue("SmsSettings:UseConsoleSender", false))
{
    builder.Services.AddSingleton<ISmsSender, ConsoleSmsSender>();
}
else
{
    builder.Services.AddHttpClient<ISmsSender, NacSmsSender>(client =>
        client.Timeout = TimeSpan.FromSeconds(10));
}

builder.Services.AddSingleton<IOtpCodeGenerator, CryptoOtpCodeGenerator>();
builder.Services.AddSingleton<IFirebaseAppProvider, FirebaseAppProvider>();
if (builder.Environment.IsDevelopment())
    builder.Services.AddSingleton<DevOtpStore>();
builder.Services.AddSingleton<EmailLogoProvider>();
// Email: yapılandırılmışsa SMTP, yoksa console'a yazar
if (!string.IsNullOrWhiteSpace(builder.Configuration["Email:User"]))
    builder.Services.AddSingleton<IEmailSender, SmtpEmailSender>();
else
    builder.Services.AddSingleton<IEmailSender, ConsoleEmailSender>();
builder.Services.AddScoped<OtpService>();
builder.Services.AddSingleton<TwilioVerifyService>();
builder.Services.AddScoped<IFirebaseIdTokenVerifier, FirebaseAdminIdTokenVerifier>();
builder.Services.AddScoped<TokenService>();
builder.Services.AddSingleton<FileStorageService>();
builder.Services.AddScoped<RealtimeNotifier>();
builder.Services.AddScoped<NotificationOutboxProcessor>();
if (!builder.Environment.IsEnvironment("Testing") && builder.Configuration.GetValue("NotificationOutbox:Enabled", true))
    builder.Services.AddHostedService<NotificationOutboxWorker>();
builder.Services.AddPushNotifications(builder.Configuration, builder.Environment);
builder.Services.AddHttpClient<IAddressSearchProvider, GooglePlacesAddressSearchProvider>(c => { c.BaseAddress = new Uri("https://places.googleapis.com/"); c.Timeout = TimeSpan.FromSeconds(5); });

builder.Services.AddControllers().AddJsonOptions(o =>
    o.JsonSerializerOptions.Converters.Add(new System.Text.Json.Serialization.JsonStringEnumConverter()));
builder.Services.AddSignalR();

var app = builder.Build();
MaintenanceCommand maintenanceCommand;
try
{
    maintenanceCommand = MaintenanceCommand.Parse(args);
}
catch (ArgumentException ex)
{
    app.Logger.LogError("Invalid maintenance command: {Message}", ex.Message);
    Environment.ExitCode = 2;
    return;
}

if (maintenanceCommand.Kind != MaintenanceCommandKind.None)
{
    try
    {
        await MaintenanceCommandRunner.RunAsync(app, maintenanceCommand);
    }
    catch (OperationCanceledException)
    {
        app.Logger.LogError("Maintenance command was cancelled; API was not started.");
        Environment.ExitCode = 1;
    }
    catch
    {
        app.Logger.LogError("Maintenance command failed; API was not started and transaction changes were rolled back.");
        Environment.ExitCode = 1;
    }
    return;
}

// Nginx arkasında X-Forwarded-For / X-Forwarded-Proto
app.UseForwardedHeaders(new ForwardedHeadersOptions
{
    ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto
});

// Güvenlik başlıkları
app.Use(async (context, next) =>
{
    context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    context.Response.Headers["X-Frame-Options"] = "DENY";
    context.Response.Headers["Referrer-Policy"] = "no-referrer";
    await next();
});

app.UseAuthentication();
app.UseRateLimiter();
app.UseAuthorization();

app.MapGet("/health", () => Results.Ok(new
    {
        status = "ok",
        service = "Berbergelsin.Api"
    }))
    .AllowAnonymous()
    .DisableRateLimiting()
    .WithName("Health")
    .Produces(StatusCodes.Status200OK);

app.UseStaticFiles(); // email logo için
app.MapControllers();
app.MapHub<Berbergelsin.Api.Hubs.AppHub>("/hubs/app");

app.Run();

public partial class Program;
