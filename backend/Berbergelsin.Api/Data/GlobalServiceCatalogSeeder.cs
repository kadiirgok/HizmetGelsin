using System.Data;
using System.Text.Json;
using Berbergelsin.Api.Entities;
using Berbergelsin.Api.Services;
using Microsoft.EntityFrameworkCore;

namespace Berbergelsin.Api.Data;

public sealed record GlobalServiceCatalogSeedResult(
    string CatalogVersion,
    int Added,
    int Preserved,
    int TotalCanonicalServices);

public sealed class CatalogMaintenanceException : Exception
{
    public CatalogMaintenanceException(string message, Exception innerException)
        : base(message, innerException) { }
}

internal sealed class GlobalServiceCatalogArtifact
{
    public string CatalogVersion { get; init; } = string.Empty;
    public DateTimeOffset ReleasedAt { get; init; }
    public List<GlobalServiceCatalogCategory> Categories { get; init; } = [];
}

internal sealed class GlobalServiceCatalogCategory
{
    public string StableKey { get; init; } = string.Empty;
    public string DisplayName { get; init; } = string.Empty;
    public int SortOrder { get; init; }
    public bool IsActive { get; init; }
    public List<GlobalServiceCatalogService> Services { get; init; } = [];
}

internal sealed class GlobalServiceCatalogService
{
    public Guid Id { get; init; }
    public string StableKey { get; init; } = string.Empty;
    public string DisplayName { get; init; } = string.Empty;
    public int SortOrder { get; init; }
    public bool IsActive { get; init; }
}

public static class GlobalServiceCatalogSeeder
{
    internal const int ExpectedCategoryCount = 16;
    internal const int ExpectedServiceCount = 32;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public static async Task<GlobalServiceCatalogSeedResult> SeedFromFileAsync(
        AppDbContext db,
        string path,
        CancellationToken ct = default)
    {
        var catalog = await LoadFromFileAsync(path, ct);
        return await SeedCatalogAsync(db, catalog, null, ct);
    }

    public static async Task<GlobalServiceCatalogSeedResult> SeedAsync(
        AppDbContext db,
        Stream artifact,
        CancellationToken ct = default)
    {
        var catalog = await LoadAsync(artifact, ct);
        return await SeedCatalogAsync(db, catalog, null, ct);
    }

    internal static async Task<GlobalServiceCatalogSeedResult> SeedFromFileAsync(
        AppDbContext db,
        string path,
        Func<AppDbContext, CancellationToken, Task>? beforeCommit,
        CancellationToken ct = default)
    {
        var catalog = await LoadFromFileAsync(path, ct);
        return await SeedCatalogAsync(db, catalog, beforeCommit, ct);
    }

    internal static async Task<GlobalServiceCatalogArtifact> LoadFromFileAsync(
        string path,
        CancellationToken ct = default)
    {
        await using var stream = File.OpenRead(path);
        return await LoadAsync(stream, ct);
    }

    private static async Task<GlobalServiceCatalogArtifact> LoadAsync(
        Stream artifact,
        CancellationToken ct)
    {
        var catalog = await JsonSerializer.DeserializeAsync<GlobalServiceCatalogArtifact>(
            artifact, JsonOptions, ct)
            ?? throw new InvalidDataException("Catalog artifact is empty.");
        Validate(catalog);
        return catalog;
    }

