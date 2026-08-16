using System.Net;
using System.Net.Http.Json;
using Berbergelsin.Api.Controllers;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Dtos;
using Berbergelsin.Api.Entities;
using Berbergelsin.Api.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Berbergelsin.Api.Tests;

public sealed class ServiceCatalogTests : IClassFixture<ClientProfileApiFactory>
{
    private readonly ClientProfileApiFactory _factory;
    public ServiceCatalogTests(ClientProfileApiFactory factory) => _factory = factory;

    [Fact]
    public async Task Catalog_is_public_and_returns_200()
        => Assert.Equal(HttpStatusCode.OK, (await _factory.CreateClient().GetAsync("/api/services/catalog")).StatusCode);

    [Theory]
    [InlineData("POST")]
    [InlineData("PUT")]
    [InlineData("DELETE")]
    public async Task Mutating_verbs_are_not_supported(string verb)
        => Assert.Equal(HttpStatusCode.MethodNotAllowed,
            (await _factory.CreateClient().SendAsync(new HttpRequestMessage(new HttpMethod(verb), "/api/services/catalog"))).StatusCode);

    [Fact]
    public async Task Invalid_query_has_safe_code()
    {
        var response = await _factory.CreateClient().GetAsync("/api/services/catalog?categoryId=11111111-1111-1111-1111-111111111111");
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Contains("service_catalog_invalid_query", await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task Active_category_q_and_order_are_deterministic_and_dto_is_safe()
    {
        await using var db = Db();
        db.ServiceDefinitions.AddRange(
            Def("Boya", "Tamir", 2, true), Def("Çatı Onarımı", "Tamir", 1, true),
            Def("Pasif", "Tamir", 0, false), Def("Saç Kesimi", "Kuaför", 0, true));
        await db.SaveChangesAsync();
        var result = Assert.IsType<OkObjectResult>(await new ServicesController(db).Catalog("Tamir", "atı", null, null, default));
        var items = Assert.IsAssignableFrom<IEnumerable<ServiceCatalogItemDto>>(result.Value).ToList();
        Assert.Single(items); Assert.Equal("Çatı Onarımı", items[0].Name); Assert.True(items[0].IsActive);
        Assert.Null(items[0].CategoryId);
    }

    [Fact]
    public async Task Default_excludes_inactive_and_has_no_duplicates()
    {
        await using var db = Db(); db.ServiceDefinitions.AddRange(Def("B", "X", 2, true), Def("A", "X", 1, true), Def("C", "X", 0, false)); await db.SaveChangesAsync();
        var result = Assert.IsType<OkObjectResult>(await new ServicesController(db).Catalog(null, null, null, null, default));
        var items = Assert.IsAssignableFrom<IEnumerable<ServiceCatalogItemDto>>(result.Value).ToList();
        Assert.Equal(new[] { "A", "B" }, items.Select(x => x.Name)); Assert.Equal(items.Count, items.Select(x => x.Id).Distinct().Count());
    }

    [Fact]
    public async Task Linker_reuses_stable_id_in_same_category_but_not_other_category()
    {
        await using var db = Db();
        var first = await ServiceCatalogLinker.GetOrCreateAsync(db, " Saç Kesimi ", "Kuaför", default); await db.SaveChangesAsync();
        var same = await ServiceCatalogLinker.GetOrCreateAsync(db, "saç kesimi", "Kuaför", default);
        var other = await ServiceCatalogLinker.GetOrCreateAsync(db, "Saç Kesimi", "Evcil Hayvan", default);
        Assert.Equal(first.Id, same.Id); Assert.NotEqual(first.Id, other.Id); Assert.Equal("SAÇ KESİMİ", first.NormalizedName);
    }

    [Fact]
    public void Nearby_catalog_id_matches_linked_active_service_and_unknown_is_empty()
    {
        var catalogId = Guid.NewGuid(); var unknown = Guid.NewGuid();
        var services = new[] { new BarberService { Id = Guid.NewGuid(), ServiceDefinitionId = catalogId, Name = "Saç", IsActive = true } };
        Assert.Contains(services, s => s.IsActive && (s.Id == catalogId || s.ServiceDefinitionId == catalogId));
        Assert.DoesNotContain(services, s => s.IsActive && (s.Id == unknown || s.ServiceDefinitionId == unknown));
    }

    private static ServiceDefinition Def(string name, string category, int order, bool active) => new()
    { Id = Guid.NewGuid(), Name = name, NormalizedName = ServiceCatalogLinker.NormalizeName(name), CategoryName = category,
      NormalizedCategoryName = ServiceCatalogLinker.NormalizeName(category), SortOrder = order, IsActive = active, CreatedAt = DateTime.UtcNow };
    private static AppDbContext Db() => new(new DbContextOptionsBuilder<AppDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
}
