using Berbergelsin.Api.Data;
using Berbergelsin.Api.Dtos;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Berbergelsin.Api.Controllers;

[ApiController]
[Route("api/categories")]
public class CategoriesController(AppDbContext db) : ControllerBase
{
    [HttpGet]
    [AllowAnonymous]
    public async Task<IActionResult> List(CancellationToken ct)
    {
        var groups = await db.CategoryGroups
            .OrderBy(g => g.SortOrder)
            .Select(g => new CategoryGroupDto(
                g.Id,
                g.Name,
                g.Icon,
                g.Categories.OrderBy(c => c.SortOrder).Select(c =>
                    new ServiceCategoryDto(c.Id, c.Name, c.SortOrder)).ToList()
            ))
            .ToListAsync(ct);

        return Ok(groups);
    }

    [HttpGet("categories")]
    [AllowAnonymous]
    public async Task<IActionResult> FlatList(CancellationToken ct)
    {
        var items = await db.ServiceCategories
            .Include(c => c.Group)
            .OrderBy(c => c.Group.SortOrder).ThenBy(c => c.SortOrder)
            .Select(c => new
            {
                c.Id,
                c.Name,
                GroupName = c.Group.Name,
                c.SortOrder
            })
            .ToListAsync(ct);

        return Ok(items);
    }
}
