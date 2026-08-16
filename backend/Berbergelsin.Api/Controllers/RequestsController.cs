using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Berbergelsin.Api.Auth;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Dtos;
using Berbergelsin.Api.Entities;
using Berbergelsin.Api.Enums;
using Berbergelsin.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using NetTopologySuite.Geometries;

namespace Berbergelsin.Api.Controllers;

[ApiController]
[Route("api/requests")]
[Authorize]
public class RequestsController : ControllerBase
{
    private static readonly GeometryFactory Geo = new(new PrecisionModel(), 4326);
    private static readonly ConcurrentDictionary<Guid, SemaphoreSlim> BusinessLocks = new();
    private static readonly ConcurrentDictionary<Guid, SemaphoreSlim> RequestLocks = new();
    private static readonly TimeZoneInfo Istanbul = TimeZoneInfo.FindSystemTimeZoneById("Europe/Istanbul");
    private static readonly RequestStatus[] BlockingStatuses = [RequestStatus.Pending, RequestStatus.Accepted, RequestStatus.OnTheWay, RequestStatus.Started];

    private readonly AppDbContext _db;
    private readonly RealtimeNotifier _notifier;

    public RequestsController(AppDbContext db, RealtimeNotifier notifier)
    {
        _db = db;
        _notifier = notifier;
    }

