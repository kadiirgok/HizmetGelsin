using Berbergelsin.Api.Auth;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Dtos;
using Berbergelsin.Api.Entities;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.RateLimiting;

namespace Berbergelsin.Api.Controllers;

[ApiController, Authorize, EnableRateLimiting("notification"), Route("api/notifications")]
public sealed class NotificationsController(AppDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List([FromQuery] int page = 1, [FromQuery] int pageSize = 20,
        [FromQuery] bool? isRead = null, CancellationToken ct = default)
    {
        if (page < 1 || pageSize < 1 || pageSize > 50) return Error(400, "notification_invalid_query");
        var userId = User.GetUserId();
        var query = db.Notifications.AsNoTracking().Where(n => n.UserId == userId);
        if (isRead.HasValue) query = query.Where(n => n.IsRead == isRead.Value);
        var total = await query.CountAsync(ct);
        var items = await query.OrderByDescending(n => n.CreatedAt).ThenBy(n => n.Id)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(n => new NotificationDto(n.Id, n.Type, n.Title, n.Body, n.EntityType,
                n.EntityId, n.Route, n.IsRead, n.ReadAt, n.CreatedAt)).ToListAsync(ct);
        return Ok(new NotificationPageDto(items, page, pageSize, total, page * pageSize < total));
    }

    [HttpGet("unread-count")]
    public async Task<IActionResult> UnreadCount(CancellationToken ct) =>
        Ok(new { unreadCount = await db.Notifications.CountAsync(n => n.UserId == User.GetUserId() && !n.IsRead, ct) });

    [HttpPost("{id:guid}/read")]
    public async Task<IActionResult> Read(Guid id, CancellationToken ct)
    {
        var item = await db.Notifications.FirstOrDefaultAsync(n => n.Id == id && n.UserId == User.GetUserId(), ct);
        if (item == null) return Error(404, "notification_not_found");
        if (!item.IsRead) { item.IsRead = true; item.ReadAt = DateTime.UtcNow; await db.SaveChangesAsync(ct); }
        return Ok(ToDto(item));
    }

    [HttpPost("read-all")]
    public async Task<IActionResult> ReadAll(CancellationToken ct)
    {
        var userId = User.GetUserId(); var now = DateTime.UtcNow;
        var items = await db.Notifications.Where(n => n.UserId == userId && !n.IsRead).ToListAsync(ct);
        foreach (var item in items) { item.IsRead = true; item.ReadAt = now; }
        await db.SaveChangesAsync(ct);
        return Ok(new { updatedCount = items.Count, readAt = now });
    }

    [HttpPost("devices")]
    public async Task<IActionResult> Register(RegisterDeviceRequest request, CancellationToken ct)
    {
        var platform = request.Platform?.Trim().ToLowerInvariant();
        var token = request.Token?.Trim(); var deviceId = request.DeviceId?.Trim();
        if (platform is not ("android" or "ios") || string.IsNullOrEmpty(token) || token.Length > 4096 ||
            string.IsNullOrEmpty(deviceId) || deviceId.Length > 200)
            return Error(400, "notification_device_invalid");
        var userId = User.GetUserId(); var now = DateTime.UtcNow;
        var byToken = await db.DevicePushTokens.FirstOrDefaultAsync(d => d.Token == token, ct);
        if (byToken != null && byToken.UserId != userId)
        {
            byToken.UserId = userId; byToken.DeviceId = deviceId; byToken.Platform = platform;
            byToken.IsActive = true; byToken.LastSeenAt = now; byToken.UpdatedAt = now;
        }
        else
        {
            var device = byToken ?? await db.DevicePushTokens.FirstOrDefaultAsync(d => d.UserId == userId && d.DeviceId == deviceId, ct);
            if (device == null)
            {
                device = new DevicePushToken { Id = Guid.NewGuid(), UserId = userId, CreatedAt = now };
                db.DevicePushTokens.Add(device);
            }
            device.Platform = platform; device.Token = token; device.DeviceId = deviceId;
            device.IsActive = true; device.LastSeenAt = now; device.UpdatedAt = now;
        }
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateException) { return Error(409, "notification_device_conflict"); }
        return Ok(new { deviceId, platform, isActive = true });
    }

    [HttpDelete("devices/{deviceId}")]
    public async Task<IActionResult> Unregister(string deviceId, CancellationToken ct)
    {
        var item = await db.DevicePushTokens.FirstOrDefaultAsync(d => d.UserId == User.GetUserId() && d.DeviceId == deviceId, ct);
        if (item != null && item.IsActive) { item.IsActive = false; item.UpdatedAt = DateTime.UtcNow; await db.SaveChangesAsync(ct); }
        return Ok(new { deviceId, isActive = false });
    }

    static NotificationDto ToDto(Notification n) => new(n.Id, n.Type, n.Title, n.Body,
        n.EntityType, n.EntityId, n.Route, n.IsRead, n.ReadAt, n.CreatedAt);
    ObjectResult Error(int status, string code) => StatusCode(status, new { code });
}
