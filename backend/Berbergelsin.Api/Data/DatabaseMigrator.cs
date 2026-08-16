using Microsoft.EntityFrameworkCore;

namespace Berbergelsin.Api.Data;

public static class DatabaseMigrator
{
    public static async Task MigrateAsync(IServiceProvider services, CancellationToken ct = default)
    {
        await using var scope = services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await db.Database.MigrateAsync(ct);
    }
}
