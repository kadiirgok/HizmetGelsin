using System.Data;
using System.Security.Cryptography;
using System.Text;
using Berbergelsin.Api.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace Berbergelsin.Api.Data;

public sealed record BarberServiceCatalogBackfillResult(
    int Eligible,
    int Matched,
    int Linked,
    int Ambiguous,
    int Unmatched,
    string PlanHash);

public sealed class BarberServiceCatalogBackfillException : Exception
{
    public BarberServiceCatalogBackfillException(string message, Exception innerException)
        : base(message, innerException) { }
}

internal sealed record BarberServiceCatalogCandidate(Guid Id, string Name, string? Category);
internal sealed record BarberServiceCatalogDefinition(
    Guid Id, string NormalizedName, string NormalizedCategoryName);
internal sealed record BarberServiceCatalogLink(Guid BarberServiceId, Guid ServiceDefinitionId);
internal sealed record BarberServiceCatalogPlan(
    IReadOnlyList<BarberServiceCatalogLink> Links, int Ambiguous, int Unmatched);

public static class BarberServiceCatalogBackfill
{
    public static async Task<BarberServiceCatalogBackfillResult> RunFromFileAsync(
        AppDbContext db,
        string artifactPath,
        bool apply = false,
        CancellationToken ct = default)
    {
        var artifact = await GlobalServiceCatalogSeeder.LoadFromFileAsync(artifactPath, ct);
        return await RunAsync(db, artifact, apply, null, ct);
    }

    internal static async Task<BarberServiceCatalogBackfillResult> RunFromFileAsync(
        AppDbContext db,
        string artifactPath,
        bool apply,
        Func<AppDbContext, CancellationToken, Task>? beforeCommit,
        CancellationToken ct = default)
    {
        var artifact = await GlobalServiceCatalogSeeder.LoadFromFileAsync(artifactPath, ct);
        return await RunAsync(db, artifact, apply, beforeCommit, ct);
    }

    private static async Task<BarberServiceCatalogBackfillResult> RunAsync(
        AppDbContext db,
        GlobalServiceCatalogArtifact artifact,
        bool apply,
        Func<AppDbContext, CancellationToken, Task>? beforeCommit,
        CancellationToken ct)
    {
        await using var transaction = await db.Database.BeginTransactionAsync(
            IsolationLevel.Serializable, ct);
        try
        {
            var rows = await db.BarberServices.AsNoTracking()
                .Where(x => x.ServiceDefinitionId == null)
                .Select(x => new { x.Id, x.Name, x.BarberProfile.Category })
                .ToListAsync(ct);
            var candidates = rows
                .Select(x => new BarberServiceCatalogCandidate(x.Id, x.Name, x.Category))
                .ToList();
            var definitions = await db.ServiceDefinitions.AsNoTracking()
                .Select(x => new BarberServiceCatalogDefinition(
                    x.Id, x.NormalizedName, x.NormalizedCategoryName))
                .ToListAsync(ct);
            var canonicalKeys = artifact.Categories
                .SelectMany(category => category.Services.Select(service =>
                    GlobalServiceCatalogSeeder.NaturalKey(
                        ServiceCatalogLinker.NormalizeName(category.DisplayName),
                        ServiceCatalogLinker.NormalizeName(service.DisplayName))))
                .ToHashSet(StringComparer.Ordinal);
            var plan = Plan(candidates, definitions, canonicalKeys);
            var linked = 0;

            if (apply)
            {
                foreach (var group in plan.Links.GroupBy(x => x.ServiceDefinitionId))
                {
                    var serviceIds = group.Select(x => x.BarberServiceId).ToArray();
                    linked += await db.BarberServices
                        .Where(x => serviceIds.Contains(x.Id) && x.ServiceDefinitionId == null)
                        .ExecuteUpdateAsync(setters => setters.SetProperty(
                            x => x.ServiceDefinitionId, group.Key), ct);
                }
            }

            if (beforeCommit != null)
                await beforeCommit(db, ct);
            await transaction.CommitAsync(ct);

            return new BarberServiceCatalogBackfillResult(
                candidates.Count,
                plan.Links.Count,
                linked,
                plan.Ambiguous,
                plan.Unmatched,
                Hash(plan.Links));
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
            throw new BarberServiceCatalogBackfillException(
                "Barber service catalog link failed; all changes were rolled back.", ex);
        }
    }

    internal static BarberServiceCatalogPlan Plan(
        IEnumerable<BarberServiceCatalogCandidate> candidates,
        IEnumerable<BarberServiceCatalogDefinition> definitions,
        IReadOnlySet<string> canonicalKeys)
    {
        var definitionsByKey = definitions
            .Where(x => canonicalKeys.Contains(GlobalServiceCatalogSeeder.NaturalKey(
                x.NormalizedCategoryName, x.NormalizedName)))
            .GroupBy(x => GlobalServiceCatalogSeeder.NaturalKey(
                x.NormalizedCategoryName, x.NormalizedName), StringComparer.Ordinal)
            .ToDictionary(x => x.Key, x => x.ToArray(), StringComparer.Ordinal);
        var links = new List<BarberServiceCatalogLink>();
        var ambiguous = 0;
        var unmatched = 0;

        foreach (var candidate in candidates)
        {
            if (string.IsNullOrWhiteSpace(candidate.Name) ||
                string.IsNullOrWhiteSpace(candidate.Category))
            {
                unmatched++;
                continue;
            }

            var key = GlobalServiceCatalogSeeder.NaturalKey(
                ServiceCatalogLinker.NormalizeName(candidate.Category),
                ServiceCatalogLinker.NormalizeName(candidate.Name));
            if (!canonicalKeys.Contains(key) || !definitionsByKey.TryGetValue(key, out var matches))
            {
                unmatched++;
                continue;
            }
            if (matches.Length != 1)
            {
                ambiguous++;
                continue;
            }

            links.Add(new BarberServiceCatalogLink(candidate.Id, matches[0].Id));
        }

        return new BarberServiceCatalogPlan(links, ambiguous, unmatched);
    }

    private static string Hash(IEnumerable<BarberServiceCatalogLink> links)
    {
        var anonymousPlan = string.Join('\n', links
            .OrderBy(x => x.BarberServiceId)
            .ThenBy(x => x.ServiceDefinitionId)
            .Select(x => $"{x.BarberServiceId:N}:{x.ServiceDefinitionId:N}"));
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(anonymousPlan)));
    }

    private static async Task RollbackAsync(IDbContextTransaction transaction)
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
}
