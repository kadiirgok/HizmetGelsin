using Berbergelsin.Api.Data;
using Berbergelsin.Api.Entities;
using Microsoft.EntityFrameworkCore;
using System.Globalization;

namespace Berbergelsin.Api.Services;

public static class ServiceCatalogLinker
{
    private static readonly TextInfo TurkishText = CultureInfo.GetCultureInfo("tr-TR").TextInfo;
    public static string NormalizeName(string value) => TurkishText.ToUpper(value.Trim());

    public static async Task<ServiceDefinition> GetOrCreateAsync(
        AppDbContext db, string name, string? category, CancellationToken ct)
    {
        var cleanName = name.Trim();
        var cleanCategory = string.IsNullOrWhiteSpace(category) ? "Diğer" : category.Trim();
        var normalized = NormalizeName(cleanName);
        var normalizedCategory = NormalizeName(cleanCategory);
        var tracked = db.ServiceDefinitions.Local.FirstOrDefault(x =>
            x.NormalizedCategoryName == normalizedCategory && x.NormalizedName == normalized);
        if (tracked != null) return tracked;
        var existing = await db.ServiceDefinitions.FirstOrDefaultAsync(x =>
            x.NormalizedCategoryName == normalizedCategory && x.NormalizedName == normalized, ct);
        if (existing != null) return existing;
        var definition = new ServiceDefinition
        {
            Id = Guid.NewGuid(), Name = cleanName, NormalizedName = normalized,
            CategoryName = cleanCategory, IsActive = true, CreatedAt = DateTime.UtcNow
            , NormalizedCategoryName = normalizedCategory
        };
        db.ServiceDefinitions.Add(definition);
        return definition;
    }
}