    [HttpPost]
    [Authorize(Roles = "Musteri")]
    [EnableRateLimiting("service-request")]
    public async Task<IActionResult> Create(CreateServiceRequestDto request, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var key = Request.Headers["Idempotency-Key"].FirstOrDefault()?.Trim();
        if (!ValidIdempotencyKey(key)) return Error(400, "request_invalid", "Geçerli bir Idempotency-Key zorunludur.");
        if (request.ServiceIds == null || request.ServiceIds.Count == 0 || request.ServiceIds.Count > 20)
            return Error(400, "request_invalid", "En az bir hizmet seçmelisiniz.");
        if (request.ServiceIds.Distinct().Count() != request.ServiceIds.Count)
            return Error(400, "request_invalid", "Aynı hizmet birden fazla seçilemez.");
        // Tag tarzı anlık eşleşme: talep zamanı şimdi veya 5 dk içinde olmalı
        // (istemci saati ile sunucu arasında ufak fark toleransı)
        var requestedUtc = request.RequestedTime.ToUniversalTime();
        if (requestedUtc < DateTimeOffset.UtcNow.AddMinutes(-5) || requestedUtc > DateTimeOffset.UtcNow.AddDays(90))
            return Error(400, "request_invalid", "Talep zamanı geçersiz.");

        if (request.AddressId != null && !string.Equals(request.ServiceLocationType, "customerAddress", StringComparison.OrdinalIgnoreCase))
            return Error(400, "request_invalid_location", "Kayıtlı adres yalnız müşteri adresinde hizmet için kullanılabilir.");
        var payloadHash = PayloadHash(request, requestedUtc);
        var gate = BusinessLocks.GetOrAdd(request.BarberProfileId, _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync(ct);
        try
        {
            var existing = await _db.ServiceRequests.AsNoTracking()
                .FirstOrDefaultAsync(r => r.ClientUserId == userId && r.IdempotencyKey == key, ct);
            if (existing != null)
                return existing.IdempotencyPayloadHash == payloadHash
                    ? Ok(await ToDtoAsync(existing.Id, ct))
                    : Error(409, "request_idempotency_conflict", "Idempotency anahtarı farklı bir istek için kullanılmış.");

            await using var transaction = _db.Database.IsRelational()
                ? await _db.Database.BeginTransactionAsync(System.Data.IsolationLevel.Serializable, ct) : null;
            if (_db.Database.ProviderName?.Contains("Npgsql", StringComparison.OrdinalIgnoreCase) == true)
                await _db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtext({request.BarberProfileId.ToString()}))", ct);

            // Başka API instance'ı advisory lock beklerken aynı key'i commit etmiş olabilir.
            existing = await _db.ServiceRequests.AsNoTracking()
                .FirstOrDefaultAsync(r => r.ClientUserId == userId && r.IdempotencyKey == key, ct);
            if (existing != null)
                return existing.IdempotencyPayloadHash == payloadHash
                    ? Ok(await ToDtoAsync(existing.Id, ct))
                    : Error(409, "request_idempotency_conflict", "Idempotency anahtarı farklı bir istek için kullanılmış.");

            var barber = await _db.BarberProfiles.Include(b => b.User)
                .FirstOrDefaultAsync(b => b.Id == request.BarberProfileId && b.Status == BarberStatus.Approved && b.IsOnline
                    && b.User.AccountStatus == AccountStatus.Active && b.User.OnboardingCompleted, ct);
            if (barber == null) return Error(404, "request_business_unavailable", "İşletme kullanılamıyor.");

            var services = await _db.BarberServices.AsNoTracking()
                .Where(s => s.BarberProfileId == barber.Id && s.IsActive && request.ServiceIds.Contains(s.Id))
                .OrderBy(s => s.Id).ToListAsync(ct);
            if (services.Count != request.ServiceIds.Count)
                return Error(400, "request_service_unavailable", "Seçilen hizmetlerden biri kullanılamıyor.");
            var duration = TimeSpan.FromMinutes(services.Sum(s => Math.Clamp(s.DurationMinutes ?? 60, 5, 480)));
            var scheduledEnd = requestedUtc.Add(duration);
            if (!InsideWorkingHours(barber.WorkingHours, requestedUtc, scheduledEnd))
                return Error(409, "request_outside_working_hours", "Seçilen zaman işletmenin çalışma saatleri dışında.");

            var atCustomer = barber.ServiceMode is "Mobile" or "Both";
            if (request.ServiceLocationType != null)
            {
                if (request.ServiceLocationType.Equals("customerAddress", StringComparison.OrdinalIgnoreCase)) atCustomer = true;
                else if (request.ServiceLocationType.Equals("business", StringComparison.OrdinalIgnoreCase)) atCustomer = false;
                else return Error(400, "request_invalid_location", "Hizmet konumu geçersiz.");
            }
            Point? clientLocation = null;
            ClientAddress? selectedAddress = null;
            string? addressSnapshot = null;
            if (request.AddressId != null)
            {
                selectedAddress = await _db.ClientAddresses.FirstOrDefaultAsync(a => a.Id == request.AddressId.Value, ct);
                if (selectedAddress == null || selectedAddress.IsDeleted)
                    return Error(404, "request_address_not_found", "Adres bulunamadı.");
                if (selectedAddress.UserId != userId)
                    return Error(403, "request_address_forbidden", "Bu adres kullanılamaz.");
                if (!ValidCoordinates(selectedAddress.Latitude, selectedAddress.Longitude))
                    return Error(400, "request_address_invalid", "Kayıtlı adres konumu geçersiz.");
                clientLocation = Geo.CreatePoint(new Coordinate(selectedAddress.Longitude, selectedAddress.Latitude));
                addressSnapshot = BuildAddressSnapshot(selectedAddress);
            }
            else if (request.Lat != null || request.Lng != null)
            {
                if (request.Lat is < -90 or > 90 || request.Lng is < -180 or > 180 || request.Lat == null || request.Lng == null)
                    return Error(400, "request_invalid", "Geçersiz konum.");
                clientLocation = Geo.CreatePoint(new Coordinate(request.Lng.Value, request.Lat.Value));
                addressSnapshot = (request.AddressSnapshot ?? request.AddressNote)?.Trim();
            }
            if (atCustomer)
            {
                if (clientLocation == null || barber.Location == null)
                    return Error(400, "request_outside_service_area", "Müşteri konumu zorunludur.");
                if (!barber.Location.IsWithinDistance(clientLocation, barber.ServiceRadiusKm * 1000d))
                    return Error(409, "request_outside_service_area", "Adres işletmenin servis alanı dışında.");
            }

            if (await _db.ServiceRequests.AsNoTracking().AnyAsync(r => r.BarberProfileId == barber.Id
                && BlockingStatuses.Contains(r.Status) && r.RequestedTime < scheduledEnd && r.ScheduledEndTime > requestedUtc, ct))
                return Error(409, "request_time_conflict", "Seçilen zaman başka bir taleple çakışıyor.");

            var baseTotal = services.Sum(s => s.Price);
            var finalPrice = baseTotal;
            if (request.ProposedPrice.HasValue)
            {
                var minPrice = baseTotal * 0.9m;
                var maxPrice = baseTotal * 1.1m;
                if (request.ProposedPrice.Value < minPrice || request.ProposedPrice.Value > maxPrice)
                    return Error(400, "request_price_invalid",
                        $"Teklif edilen fiyat ±%10 aralığında olmalıdır (Min: {minPrice:0} TL, Max: {maxPrice:0} TL).");
                finalPrice = request.ProposedPrice.Value;
            }

            var now = DateTime.UtcNow;
            var sr = new ServiceRequest
            {
                Id = Guid.NewGuid(), ClientUserId = userId, CreatedBy = userId, BarberProfileId = barber.Id,
                Status = RequestStatus.Pending, RequestedTime = requestedUtc, ScheduledEndTime = scheduledEnd,
                ClientLocation = clientLocation, ClientAddressId = selectedAddress?.Id,
                AddressSnapshot = addressSnapshot, AddressNote = request.AddressNote?.Trim(),
                TotalPrice = finalPrice, CreatedAt = now, UpdatedAt = now,
                IdempotencyKey = key, IdempotencyPayloadHash = payloadHash,
                Items = services.Select(s => new ServiceRequestItem { Id = Guid.NewGuid(), BarberServiceId = s.Id,
                    ServiceName = s.Name, PriceAtRequest = s.Price }).ToList()
            };
            _db.ServiceRequests.Add(sr);
            await _notifier.EnqueueAsync(barber.UserId, "NewRequest", new { requestId = sr.Id }, ct);
            try { await _db.SaveChangesAsync(ct); }
            catch (DbUpdateException) { return Error(409, "request_idempotency_conflict", "Talep eşzamanlı olarak işlendi."); }
            if (transaction != null) await transaction.CommitAsync(ct);
            return Ok(await ToDtoAsync(sr.Id, ct));
        }
        finally { gate.Release(); }
    }

