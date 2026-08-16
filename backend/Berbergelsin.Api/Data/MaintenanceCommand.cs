namespace Berbergelsin.Api.Data;

public enum MaintenanceCommandKind
{
    None,
    Migrate,
    SeedGlobalServiceCatalog,
    LinkBarberServicesCatalog
}

public sealed record MaintenanceCommand(MaintenanceCommandKind Kind, bool Apply)
{
    public static MaintenanceCommand Parse(IEnumerable<string> args)
    {
        var values = args.ToArray();
        var commands = new[]
        {
            (Argument: "--migrate", Kind: MaintenanceCommandKind.Migrate),
            (Argument: "--seed-global-service-catalog", Kind: MaintenanceCommandKind.SeedGlobalServiceCatalog),
            (Argument: "--link-barber-services-catalog", Kind: MaintenanceCommandKind.LinkBarberServicesCatalog)
        };
        var selected = commands
            .Where(command => values.Contains(command.Argument, StringComparer.OrdinalIgnoreCase))
            .ToArray();
        if (selected.Length > 1)
            throw new ArgumentException("Only one maintenance command can be run at a time.");

        var apply = values.Contains("--apply", StringComparer.OrdinalIgnoreCase);
        var kind = selected.Length == 0 ? MaintenanceCommandKind.None : selected[0].Kind;
        if (apply && kind != MaintenanceCommandKind.LinkBarberServicesCatalog)
            throw new ArgumentException("--apply is only valid with --link-barber-services-catalog.");

        return new MaintenanceCommand(kind, apply);
    }
}

public static class MaintenanceCommandRunner
{
    public static async Task RunAsync(
        WebApplication app,
        MaintenanceCommand command,
        CancellationToken ct = default)
    {
        var artifactPath = Path.Combine(
            app.Environment.ContentRootPath, "Data", "Seed", "global-service-catalog.v1.json");
        await DispatchAsync(
            command,
            async () =>
            {
                await DatabaseMigrator.MigrateAsync(app.Services, ct);
                app.Logger.LogInformation("Database migration maintenance command completed.");
            },
            async () =>
            {
                await using var scope = app.Services.CreateAsyncScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                var result = await GlobalServiceCatalogSeeder.SeedFromFileAsync(db, artifactPath, ct);
                app.Logger.LogInformation(
                    "Global service catalog maintenance completed. Version: {CatalogVersion}; added: {Added}; preserved: {Preserved}; total: {Total}.",
                    result.CatalogVersion, result.Added, result.Preserved, result.TotalCanonicalServices);
            },
            async apply =>
            {
                await using var scope = app.Services.CreateAsyncScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                var result = await BarberServiceCatalogBackfill.RunFromFileAsync(
                    db, artifactPath, apply, ct);
                app.Logger.LogInformation(
                    "Barber service catalog link maintenance completed. Mode: {Mode}; eligible: {Eligible}; matched: {Matched}; linked: {Linked}; ambiguous: {Ambiguous}; unmatched: {Unmatched}; hash: {Hash}.",
                    apply ? "apply" : "dry-run",
                    result.Eligible, result.Matched, result.Linked,
                    result.Ambiguous, result.Unmatched, result.PlanHash);
            });
    }

    internal static async Task DispatchAsync(
        MaintenanceCommand command,
        Func<Task> migrate,
        Func<Task> seedGlobalServiceCatalog,
        Func<bool, Task> linkBarberServicesCatalog)
    {
        switch (command.Kind)
        {
            case MaintenanceCommandKind.Migrate:
                await migrate();
                return;
            case MaintenanceCommandKind.SeedGlobalServiceCatalog:
                await seedGlobalServiceCatalog();
                return;
            case MaintenanceCommandKind.LinkBarberServicesCatalog:
                await linkBarberServicesCatalog(command.Apply);
                return;
            case MaintenanceCommandKind.None:
                return;
            default:
                throw new ArgumentOutOfRangeException(nameof(command));
        }
    }
}
