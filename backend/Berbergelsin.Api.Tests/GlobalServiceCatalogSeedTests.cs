using System.Text;
using Berbergelsin.Api.Controllers;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Dtos;
using Berbergelsin.Api.Entities;
using Berbergelsin.Api.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace Berbergelsin.Api.Tests;

public sealed class GlobalServiceCatalogSeedTests
{
    private static string ArtifactPath => Path.Combine(
        AppContext.BaseDirectory, "Data", "Seed", "global-service-catalog.v1.json");

    [Fact]
    public async Task Empty_database_seed_and_second_run_are_deterministic_and_idempotent()
    {
        await using var db = Db();
        var first = await GlobalServiceCatalogSeeder.SeedFromFileAsync(db, ArtifactPath);
        var firstSnapshot = await db.ServiceDefinitions.AsNoTracking()
            .OrderBy(x => x.Id).Select(x => new { x.Id, x.Name, x.CategoryName, x.SortOrder, x.IsActive }).ToListAsync();
        var second = await GlobalServiceCatalogSeeder.SeedFromFileAsync(db, ArtifactPath);
        var secondSnapshot = await db.ServiceDefinitions.AsNoTracking()
            .OrderBy(x => x.Id).Select(x => new { x.Id, x.Name, x.CategoryName, x.SortOrder, x.IsActive }).ToListAsync();

        Assert.Equal("1.0.0", first.CatalogVersion);
        Assert.Equal(first.TotalCanonicalServices, first.Added);
        Assert.Equal(0, second.Added);
        Assert.Equal(first.TotalCanonicalServices, second.Preserved);
        Assert.Equal(firstSnapshot, secondSnapshot);
    }

    [Fact]
    public async Task Canonical_artifact_contains_exactly_16_categories_and_32_services()
    {
        await using var db = Db();

        var result = await GlobalServiceCatalogSeeder.SeedFromFileAsync(db, ArtifactPath);

        Assert.Equal(16, await db.ServiceDefinitions.Select(x => x.CategoryName).Distinct().CountAsync());
        Assert.Equal(32, result.TotalCanonicalServices);
    }

    [Fact]
    public async Task Existing_canonical_natural_key_is_preserved_without_duplicate()
    {
        await using var db = Db();
        var existing = Def(Guid.NewGuid(), "Saç Kesimi", "Kuaför & Güzellik", active: true);
        db.Add(existing);
        await db.SaveChangesAsync();

        await GlobalServiceCatalogSeeder.SeedFromFileAsync(db, ArtifactPath);

        Assert.Single(await db.ServiceDefinitions.Where(x =>
            x.NormalizedCategoryName == existing.NormalizedCategoryName &&
            x.NormalizedName == existing.NormalizedName).ToListAsync());
        Assert.Equal(existing.Id, (await db.ServiceDefinitions.SingleAsync(x => x.NormalizedName == existing.NormalizedName)).Id);
    }

    [Fact]
    public async Task Missing_single_service_is_inserted_without_touching_others()
    {
        await using var db = Db();
        var initial = await GlobalServiceCatalogSeeder.SeedFromFileAsync(db, ArtifactPath);
        var missing = await db.ServiceDefinitions.OrderBy(x => x.Id).FirstAsync();
        db.Remove(missing);
        await db.SaveChangesAsync();

        var result = await GlobalServiceCatalogSeeder.SeedFromFileAsync(db, ArtifactPath);

        Assert.Equal(1, result.Added);
        Assert.Equal(initial.TotalCanonicalServices, await db.ServiceDefinitions.CountAsync());
        Assert.NotNull(await db.ServiceDefinitions.FindAsync(missing.Id));
    }

    [Fact]
    public async Task Customized_name_and_inactive_state_with_canonical_ids_are_not_overwritten()
    {
        await using var db = Db();
        var customized = Def(Guid.Parse("132a0007-0001-4000-8000-000000000001"), "Özel Saç Kesimi", "Kuaför & Güzellik", active: true);
        var inactive = Def(Guid.Parse("132a0007-0002-4000-8000-000000000002"), "Sakal Bakımı", "Kuaför & Güzellik", active: false);
        db.AddRange(customized, inactive);
        await db.SaveChangesAsync();

        await GlobalServiceCatalogSeeder.SeedFromFileAsync(db, ArtifactPath);

        Assert.Equal("Özel Saç Kesimi", (await db.ServiceDefinitions.FindAsync(customized.Id))!.Name);
        Assert.False((await db.ServiceDefinitions.FindAsync(inactive.Id))!.IsActive);
    }

    [Fact]
    public async Task Duplicate_stable_key_is_rejected_before_database_change()
    {
        const string invalid = """
            {
              "catalogVersion":"test", "releasedAt":"2026-07-20T00:00:00Z",
              "categories":[{
                "stableKey":"one", "displayName":"One", "sortOrder":1, "isActive":true,
                "services":[
                  {"id":"132a9999-0001-4000-8000-000000000001","stableKey":"duplicate","displayName":"A","sortOrder":1,"isActive":true},
                  {"id":"132a9999-0002-4000-8000-000000000002","stableKey":"duplicate","displayName":"B","sortOrder":2,"isActive":true}
                ]
              }]
            }
            """;
        await using var db = Db();
        await using var stream = new MemoryStream(Encoding.UTF8.GetBytes(invalid));

        await Assert.ThrowsAsync<InvalidDataException>(() => GlobalServiceCatalogSeeder.SeedAsync(db, stream));
        Assert.Empty(db.ServiceDefinitions);
    }

    [Fact]
    public async Task Seeded_catalog_is_available_through_backend_endpoint()
    {
        await using var db = Db();
        var seed = await GlobalServiceCatalogSeeder.SeedFromFileAsync(db, ArtifactPath);

        var response = Assert.IsType<OkObjectResult>(
            await new ServicesController(db).Catalog(null, null, null, null, default));
        var items = Assert.IsAssignableFrom<IEnumerable<ServiceCatalogItemDto>>(response.Value).ToList();

        Assert.Equal(seed.TotalCanonicalServices, items.Count);
        Assert.All(items, item => Assert.True(item.IsActive));
    }

    [Fact]
    public async Task Failure_before_commit_rolls_back_all_catalog_inserts()
    {
        await using var db = Db();

        await Assert.ThrowsAsync<CatalogMaintenanceException>(() =>
            GlobalServiceCatalogSeeder.SeedFromFileAsync(
                db,
                ArtifactPath,
                (_, _) => throw new InvalidOperationException("synthetic failure")));

        Assert.Empty(await db.ServiceDefinitions.AsNoTracking().ToListAsync());
    }

    private static ServiceDefinition Def(Guid id, string name, string category, bool active) => new()
    {
        Id = id,
        Name = name,
        NormalizedName = ServiceCatalogLinker.NormalizeName(name),
        CategoryName = category,
        NormalizedCategoryName = ServiceCatalogLinker.NormalizeName(category),
        SortOrder = 999,
        IsActive = active,
        CreatedAt = DateTime.UtcNow
    };

    private static AppDbContext Db()
    {
        var db = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlite("Data Source=:memory:", options => options.UseNetTopologySuite()).Options);
        db.Database.OpenConnection();
        db.Database.EnsureCreated();
        return db;
    }
}