    [HttpGet("mine")]
    public async Task<IActionResult> Mine(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        CancellationToken ct = default)
    {
        var userId = User.GetUserId();
        var barberProfileId = User.GetBarberProfileId();

        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);

        var query = _db.ServiceRequests
            .Include(r => r.Items)
            .Include(r => r.BarberProfile).ThenInclude(b => b.User)
            .Include(r => r.ClientUser)
            .AsQueryable();

        if (User.IsInRole(UserRole.Berber.ToString()))
        {
            if (barberProfileId == null)
                return Forbid();

            query = query.Where(r => r.BarberProfileId == barberProfileId);
        }
        else if (User.IsInRole(UserRole.Musteri.ToString()))
        {
            query = query.Where(r => r.ClientUserId == userId);
        }
        else
        {
            return Forbid();
        }

        var totalCount = await query.CountAsync(ct);
        var list = await query
            .OrderByDescending(r => r.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(ct);

        // Puanlama bilgisi: hangi taleplere bu kullanıcı puan vermiş
        var requestIds = list.Select(r => r.Id).ToList();
        var myRatings = await _db.Ratings
            .Where(r => requestIds.Contains(r.ServiceRequestId) && r.RaterUserId == userId)
            .ToDictionaryAsync(r => r.ServiceRequestId, r => r.Score, ct);

        return Ok(new
        {
            items = list.Select(r => ToDto(r, userId, myRatings)),
            page,
            pageSize,
            totalCount,
            totalPages = (int)Math.Ceiling((double)totalCount / pageSize),
        });
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Detail(Guid id, CancellationToken ct)
    {
        var authorized = await AuthorizedRequest(id, ct);
        if (authorized == null) return Error(404, "request_not_found", "Talep bulunamadı.");
        return Ok(await ToDtoAsync(id, ct));
    }

    [HttpPost("{id:guid}/accept")]
    [Authorize(Roles = "Berber")]
    public Task<IActionResult> Accept(Guid id, CancellationToken ct)
        => Transition(id, "accept", [RequestStatus.Pending], RequestStatus.Accepted, null, null, ct);

    [HttpPost("{id:guid}/reject")]
    [Authorize(Roles = "Berber")]
    public Task<IActionResult> Reject(Guid id, CancellationToken ct)
        => Transition(id, "reject", [RequestStatus.Pending], RequestStatus.Rejected, "business_rejected", null, ct);

    /// <summary>Hizmet veren yola çıktı — canlı takip başlar.</summary>
    [HttpPost("{id:guid}/on-the-way")]
    [Authorize(Roles = "Berber")]
    public Task<IActionResult> OnTheWay(Guid id, CancellationToken ct)
        => Transition(id, "on-the-way", [RequestStatus.Accepted], RequestStatus.OnTheWay, null, null, ct);

    /// <summary>Manuel başlatma (otomatik 200 m tetiklemesi çalışmazsa hizmet veren elle başlatır).</summary>
    [HttpPost("{id:guid}/start")]
    [Authorize(Roles = "Berber")]
    public Task<IActionResult> Start(Guid id, CancellationToken ct)
        => Transition(id, "start", [RequestStatus.OnTheWay, RequestStatus.Accepted], RequestStatus.Started, null, null, ct);

    [HttpPut("{id:guid}/note")]
    [Authorize(Roles = "Berber")]
    public async Task<IActionResult> UpdateNote(Guid id, UpdateRequestNoteDto request, CancellationToken ct)
    {
        var barberProfileId = User.GetBarberProfileId();
        var sr = await _db.ServiceRequests
            .Include(r => r.BarberProfile)
            .FirstOrDefaultAsync(r => r.Id == id && r.BarberProfileId == barberProfileId, ct);
        if (sr == null) return NotFound();

        sr.AddressNote = string.IsNullOrWhiteSpace(request.Note) ? null : request.Note.Trim();
        await EnqueueRequestUpdatedBoth(sr, ct);
        await _db.SaveChangesAsync(ct);
        return Ok(new { message = "Randevu notu güncellendi." });
    }

    /// <summary>Randevuyu müşteri veya işletme bitirir.</summary>
    [HttpPost("{id:guid}/complete")]
    [Authorize(Roles = "Musteri,Berber")]
    public Task<IActionResult> Complete(Guid id, CancellationToken ct)
        => Transition(id, "complete", [RequestStatus.Accepted, RequestStatus.Started], RequestStatus.Completed, null, null, ct);

    /// <summary>İşletme doğrulama kodunu girer, kod eşleşirse randevuyu tamamlar.</summary>
    [HttpPost("{id:guid}/verify-code")]
    [Authorize(Roles = "Berber")]
    public async Task<IActionResult> VerifyCode(Guid id, VerifyCodeDto request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Code) || request.Code.Length != 4)
            return Error(400, "verify_code_invalid", "Geçerli bir doğrulama kodu girin (4 karakter).");

