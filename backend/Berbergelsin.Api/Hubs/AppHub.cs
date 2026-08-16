using System.Security.Claims;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Auth;
using Berbergelsin.Api.Enums;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using NetTopologySuite.Geometries;

namespace Berbergelsin.Api.Hubs;

[Authorize]
public class AppHub : Hub
{
    private readonly AppDbContext _db;
    private static readonly GeometryFactory Geo = new(new PrecisionModel(), 4326);

    public AppHub(AppDbContext db) => _db = db;

    private Guid UserId => Guid.Parse(Context.User!.FindFirstValue(ClaimTypes.NameIdentifier)!);
    private string? Role => Context.User!.FindFirstValue(ClaimTypes.Role);
    private int TokenVersion => int.Parse(Context.User!.FindFirstValue("tokenVersion")!);
    private Guid? BarberProfileId
    {
        get
        {
            var v = Context.User!.FindFirstValue("barberProfileId");
            return v == null ? null : Guid.Parse(v);
        }
    }

    public override async Task OnConnectedAsync()
    {
        if (!await SessionIsCurrent())
        {
            Context.Abort();
            return;
        }
        await Groups.AddToGroupAsync(Context.ConnectionId, SessionGroups.User(UserId, TokenVersion));
        if (Role == nameof(UserRole.Admin))
            await Groups.AddToGroupAsync(Context.ConnectionId, $"admins:v{TokenVersion}");
        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        // İşletme bağlantısı koptuğunda haritadan düşür
        if (Role == nameof(UserRole.Berber) && BarberProfileId is Guid barberId)
        {
            var updated = await _db.BarberProfiles
                .Where(b => b.Id == barberId && b.IsOnline)
                .ExecuteUpdateAsync(s => s.SetProperty(b => b.IsOnline, false));
            if (updated > 0)
                await Clients.Group("map-watchers")
                    .SendAsync("BarberOnlineChanged", new { barberProfileId = barberId, isOnline = false });
        }
        await base.OnDisconnectedAsync(exception);
    }

    public async Task JoinMap()
    {
        if (!await SessionIsCurrent()) { Context.Abort(); return; }
        await Groups.AddToGroupAsync(Context.ConnectionId, "map-watchers");
    }
    public Task LeaveMap() => Groups.RemoveFromGroupAsync(Context.ConnectionId, "map-watchers");

    public async Task SetOnline(bool isOnline)
    {
        if (!await SessionIsCurrent()) { Context.Abort(); return; }
        if (Role != nameof(UserRole.Berber) || BarberProfileId is not Guid barberId) return;

        var barber = await _db.BarberProfiles.FirstOrDefaultAsync(b => b.Id == barberId);
        if (barber == null || barber.Status != BarberStatus.Approved) return;

        barber.IsOnline = isOnline;
        await _db.SaveChangesAsync();

        await Clients.Group("map-watchers")
            .SendAsync("BarberOnlineChanged", new { barberProfileId = barberId, isOnline });
    }

    public async Task UpdateLocation(double lat, double lng)
    {
        if (!await SessionIsCurrent()) { Context.Abort(); return; }
        if (Role != nameof(UserRole.Berber) || BarberProfileId is not Guid barberId) return;
        if (lat is < -90 or > 90 || lng is < -180 or > 180) return;

        var barber = await _db.BarberProfiles.FirstOrDefaultAsync(b => b.Id == barberId);
        if (barber == null || barber.Status != BarberStatus.Approved) return;

        // DB yazımını 10 sn'de bire sınırla; yayın her zaman yapılır
        var now = DateTime.UtcNow;
        if (barber.LastLocationAt == null || (now - barber.LastLocationAt.Value).TotalSeconds >= 10)
        {
            barber.Location = Geo.CreatePoint(new Coordinate(lng, lat));
            barber.LastLocationAt = now;
            await _db.SaveChangesAsync();
        }

        if (barber.IsOnline)
            await Clients.Group("map-watchers")
                .SendAsync("BarberLocationUpdated", new { barberProfileId = barberId, lat, lng });

        await PushTrackingUpdatesAsync(barberId, lat, lng);
    }

    private async Task<bool> SessionIsCurrent()
    {
        var versionRaw = Context.User?.FindFirstValue("tokenVersion");
        if (!int.TryParse(versionRaw, out var version)) return false;
        var role = Context.User?.FindFirstValue(ClaimTypes.Role);
        if (!Enum.TryParse<UserRole>(role, out var expectedRole)) return false;
        return await _db.Users.AsNoTracking().AnyAsync(u => u.Id == UserId &&
            u.AccountStatus == AccountStatus.Active && u.Role == expectedRole && u.TokenVersion == version);
    }

    /// <summary>Yoldaki randevular için müşteriye canlı konum + ETA gönderir;
    /// hizmet veren müşteriye 200 m yaklaştığında randevuyu otomatik başlatır.</summary>
    private async Task PushTrackingUpdatesAsync(Guid barberId, double lat, double lng)
    {
        var activeRequests = await _db.ServiceRequests
            .Where(r => r.BarberProfileId == barberId &&
                        (r.Status == RequestStatus.OnTheWay || r.Status == RequestStatus.Started))
            .ToListAsync();

        foreach (var request in activeRequests)
        {
            if (request.ClientLocation is null) continue;
            var distance = Services.GeoUtils.DistanceMeters(
                lat, lng, request.ClientLocation.Y, request.ClientLocation.X);

            if (request.Status == RequestStatus.OnTheWay && distance <= 200)
            {
                request.Status = RequestStatus.Started;
                request.StartedAt = DateTime.UtcNow;
                await _db.SaveChangesAsync();

                var statusPayload = new { requestId = request.Id, status = request.Status.ToString() };
                var clientGroup = await CurrentGroup(request.ClientUserId);
                if (clientGroup != null) await Clients.Group(clientGroup).SendAsync("RequestUpdated", statusPayload);
                await Clients.Group(SessionGroups.User(UserId, TokenVersion)).SendAsync("RequestUpdated", statusPayload);
            }

            var trackingGroup = await CurrentGroup(request.ClientUserId);
            if (trackingGroup != null) await Clients.Group(trackingGroup).SendAsync("TrackingUpdate", new
            {
                requestId = request.Id,
                lat,
                lng,
                distanceMeters = Math.Round(distance),
                etaMinutes = Services.GeoUtils.EtaMinutes(distance),
                status = request.Status.ToString()
            });
        }
    }

    private async Task<string?> CurrentGroup(Guid userId)
    {
        var account = await _db.Users.AsNoTracking().Where(u => u.Id == userId && u.AccountStatus == AccountStatus.Active)
            .Select(u => new { u.TokenVersion }).SingleOrDefaultAsync();
        return account == null ? null : SessionGroups.User(userId, account.TokenVersion);
    }
}
