using System.Collections.Concurrent;
using Berbergelsin.Api.Auth;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Dtos;
using Berbergelsin.Api.Entities;
using Berbergelsin.Api.Enums;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;

namespace Berbergelsin.Api.Controllers;

[ApiController]
[Route("api/client/addresses")]
[Authorize(Roles = "Musteri")]
[EnableRateLimiting("client-address")]
public sealed class ClientAddressesController(AppDbContext db, IConfiguration configuration) : ControllerBase
{
    private static readonly ConcurrentDictionary<Guid, SemaphoreSlim> UserLocks = new();
    private int Limit => Math.Clamp(configuration.GetValue("ClientAddresses:MaxActive", 10), 5, 20);

    [HttpGet]
    public async Task<IActionResult> List(CancellationToken ct)
    {
        var userId = User.GetUserId();
        if (!await ActiveClient(userId, ct)) return Error(403, "client_address_forbidden");
        var rows = await db.ClientAddresses.AsNoTracking()
            .Where(a => a.UserId == userId && !a.IsDeleted)
            .OrderByDescending(a => a.IsDefault).ThenByDescending(a => a.UpdatedAt).ThenBy(a => a.Id)
            .Select(a => ToDto(a)).ToListAsync(ct);
        return Ok(rows);
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Get(Guid id, CancellationToken ct)
    {
        var userId = User.GetUserId();
        if (!await ActiveClient(userId, ct)) return Error(403, "client_address_forbidden");
        var address = await db.ClientAddresses.AsNoTracking()
            .SingleOrDefaultAsync(a => a.Id == id && a.UserId == userId && !a.IsDeleted, ct);
        return address == null ? Error(404, "client_address_not_found") : Ok(ToDto(address));
    }

    [HttpPost]
    public async Task<IActionResult> Create(SaveClientAddressRequest request, CancellationToken ct)
    {
        var validation = Validate(request, requireVersion: false);
        if (validation != null) return validation;
        var userId = User.GetUserId();
        if (!await ActiveClient(userId, ct)) return Error(403, "client_address_forbidden");
        var gate = UserLocks.GetOrAdd(userId, _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync(ct);
        try
        {
            await using var tx = db.Database.IsRelational() ? await db.Database.BeginTransactionAsync(ct) : null;
            var count = await db.ClientAddresses.CountAsync(a => a.UserId == userId && !a.IsDeleted, ct);
            if (count >= Limit) return Error(409, "client_address_limit_reached");
            var makeDefault = count == 0 || request.IsDefault;
            if (makeDefault) await ClearDefault(userId, null, ct);
            var now = DateTime.UtcNow;
            var entity = new ClientAddress { Id = Guid.NewGuid(), UserId = userId,
                CreatedAt = now, UpdatedAt = now, IsDefault = makeDefault };
            Apply(entity, request);
            db.ClientAddresses.Add(entity);
            try { await db.SaveChangesAsync(ct); }
            catch (DbUpdateException) { return Error(409, "client_address_default_conflict"); }
            if (tx != null) await tx.CommitAsync(ct);
            return CreatedAtAction(nameof(Get), new { id = entity.Id }, ToDto(entity));
        }
        finally { gate.Release(); }
    }

    [HttpPut("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, SaveClientAddressRequest request, CancellationToken ct)
    {
        var validation = Validate(request, requireVersion: true);
        if (validation != null) return validation;
        var userId = User.GetUserId();
        if (!await ActiveClient(userId, ct)) return Error(403, "client_address_forbidden");
        var gate = UserLocks.GetOrAdd(userId, _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync(ct);
        try
        {
            await using var tx = db.Database.IsRelational() ? await db.Database.BeginTransactionAsync(ct) : null;
            var entity = await db.ClientAddresses.SingleOrDefaultAsync(a => a.Id == id && a.UserId == userId && !a.IsDeleted, ct);
            if (entity == null) return Error(404, "client_address_not_found");
            if (!Guid.TryParse(request.Version, out var expected) || entity.Version != expected)
                return Error(409, "client_address_conflict");
            if (request.IsDefault && !entity.IsDefault) await ClearDefault(userId, id, ct);
            Apply(entity, request);
            entity.UpdatedAt = DateTime.UtcNow;
            entity.Version = Guid.NewGuid();
            try { await db.SaveChangesAsync(ct); }
            catch (DbUpdateConcurrencyException) { return Error(409, "client_address_conflict"); }
            catch (DbUpdateException) { return Error(409, "client_address_default_conflict"); }
            if (tx != null) await tx.CommitAsync(ct);
            return Ok(ToDto(entity));
        }
        finally { gate.Release(); }
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct)
    {
        var userId = User.GetUserId();
        if (!await ActiveClient(userId, ct)) return Error(403, "client_address_forbidden");
        var gate = UserLocks.GetOrAdd(userId, _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync(ct);
        try
        {
            await using var tx = db.Database.IsRelational() ? await db.Database.BeginTransactionAsync(ct) : null;
            var entity = await db.ClientAddresses.SingleOrDefaultAsync(a => a.Id == id && a.UserId == userId, ct);
            if (entity == null) return Error(404, "client_address_not_found");
            if (entity.IsDeleted) return Ok(new { id, deleted = true });
            var wasDefault = entity.IsDefault;
            entity.IsDeleted = true; entity.IsDefault = false; entity.DeletedAt = DateTime.UtcNow;
            entity.UpdatedAt = entity.DeletedAt.Value; entity.Version = Guid.NewGuid();
            await db.SaveChangesAsync(ct);
            if (wasDefault)
            {
                var replacement = await db.ClientAddresses.Where(a => a.UserId == userId && !a.IsDeleted)
                    .OrderByDescending(a => a.UpdatedAt).ThenBy(a => a.Id).FirstOrDefaultAsync(ct);
                if (replacement != null) { replacement.IsDefault = true; replacement.UpdatedAt = DateTime.UtcNow;
                    replacement.Version = Guid.NewGuid(); await db.SaveChangesAsync(ct); }
            }
            if (tx != null) await tx.CommitAsync(ct);
            return Ok(new { id, deleted = true });
        }
        finally { gate.Release(); }
    }

    [HttpPost("{id:guid}/set-default")]
    public async Task<IActionResult> SetDefault(Guid id, CancellationToken ct)
    {
        var userId = User.GetUserId();
        if (!await ActiveClient(userId, ct)) return Error(403, "client_address_forbidden");
        var gate = UserLocks.GetOrAdd(userId, _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync(ct);
        try
        {
            await using var tx = db.Database.IsRelational() ? await db.Database.BeginTransactionAsync(ct) : null;
            var entity = await db.ClientAddresses.SingleOrDefaultAsync(a => a.Id == id && a.UserId == userId && !a.IsDeleted, ct);
            if (entity == null) return Error(404, "client_address_not_found");
            if (!entity.IsDefault)
            {
                await ClearDefault(userId, id, ct);
                entity.IsDefault = true; entity.UpdatedAt = DateTime.UtcNow; entity.Version = Guid.NewGuid();
                try { await db.SaveChangesAsync(ct); }
                catch (DbUpdateException) { return Error(409, "client_address_default_conflict"); }
            }
            if (tx != null) await tx.CommitAsync(ct);
            return Ok(ToDto(entity));
        }
        finally { gate.Release(); }
    }

    private async Task ClearDefault(Guid userId, Guid? exceptId, CancellationToken ct)
    {
        var defaults = await db.ClientAddresses.Where(a => a.UserId == userId && !a.IsDeleted && a.IsDefault && a.Id != exceptId).ToListAsync(ct);
        foreach (var old in defaults) { old.IsDefault = false; old.UpdatedAt = DateTime.UtcNow; old.Version = Guid.NewGuid(); }
        if (defaults.Count > 0) await db.SaveChangesAsync(ct);
    }

    private async Task<bool> ActiveClient(Guid userId, CancellationToken ct) =>
        await db.Users.AsNoTracking().AnyAsync(u => u.Id == userId && u.Role == UserRole.Musteri
            && u.AccountStatus == AccountStatus.Active && u.OnboardingCompleted, ct);

    private ObjectResult? Validate(SaveClientAddressRequest r, bool requireVersion)
    {
        static bool TooLong(string? value, int max) => value?.Trim().Length > max;
        if (string.IsNullOrWhiteSpace(r.Label) || r.Label.Trim().Length > 50 ||
            string.IsNullOrWhiteSpace(r.AddressLine) || r.AddressLine.Trim().Length > 500 ||
            !double.IsFinite(r.Latitude) || !double.IsFinite(r.Longitude) ||
            r.Latitude is < -90 or > 90 || r.Longitude is < -180 or > 180 ||
            TooLong(r.PlaceId, 300) || TooLong(r.FormattedAddress, 500) || TooLong(r.Province, 100) ||
            TooLong(r.District, 100) || TooLong(r.Neighborhood, 150) || TooLong(r.Street, 150) ||
            TooLong(r.StreetNumber, 30) || TooLong(r.PostalCode, 20) ||
            (requireVersion && !Guid.TryParse(r.Version, out _))) return Error(400, "client_address_invalid");
        return null;
    }

    private static void Apply(ClientAddress a, SaveClientAddressRequest r)
    {
        static string? N(string? x) => string.IsNullOrWhiteSpace(x) ? null : x.Trim();
        a.Label = r.Label.Trim(); a.PlaceId = N(r.PlaceId); a.FormattedAddress = N(r.FormattedAddress);
        a.Province = N(r.Province); a.District = N(r.District); a.Neighborhood = N(r.Neighborhood);
        a.Street = N(r.Street); a.StreetNumber = N(r.StreetNumber); a.PostalCode = N(r.PostalCode);
        a.AddressLine = r.AddressLine.Trim(); a.Latitude = r.Latitude; a.Longitude = r.Longitude;
        if (!r.IsDefault && !a.IsDefault) a.IsDefault = false;
    }

    private static ClientAddressDto ToDto(ClientAddress a) => new(a.Id, a.Label, a.PlaceId,
        a.FormattedAddress, a.Province, a.District, a.Neighborhood, a.Street, a.StreetNumber,
        a.PostalCode, a.AddressLine, a.Latitude, a.Longitude, a.IsDefault, a.CreatedAt,
        a.UpdatedAt, a.Version.ToString("D"));
    private ObjectResult Error(int status, string code) => StatusCode(status, new { code });
}
