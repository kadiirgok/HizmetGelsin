using Berbergelsin.Api.Data;
using Berbergelsin.Api.Entities;
using Berbergelsin.Api.Enums;
using Berbergelsin.Api.Services;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace Berbergelsin.Api.Tests;

public sealed class BarberServiceCatalogBackfillTests
{
    private static string ArtifactPath => Path.Combine(
        AppContext.BaseDirectory, "Data", "Seed", "global-service-catalog.v1.json");

    [Fact]
    public async Task Dry_run_changes_nothing_and_apply_links_only_exact_unique_null_match()
    {
        await using var db = Db();
        var fixture = await SeedFixtureAsync(db);

        var dryRun = await BarberServiceCatalogBackfill.RunFromFileAsync(db, ArtifactPath);

        Assert.Equal(2, dryRun.Eligible);
        Assert.Equal(1, dryRun.Matched);
        Assert.Equal(0, dryRun.Linked);
        Assert.Equal(0, dryRun.Ambiguous);
        Assert.Equal(1, dryRun.Unmatched);
        Assert.Equal(64, dryRun.PlanHash.Length);
        Assert.Null((await db.BarberServices.FindAsync(fixture.MatchId))!.ServiceDefinitionId);
        Assert.Null((await db.BarberServices.FindAsync(fixture.UnmatchedId))!.ServiceDefinitionId);
        Assert.Equal(fixture.ProtectedDefinitionId,
            (await db.BarberServices.FindAsync(fixture.ProtectedId))!.ServiceDefinitionId);

        var applied = await BarberServiceCatalogBackfill.RunFromFileAsync(
            db, ArtifactPath, apply: true);

        Assert.Equal(1, applied.Linked);
        Assert.Equal(fixture.MatchDefinitionId,
            (await db.BarberServices.AsNoTracking().SingleAsync(x => x.Id == fixture.MatchId)).ServiceDefinitionId);
        Assert.Null((await db.BarberServices.AsNoTracking()
            .SingleAsync(x => x.Id == fixture.UnmatchedId)).ServiceDefinitionId);
        Assert.Equal(fixture.ProtectedDefinitionId,
            (await db.BarberServices.AsNoTracking()
                .SingleAsync(x => x.Id == fixture.ProtectedId)).ServiceDefinitionId);

        var snapshot = await db.BarberServices.AsNoTracking()
            .OrderBy(x => x.Id)
            .Select(x => new { x.Id, x.ServiceDefinitionId })
            .ToListAsync();
        var second = await BarberServiceCatalogBackfill.RunFromFileAsync(
            db, ArtifactPath, apply: true);
        var secondSnapshot = await db.BarberServices.AsNoTracking()
            .OrderBy(x => x.Id)
            .Select(x => new { x.Id, x.ServiceDefinitionId })
            .ToListAsync();

        Assert.Equal(0, second.Matched);
        Assert.Equal(0, second.Linked);
        Assert.Equal(snapshot, secondSnapshot);
    }

    [Fact]
    public void Ambiguous_canonical_match_is_not_planned()
    {
        var category = ServiceCatalogLinker.NormalizeName("Kuaför & Güzellik");
        var name = ServiceCatalogLinker.NormalizeName("Saç Kesimi");
        var key = GlobalServiceCatalogSeeder.NaturalKey(category, name);
        var candidate = new BarberServiceCatalogCandidate(
            Guid.NewGuid(), " saç kesimi ", " kuaför & güzellik ");
        var definitions = new[]
        {
            new BarberServiceCatalogDefinition(Guid.NewGuid(), name, category),
            new BarberServiceCatalogDefinition(Guid.NewGuid(), name, category)
        };

        var plan = BarberServiceCatalogBackfill.Plan(
            [candidate], definitions, new HashSet<string>(StringComparer.Ordinal) { key });

        Assert.Empty(plan.Links);
        Assert.Equal(1, plan.Ambiguous);
        Assert.Equal(0, plan.Unmatched);
    }

    [Fact]
    public async Task Failure_before_commit_rolls_back_all_links()
    {
        await using var db = Db();
        var fixture = await SeedFixtureAsync(db);

        await Assert.ThrowsAsync<BarberServiceCatalogBackfillException>(() =>
            BarberServiceCatalogBackfill.RunFromFileAsync(
                db,
                ArtifactPath,
                apply: true,
                (_, _) => throw new InvalidOperationException("synthetic failure")));

        Assert.Null((await db.BarberServices.AsNoTracking()
            .SingleAsync(x => x.Id == fixture.MatchId)).ServiceDefinitionId);
    }

    private static async Task<BackfillFixture> SeedFixtureAsync(AppDbContext db)
    {
        await GlobalServiceCatalogSeeder.SeedFromFileAsync(db, ArtifactPath);
        var matchDefinition = await db.ServiceDefinitions.SingleAsync(x =>
            x.NormalizedCategoryName == ServiceCatalogLinker.NormalizeName("Kuaför & Güzellik") &&
            x.NormalizedName == ServiceCatalogLinker.NormalizeName("Saç Kesimi"));
        var protectedDefinition = await db.ServiceDefinitions.SingleAsync(x =>
            x.NormalizedCategoryName == ServiceCatalogLinker.NormalizeName("Kuaför & Güzellik") &&
            x.NormalizedName == ServiceCatalogLinker.NormalizeName("Sakal Bakımı"));
        var user = new User
        {
            Id = Guid.NewGuid(),
            PhoneNumber = "synthetic-user",
            Role = UserRole.Berber,
            CreatedAt = DateTime.UtcNow
        };
        var profile = new BarberProfile
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            User = user,
            Category = " kuaför & güzellik ",
            CreatedAt = DateTime.UtcNow
        };
        var match = Service(profile, " saç kesimi ");
        var unmatched = Service(profile, "canonical olmayan hizmet");
        var protectedService = Service(profile, "Saç Kesimi");
        protectedService.ServiceDefinitionId = protectedDefinition.Id;
        db.AddRange(user, profile, match, unmatched, protectedService);
        await db.SaveChangesAsync();
        return new BackfillFixture(
            match.Id, unmatched.Id, protectedService.Id,
            matchDefinition.Id, protectedDefinition.Id);
    }

    private static BarberService Service(BarberProfile profile, string name) => new()
    {
        Id = Guid.NewGuid(),
        BarberProfileId = profile.Id,
        BarberProfile = profile,
        Name = name,
        Price = 1
    };

    private static AppDbContext Db()
    {
        var db = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlite("Data Source=:memory:", options => options.UseNetTopologySuite()).Options);
        db.Database.OpenConnection();
        db.Database.EnsureCreated();
        return db;
    }

    private sealed record BackfillFixture(
        Guid MatchId,
        Guid UnmatchedId,
        Guid ProtectedId,
        Guid MatchDefinitionId,
        Guid ProtectedDefinitionId);
}