    private static async Task<GlobalServiceCatalogSeedResult> SeedCatalogAsync(
        AppDbContext db,
        GlobalServiceCatalogArtifact catalog,
        Func<AppDbContext, CancellationToken, Task>? beforeCommit,
        CancellationToken ct)
    {
        await using var transaction = await db.Database.BeginTransactionAsync(
            IsolationLevel.Serializable, ct);
        try
        {
            var existing = await db.ServiceDefinitions.AsNoTracking().ToListAsync(ct);
            var ids = existing.Select(x => x.Id).ToHashSet();
            var naturalKeys = existing
                .Select(x => NaturalKey(x.NormalizedCategoryName, x.NormalizedName))
                .ToHashSet(StringComparer.Ordinal);
            var createdAt = catalog.ReleasedAt.UtcDateTime;
            var added = 0;
            var preserved = 0;

            foreach (var category in catalog.Categories.OrderBy(x => x.SortOrder))
            {
                var normalizedCategory = ServiceCatalogLinker.NormalizeName(category.DisplayName);
                foreach (var service in category.Services.OrderBy(x => x.SortOrder))
                {
                    var normalizedName = ServiceCatalogLinker.NormalizeName(service.DisplayName);
                    var naturalKey = NaturalKey(normalizedCategory, normalizedName);
                    if (ids.Contains(service.Id) || naturalKeys.Contains(naturalKey))
                    {
                        preserved++;
                        continue;
                    }

                    db.ServiceDefinitions.Add(new ServiceDefinition
                    {
                        Id = service.Id,
                        Name = service.DisplayName,
                        NormalizedName = normalizedName,
                        CategoryName = category.DisplayName,
                        NormalizedCategoryName = normalizedCategory,
                        SortOrder = service.SortOrder,
                        IsActive = category.IsActive && service.IsActive,
                        CreatedAt = createdAt
                    });
                    ids.Add(service.Id);
                    naturalKeys.Add(naturalKey);
                    added++;
                }
            }

            if (added > 0)
                await db.SaveChangesAsync(ct);
            if (beforeCommit != null)
                await beforeCommit(db, ct);

            await transaction.CommitAsync(ct);
            return new GlobalServiceCatalogSeedResult(
                catalog.CatalogVersion,
                added,
                preserved,
                catalog.Categories.Sum(x => x.Services.Count));
        }
        catch (OperationCanceledException)
        {
            await RollbackAsync(transaction);
            db.ChangeTracker.Clear();
            throw;
        }
        catch (Exception ex)
        {
            await RollbackAsync(transaction);
            db.ChangeTracker.Clear();
            throw new CatalogMaintenanceException(
                "Global service catalog seed failed; all changes were rolled back.", ex);
        }
    }

    internal static string NaturalKey(string normalizedCategory, string normalizedName)
        => $"{normalizedCategory}\u001f{normalizedName}";

    private static async Task RollbackAsync(Microsoft.EntityFrameworkCore.Storage.IDbContextTransaction transaction)
    {
        try
        {
            await transaction.RollbackAsync(CancellationToken.None);
        }
        catch
        {
            // Preserve the original maintenance failure; disposal will close the transaction.
        }
    }

    private static void Validate(GlobalServiceCatalogArtifact catalog)
    {
        if (string.IsNullOrWhiteSpace(catalog.CatalogVersion))
            throw new InvalidDataException("catalogVersion is required.");
        if (catalog.ReleasedAt == default)
            throw new InvalidDataException("releasedAt is required.");
        if (catalog.Categories.Count == 0)
            throw new InvalidDataException("At least one category is required.");

        var categoryKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var serviceKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var serviceIds = new HashSet<Guid>();
        var naturalKeys = new HashSet<string>(StringComparer.Ordinal);
        foreach (var category in catalog.Categories)
        {
            if (string.IsNullOrWhiteSpace(category.StableKey) || !categoryKeys.Add(category.StableKey))
                throw new InvalidDataException($"Duplicate or empty category stable key: {category.StableKey}");
            if (string.IsNullOrWhiteSpace(category.DisplayName))
                throw new InvalidDataException($"Category {category.StableKey} has no display name.");

            var normalizedCategory = ServiceCatalogLinker.NormalizeName(category.DisplayName);
            foreach (var service in category.Services)
            {
                if (service.Id == Guid.Empty || !serviceIds.Add(service.Id))
                    throw new InvalidDataException($"Duplicate or empty service id: {service.Id}");
                if (string.IsNullOrWhiteSpace(service.StableKey) || !serviceKeys.Add(service.StableKey))
                    throw new InvalidDataException($"Duplicate or empty service stable key: {service.StableKey}");
                if (string.IsNullOrWhiteSpace(service.DisplayName))
                    throw new InvalidDataException($"Service {service.StableKey} has no display name.");
                var naturalKey = NaturalKey(
                    normalizedCategory, ServiceCatalogLinker.NormalizeName(service.DisplayName));
                if (!naturalKeys.Add(naturalKey))
                    throw new InvalidDataException("Duplicate normalized catalog service key.");
            }
        }

        var serviceCount = catalog.Categories.Sum(x => x.Services.Count);
        if (catalog.Categories.Count != ExpectedCategoryCount || serviceCount != ExpectedServiceCount)
            throw new InvalidDataException(
                $"Canonical catalog must contain exactly {ExpectedCategoryCount} categories and {ExpectedServiceCount} services.");
    }
}
