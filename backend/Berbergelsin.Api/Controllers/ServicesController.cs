using Berbergelsin.Api.Data;
using Berbergelsin.Api.Dtos;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Berbergelsin.Api.Services;

namespace Berbergelsin.Api.Controllers;

[ApiController]
[Route("api/services")]
public sealed class ServicesController(AppDbContext db) : ControllerBase
{
    [HttpGet("catalog")]
    [AllowAnonymous]
    public async Task<IActionResult> Catalog([FromQuery] string? category, [FromQuery] string? q,
        [FromQuery] bool? isActive, [FromQuery] Guid? categoryId, CancellationToken ct)
    {
        if (categoryId.HasValue)
            return BadRequest(new { code = "service_catalog_invalid_query", message = "Kategori kimliği henüz desteklenmiyor." });
        if (q?.Trim().Length > 80 || category?.Trim().Length > 80)
            return BadRequest(new { code = "service_catalog_invalid_query", message = "Filtre en fazla 80 karakter olabilir." });

        var query = db.ServiceDefinitions.AsNoTracking().AsQueryable();
        query = query.Where(x => x.IsActive == (isActive ?? true));
        var cleanCategory = category?.Trim();
        var cleanQ = q?.Trim();
        if (!string.IsNullOrEmpty(cleanCategory))
        {
            var normalizedCategory = ServiceCatalogLinker.NormalizeName(cleanCategory);
            query = query.Where(x => x.NormalizedCategoryName == normalizedCategory);
        }
        if (!string.IsNullOrEmpty(cleanQ))
        {
            var normalizedQ = ServiceCatalogLinker.NormalizeName(cleanQ);
            query = query.Where(x => x.NormalizedName.Contains(normalizedQ));
        }

        var items = await query.OrderBy(x => x.SortOrder).ThenBy(x => x.CategoryName)
            .ThenBy(x => x.Name).ThenBy(x => x.Id)
            .Select(x => new ServiceCatalogItemDto(x.Id, x.Name, null, x.CategoryName, x.IsActive))
            .ToListAsync(ct);
        return Ok(items);
    }
}