        var barberProfileId = User.GetBarberProfileId();
        var sr = await _db.ServiceRequests
            .Include(r => r.BarberProfile)
            .FirstOrDefaultAsync(r => r.Id == id && r.BarberProfileId == barberProfileId, ct);
        if (sr == null) return Error(404, "request_not_found", "Talep bulunamadı.");
        if (sr.Status is not (RequestStatus.Accepted or RequestStatus.OnTheWay or RequestStatus.Started))
            return Error(409, "request_invalid_transition", "Talep bu durumda kod ile tamamlanamaz.");

        var expectedCode = sr.Id.ToString("N")[..4].ToUpperInvariant();
        if (!string.Equals(request.Code.Trim(), expectedCode, StringComparison.OrdinalIgnoreCase))
            return Error(400, "verify_code_mismatch", "Doğrulama kodu eşleşmiyor.");

        // Kod doğru → talebi tamamla
        return await Transition(id, "verify-code", [RequestStatus.Accepted, RequestStatus.OnTheWay, RequestStatus.Started], RequestStatus.Completed, null, null, ct);
    }

    [HttpPost("{id:guid}/cancel")]
    public async Task<IActionResult> Cancel(Guid id, CancelRequestDto request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.ReasonCode) || request.ReasonCode.Length > 50 || request.ReasonText?.Length > 500)
            return Error(400, "request_cancellation_invalid", "Geçerli bir iptal nedeni zorunludur.");
        return await Transition(id, "cancel", [RequestStatus.Pending, RequestStatus.Accepted, RequestStatus.OnTheWay, RequestStatus.Started],
            RequestStatus.Cancelled, request.ReasonCode.Trim(), request.ReasonText?.Trim(), ct);
    }

    [HttpPost("{id:guid}/reschedule")]
    public async Task<IActionResult> Reschedule(Guid id, RescheduleRequestDto request, CancellationToken ct)
    {
        var when = request.RequestedStartAt.ToUniversalTime();
        if (when <= DateTimeOffset.UtcNow || when > DateTimeOffset.UtcNow.AddDays(90) || request.Reason?.Length > 500)
            return Error(400, "request_reschedule_invalid", "Yeniden planlama zamanı geçersiz.");
        return await Transition(id, $"reschedule:{when:O}", [RequestStatus.Pending, RequestStatus.Accepted],
            RequestStatus.ReschedulePending, "reschedule_requested", request.Reason?.Trim(), ct, when);
    }

    [HttpPost("{id:guid}/reschedule/accept")]
    public Task<IActionResult> AcceptReschedule(Guid id, CancellationToken ct)
        => Transition(id, "reschedule-accept", [RequestStatus.ReschedulePending], RequestStatus.Accepted,
            "reschedule_accepted", null, ct, acceptReschedule: true);

    [HttpPost("{id:guid}/reschedule/reject")]
    public Task<IActionResult> RejectReschedule(Guid id, CancellationToken ct)
        => Transition(id, "reschedule-reject", [RequestStatus.ReschedulePending], RequestStatus.Accepted,
            "reschedule_rejected", null, ct, rejectReschedule: true);

    [HttpGet("{id:guid}/timeline")]
    public async Task<IActionResult> Timeline(Guid id, CancellationToken ct)
    {
        var sr = await AuthorizedRequest(id, ct);
        if (sr == null) return Error(404, "request_not_found", "Talep bulunamadı.");
        var rows = await _db.RequestStatusHistories.AsNoTracking().Where(h => h.RequestId == id)
            .OrderBy(h => h.CreatedAt).ThenBy(h => h.Id)
            .Select(h => new RequestTimelineDto(h.Id, h.FromStatus, h.ToStatus, h.ChangedByRole,
                h.ReasonCode, h.ReasonText, h.CreatedAt)).ToListAsync(ct);
        return Ok(rows);
    }

    /// <summary>Tamamlanan randevuda karşı tarafı puanla (her iki rol, birer kez).</summary>
    [HttpPost("{id:guid}/rate")]
    [HttpPost("{id:guid}/rating")]
    [Authorize(Roles = "Musteri,Berber")]
    public async Task<IActionResult> Rate(Guid id, RateRequestDto request, CancellationToken ct)
    {
        if (request.Score is < 1 or > 5 || request.Comment?.Trim().Length > 600)
            return Error(400, "rating_invalid", "Yorum bilgileri geçersiz.");

        var userId = User.GetUserId();
        var isBarber = User.IsInRole("Berber");
        var barberProfileId = isBarber ? User.GetBarberProfileId() : null;

        var sr = await _db.ServiceRequests
            .Include(r => r.BarberProfile)
            .Include(r => r.ClientUser)
            .FirstOrDefaultAsync(r => r.Id == id, ct);
        if (sr == null) return Error(404, "rating_not_found", "Talep bulunamadı.");
        if (sr.Status != RequestStatus.Completed)
            return Error(409, "rating_request_not_completed", "Yalnızca tamamlanan randevular yorumlanabilir.");

        // Kim kimi puanlıyor?
        Guid ratedUserId;
        if (isBarber)
        {
            // İşletme müşteriyi puanlıyor
            if (sr.BarberProfile.UserId != userId || sr.BarberProfileId != barberProfileId)
                return Error(403, "rating_forbidden", "Bu talep için yorum yetkiniz yok.");
            ratedUserId = sr.ClientUserId;
        }
        else
        {
            // Müşteri işletmeyi puanlıyor
            if (sr.ClientUserId != userId)
                return Error(403, "rating_forbidden", "Bu talep için yorum yetkiniz yok.");
            ratedUserId = sr.BarberProfile.UserId;
        }

        var alreadyRated = await _db.Ratings
            .AnyAsync(r => r.ServiceRequestId == id && r.RaterUserId == userId, ct);
        if (alreadyRated)
            return Error(409, "rating_already_exists", "Bu talep daha önce yorumlandı.");

        var rating = new Rating
        {
            Id = Guid.NewGuid(),
            ServiceRequestId = id,
            RaterUserId = userId,
            RatedUserId = ratedUserId,
            Score = request.Score,
            Comment = string.IsNullOrWhiteSpace(request.Comment) ? null : request.Comment.Trim(),
            CreatedAt = DateTime.UtcNow
        };
        _db.Ratings.Add(rating);
        await _notifier.EnqueueAsync(ratedUserId, "RatingReceived",
            new { ratingId = rating.Id, requestId = id }, ct);
        try { await _db.SaveChangesAsync(ct); }
        catch (DbUpdateException) { return Error(409, "rating_already_exists", "Bu talep daha önce yorumlandı."); }

        return Ok(new { message = "Değerlendirmeniz kaydedildi. Teşekkürler!" });
    }

    private static bool ValidIdempotencyKey(string? key)
    {
        if (key is null || key.Length is < 8 or > 100) return false;
        return key.All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '_' or '.');
    }

    private static string PayloadHash(CreateServiceRequestDto request, DateTimeOffset requestedUtc)
    {
        var canonical = JsonSerializer.Serialize(new
        {
            request.BarberProfileId,
            ServiceIds = request.ServiceIds.OrderBy(x => x),
            RequestedTime = requestedUtc.ToString("O"),
            Lat = request.Lat is null ? (double?)null : Math.Round(request.Lat.Value, 6),
            Lng = request.Lng is null ? (double?)null : Math.Round(request.Lng.Value, 6),
            AddressNote = request.AddressNote?.Trim(),
            request.AddressId,
            ServiceLocationType = request.ServiceLocationType?.Trim().ToLowerInvariant(),
            ProposedPrice = request.ProposedPrice
        });
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(canonical)));
    }

    private static bool ValidCoordinates(double latitude, double longitude) =>
        latitude is >= -90 and <= 90 && longitude is >= -180 and <= 180;

    private static string BuildAddressSnapshot(ClientAddress address)
    {
        var parts = new[] { address.AddressLine, address.Neighborhood, address.District, address.Province }
            .Where(x => !string.IsNullOrWhiteSpace(x)).Select(x => x!.Trim()).Distinct();
        return string.Join(", ", parts);
    }

    internal static bool InsideWorkingHours(string json, DateTimeOffset startUtc, DateTimeOffset endUtc)
    {
        // Çalışma saatleri kaldırıldı — online olan her zaman çalışıyordur.
        return true;
    }

    private ObjectResult Error(int status, string code, string message) => StatusCode(status, new { code, message });

    private async Task<ServiceRequest?> AuthorizedRequest(Guid id, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var sr = await _db.ServiceRequests.Include(r => r.BarberProfile).ThenInclude(b => b.User)
            .Include(r => r.ClientUser).FirstOrDefaultAsync(r => r.Id == id, ct);
        if (sr == null) return null;
        var role = User.IsInRole("Berber") ? UserRole.Berber : User.IsInRole("Musteri") ? UserRole.Musteri : (UserRole?)null;
        if (role == null || (role == UserRole.Musteri && sr.ClientUserId != userId) ||
            (role == UserRole.Berber && sr.BarberProfile.UserId != userId)) return null;
        var actor = role == UserRole.Musteri ? sr.ClientUser : sr.BarberProfile.User;
        return actor.Role == role && actor.AccountStatus == AccountStatus.Active && actor.OnboardingCompleted ? sr : null;
    }

    private async Task<IActionResult> Transition(Guid id, string action, RequestStatus[] from, RequestStatus to,
        string? reasonCode, string? reasonText, CancellationToken ct, DateTimeOffset? proposedStart = null,
        bool acceptReschedule = false, bool rejectReschedule = false)
    {
        var userId = User.GetUserId();
        var role = User.IsInRole("Berber") ? "Berber" : User.IsInRole("Musteri") ? "Musteri" : null;
        if (role == null) return Error(403, "request_forbidden", "Bu işlem için yetkiniz yok.");
        var key = Request.Headers["Idempotency-Key"].FirstOrDefault()?.Trim();
        if (!ValidIdempotencyKey(key)) return Error(400, "request_invalid_transition", "Geçerli bir Idempotency-Key zorunludur.");
        var payloadHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(
            JsonSerializer.Serialize(new { id, action, reasonCode, reasonText, proposedStart }))));
        var gate = RequestLocks.GetOrAdd(id, _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync(ct);
        try
        {
            var previous = await _db.RequestOperations.AsNoTracking()
                .FirstOrDefaultAsync(o => o.UserId == userId && o.IdempotencyKey == key, ct);
            if (previous != null)
            {
                if (previous.PayloadHash != payloadHash)
                    return Error(409, "request_idempotency_conflict", "Idempotency anahtarı farklı bir işlem için kullanılmış.");
                using var replay = JsonDocument.Parse(previous.ResultJson);
                return Ok(replay.RootElement.Clone());
            }

            await using var transaction = _db.Database.IsRelational()
                ? await _db.Database.BeginTransactionAsync(System.Data.IsolationLevel.Serializable, ct) : null;
            if (_db.Database.ProviderName?.Contains("Npgsql", StringComparison.OrdinalIgnoreCase) == true)
                await _db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtext({id.ToString()}))", ct);

            var sr = await AuthorizedRequest(id, ct);
            if (sr == null) return Error(404, "request_not_found", "Talep bulunamadı.");
            if (!from.Contains(sr.Status))
                return Error(409, "request_invalid_transition", "Talep bu durumdan ilerletilemez.");
            if ((acceptReschedule || rejectReschedule) && sr.RescheduleRequestedByRole == role)
                return Error(403, "request_forbidden", "Yeniden planlamayı karşı taraf sonuçlandırmalıdır.");

            if (proposedStart != null)
            {
                var duration = sr.ScheduledEndTime - sr.RequestedTime;
                var proposedEnd = proposedStart.Value.Add(duration);
                if (!InsideWorkingHours(sr.BarberProfile.WorkingHours, proposedStart.Value, proposedEnd))
                    return Error(409, "request_reschedule_invalid", "Önerilen zaman çalışma saatleri dışında.");
                if (await _db.ServiceRequests.AsNoTracking().AnyAsync(r => r.Id != id && r.BarberProfileId == sr.BarberProfileId
                    && BlockingStatuses.Contains(r.Status) && r.RequestedTime < proposedEnd && r.ScheduledEndTime > proposedStart, ct))
                    return Error(409, "request_reschedule_conflict", "Önerilen zaman başka bir taleple çakışıyor.");
            }

            var old = sr.Status;
            var now = DateTime.UtcNow;
            if (proposedStart != null)
            {
                sr.PreviousRequestedTime = sr.RequestedTime;
                sr.ProposedStartAt = proposedStart;
                sr.RescheduleRequestedByRole = role;
            }
            if (acceptReschedule && sr.ProposedStartAt != null)
            {
                var duration = sr.ScheduledEndTime - sr.RequestedTime;
                sr.RequestedTime = sr.ProposedStartAt.Value;
                sr.ScheduledEndTime = sr.RequestedTime.Add(duration);
                sr.ProposedStartAt = null;
                sr.RescheduleRequestedByRole = null;
            }
            if (rejectReschedule)
            {
                sr.ProposedStartAt = null;
                sr.RescheduleRequestedByRole = null;
            }
            sr.Status = to;
            sr.UpdatedAt = now;
            sr.Version = Guid.NewGuid();
            if (to is RequestStatus.Accepted or RequestStatus.Rejected) sr.RespondedAt = now;
            if (to == RequestStatus.OnTheWay) sr.OnTheWayAt = now;
            if (to == RequestStatus.Started) sr.StartedAt = now;
            if (to == RequestStatus.Completed) sr.CompletedAt = now;
            if (to == RequestStatus.Cancelled)
            {
                sr.CancelledAt = now;
                sr.CancellationReasonCode = reasonCode;
                sr.CancellationReasonText = reasonText;
                sr.CancelledByRole = role;
            }
            var history = new RequestStatusHistory { Id = Guid.NewGuid(), RequestId = id, FromStatus = old,
                ToStatus = to, ChangedByUserId = userId, ChangedByRole = role, ReasonCode = reasonCode,
                ReasonText = reasonText, CreatedAt = now };
            _db.RequestStatusHistories.Add(history);
            var resultJson = JsonSerializer.Serialize(new { requestId = id, status = to.ToString(), timelineId = history.Id });
            _db.RequestOperations.Add(new RequestOperation { Id = Guid.NewGuid(), UserId = userId,
                IdempotencyKey = key!, PayloadHash = payloadHash, RequestId = id, ResultJson = resultJson, CreatedAt = now });
            await EnqueueRequestUpdatedBoth(sr, ct);
            var timelinePayload = new { requestId = id, timelineId = history.Id };
            await _notifier.EnqueueAsync(sr.ClientUserId, "RequestTimelineUpdated", timelinePayload, ct);
            await _notifier.EnqueueAsync(sr.BarberProfile.UserId, "RequestTimelineUpdated", timelinePayload, ct);
            try { await _db.SaveChangesAsync(ct); }
            catch (DbUpdateConcurrencyException) { return Error(409, "request_concurrency_conflict", "Talep eşzamanlı güncellendi."); }
            catch (DbUpdateException) { return Error(409, "request_concurrency_conflict", "Talep eşzamanlı işlendi."); }
            if (transaction != null) await transaction.CommitAsync(ct);

            using var result = JsonDocument.Parse(resultJson);
            return Ok(result.RootElement.Clone());
        }
        finally { gate.Release(); }
    }

    private async Task EnqueueRequestUpdatedBoth(ServiceRequest sr, CancellationToken ct)
    {
        var payload = new { requestId = sr.Id, status = sr.Status.ToString() };
        await _notifier.EnqueueAsync(sr.ClientUserId, "RequestUpdated", payload, ct);
        await _notifier.EnqueueAsync(sr.BarberProfile.UserId, "RequestUpdated", payload, ct);
    }

    private async Task<ServiceRequestDto> ToDtoAsync(Guid id, CancellationToken ct)
    {
        var sr = await _db.ServiceRequests
            .Include(r => r.Items)
            .Include(r => r.BarberProfile).ThenInclude(b => b.User)
            .Include(r => r.ClientUser)
            .FirstAsync(r => r.Id == id, ct);
        return ToDto(sr, User.GetUserId(), new Dictionary<Guid, int>());
    }

    private static ServiceRequestDto ToDto(
        ServiceRequest r, Guid currentUserId, IReadOnlyDictionary<Guid, int> myRatings)
    {
        var rated = myRatings.TryGetValue(r.Id, out var myScore);
        var tracking = r.Status is RequestStatus.OnTheWay or RequestStatus.Started;
        return new ServiceRequestDto(
            r.Id,
            r.BarberProfileId,
            r.BarberProfile.BusinessName ?? r.BarberProfile.User.FirstName,
            $"{r.ClientUser.FirstName} {r.ClientUser.LastName}".Trim(),
            r.ClientUser.PhoneNumber,
            r.BarberProfile.User.PhoneNumber,
            r.Status,
            r.RequestedTime,
            r.ClientLocation?.Y,
            r.ClientLocation?.X,
            r.AddressNote,
            r.TotalPrice,
            r.Items.Select(i => new RequestItemDto(i.ServiceName, i.PriceAtRequest)).ToList(),
            r.CreatedAt,
            r.OnTheWayAt,
            r.StartedAt,
            r.CompletedAt,
            tracking ? r.BarberProfile.Location?.Y : null,
            tracking ? r.BarberProfile.Location?.X : null,
            r.Status == RequestStatus.Completed && !rated,
            rated ? myScore : null,
            r.ClientAddressId,
            r.AddressSnapshot,
            r.ClientLocation == null ? "business" : "customerAddress",
            r.UpdatedAt,
            r.Version,
            r.RespondedAt,
            r.CancelledAt,
            r.CancelledAt == null ? null : new { reasonCode = r.CancellationReasonCode, reasonText = r.CancellationReasonText, cancelledByRole = r.CancelledByRole, cancelledAt = r.CancelledAt },
            r.ProposedStartAt == null ? null : new { proposedStartAt = r.ProposedStartAt, requestedByRole = r.RescheduleRequestedByRole });
    }
}
