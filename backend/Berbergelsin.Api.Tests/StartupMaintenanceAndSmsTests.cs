using System.Net;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Services;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;
using Xunit;

namespace Berbergelsin.Api.Tests;

public sealed class StartupMaintenanceAndSmsTests
{
    [Fact]
    public async Task Production_normal_startup_does_not_run_migration()
    {
        using var factory = new ProductionStartupFactory();
        using var response = await factory.CreateClient().GetAsync("/health");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Production_normal_startup_does_not_create_or_promote_admin()
    {
        using var factory = new ProductionStartupFactory();
        using var response = await factory.CreateClient().GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        Assert.Empty(await db.Users.AsNoTracking().ToListAsync());
    }

    [Fact]
    public void Production_never_registers_console_sms_sender()
    {
        using var factory = new ProductionStartupFactory();
        using var client = factory.CreateClient();
        using var scope = factory.Services.CreateScope();

        Assert.IsType<NacSmsSender>(scope.ServiceProvider.GetRequiredService<ISmsSender>());
    }

    [Fact]
    public async Task Explicit_migrate_and_catalog_seed_dispatch_only_the_requested_operation()
    {
        var migrated = 0;
        var seeded = 0;
        var linked = 0;
        Task Migrate() { migrated++; return Task.CompletedTask; }
        Task Seed() { seeded++; return Task.CompletedTask; }
        Task Link(bool _) { linked++; return Task.CompletedTask; }

        await MaintenanceCommandRunner.DispatchAsync(
            MaintenanceCommand.Parse(["--migrate"]), Migrate, Seed, Link);
        Assert.Equal((1, 0, 0), (migrated, seeded, linked));

        await MaintenanceCommandRunner.DispatchAsync(
            MaintenanceCommand.Parse(["--seed-global-service-catalog"]), Migrate, Seed, Link);
        Assert.Equal((1, 1, 0), (migrated, seeded, linked));
    }

    [Fact]
    public async Task Backfill_is_dry_run_by_default_and_requires_apply_flag_for_changes()
    {
        bool? apply = null;
        Task Noop() => Task.CompletedTask;
        Task Link(bool value) { apply = value; return Task.CompletedTask; }

        await MaintenanceCommandRunner.DispatchAsync(
            MaintenanceCommand.Parse(["--link-barber-services-catalog"]), Noop, Noop, Link);
        Assert.False(apply);

        await MaintenanceCommandRunner.DispatchAsync(
            MaintenanceCommand.Parse(["--link-barber-services-catalog", "--apply"]), Noop, Noop, Link);
        Assert.True(apply);
        Assert.Throws<ArgumentException>(() => MaintenanceCommand.Parse(["--apply"]));
    }

    [Fact]
    public async Task Sms_failure_logs_exclude_destination_otp_and_provider_body()
    {
        const string destinationMarker = "synthetic-destination";
        const string otpMarker = "otp-marker-1234";
        const string providerMarker = "provider-body-marker";
        await using var db = SqliteDb();
        var otpLogger = new BufferLogger<OtpService>();
        var config = new ConfigurationBuilder().AddInMemoryCollection(
            new Dictionary<string, string?>
            {
                ["Otp:Pepper"] = "synthetic-test-pepper",
                ["Otp:ResendSeconds"] = "0"
            }).Build();
        var otp = new OtpService(
            db,
            new ThrowingSmsSender($"{destinationMarker} {otpMarker} {providerMarker}"),
            new CryptoOtpCodeGenerator(),
            config,
            otpLogger);

        Assert.Equal(OtpService.SendResult.SmsFailed,
            await otp.SendOtpAsync(destinationMarker, null));
        AssertSafe(otpLogger.Messages, destinationMarker, otpMarker, providerMarker);

        var providerLogger = new BufferLogger<NacSmsSender>();
        var providerConfig = new ConfigurationBuilder().AddInMemoryCollection(
            new Dictionary<string, string?>
            {
                ["SmsSettings:BaseUrl"] = "https://sms.invalid",
                ["SmsSettings:AuthHeader"] = "synthetic-auth",
                ["SmsSettings:Origin"] = "synthetic-origin"
            }).Build();
        var handler = new StaticResponseHandler(new HttpResponseMessage(HttpStatusCode.BadRequest)
        {
            Content = new StringContent(providerMarker)
        });
        var sender = new NacSmsSender(new HttpClient(handler), providerConfig, providerLogger);

        await Assert.ThrowsAsync<SmsSendException>(() =>
            sender.SendAsync(destinationMarker, otpMarker));
        AssertSafe(providerLogger.Messages, destinationMarker, otpMarker, providerMarker);
    }

    private static void AssertSafe(IEnumerable<string> messages, params string[] forbidden)
    {
        var combined = string.Join('\n', messages);
        foreach (var marker in forbidden)
            Assert.DoesNotContain(marker, combined, StringComparison.OrdinalIgnoreCase);
    }

    private static AppDbContext SqliteDb()
    {
        var db = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlite("Data Source=:memory:", options => options.UseNetTopologySuite()).Options);
        db.Database.OpenConnection();
        db.Database.EnsureCreated();
        return db;
    }

    private sealed class ProductionStartupFactory : WebApplicationFactory<Program>
    {
        private readonly string database = $"production-startup-{Guid.NewGuid()}";

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment("Production");
            builder.UseSetting("Jwt:Key", "production-startup-test-key-at-least-32-chars");
            builder.UseSetting("Jwt:Issuer", "production-startup-tests");
            builder.UseSetting("Jwt:Audience", "production-startup-tests");
            builder.UseSetting("Seed:AdminPhone", "synthetic-admin-bootstrap-value");
            builder.UseSetting("SmsSettings:UseConsoleSender", "true");
            builder.ConfigureServices(services =>
            {
                services.RemoveAll<DbContextOptions<AppDbContext>>();
                services.AddDbContext<AppDbContext>(options =>
                    options.UseInMemoryDatabase(database));
            });
        }
    }

    private sealed class ThrowingSmsSender(string message) : ISmsSender
    {
        public Task SendAsync(string phone, string content, CancellationToken ct = default)
            => throw new InvalidOperationException(message);
    }

    private sealed class StaticResponseHandler(HttpResponseMessage response) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
            => Task.FromResult(response);
    }

    private sealed class BufferLogger<T> : ILogger<T>
    {
        public List<string> Messages { get; } = [];
        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
        public bool IsEnabled(LogLevel logLevel) => true;
        public void Log<TState>(
            LogLevel logLevel,
            EventId eventId,
            TState state,
            Exception? exception,
            Func<TState, Exception?, string> formatter)
            => Messages.Add(formatter(state, exception));
    }
}
