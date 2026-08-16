using Berbergelsin.Api.Auth;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Dtos;
using Berbergelsin.Api.Entities;
using Berbergelsin.Api.Enums;
using Berbergelsin.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NetTopologySuite.Geometries;
using System.Text.Json;

namespace Berbergelsin.Api.Controllers;

[ApiController]
[Route("api/barbers")]
[Authorize]
public class BarbersController : ControllerBase
{
    private static readonly GeometryFactory Geo = new(new PrecisionModel(), 4326);
    private static readonly HashSet<string> NewDiscoveryParameters = new(StringComparer.OrdinalIgnoreCase)
    { "radiusKm", "serviceId", "minPrice", "maxPrice", "minRating", "serviceMode", "availableAt", "sort", "page", "pageSize" };
    private static readonly string[] ServiceCategories =
    [
        "Tesisat",
        "Elektrik",
        "Tamir & Bakım",
        "Temizlik",
        "Nakliye",
        "Oto Servis",
        "Kuaför & Güzellik",
        "Sağlık & Bakım",
        "Özel Ders",
        "Organizasyon",
        "Evcil Hayvan",
        "Bahçe & Peyzaj",
        "Bilgisayar & Teknik Servis",
        "Beyaz Eşya",
        "İnşaat & Tadilat",
        "Diğer"
    ];

    private readonly AppDbContext _db;
    private readonly RealtimeNotifier _notifier;
    private readonly FileStorageService _fileStorage;

    public BarbersController(AppDbContext db, RealtimeNotifier notifier, FileStorageService fileStorage)
    {
        _db = db;
        _notifier = notifier;
        _fileStorage = fileStorage;
    }

    [HttpGet("categories")]
    [AllowAnonymous]
    public async Task<IActionResult> Categories(CancellationToken ct)
    {
        var items = await _db.ServiceCategories
            .Include(c => c.Group)
            .OrderBy(c => c.Group.SortOrder).ThenBy(c => c.SortOrder)
            .Select(c => c.Name)
            .Distinct()
            .ToListAsync(ct);
        return Ok(items.Count > 0 ? items : ServiceCategories);
    }

    [HttpGet("nearby")]
    [Authorize(Roles = "Musteri")]
    [EnableRateLimiting("discovery")]
    public async Task<IActionResult> Nearby([FromQuery] NearbyDiscoveryQuery request, CancellationToken ct)
    {
        var validation = ValidateDiscoveryQuery(request);
        if (validation != null) return BadRequest(validation);

        var client = Geo.CreatePoint(new Coordinate(request.Lng!.Value, request.Lat!.Value));
        var radiusKm = request.RadiusKm ?? 30;
        var pageSize = Math.Min(request.PageSize, 50);
        var q = NormalizeSearch(request.Q);
        var category = NormalizeSearch(request.Category);
        var city = NormalizeSearch(request.City);
        var district = NormalizeSearch(request.District);
        var neighborhood = NormalizeSearch(request.Neighborhood);
        var serviceMode = NormalizeDiscoveryServiceMode(request.ServiceMode);

        IQueryable<BarberProfile> query = _db.BarberProfiles.AsNoTracking();
        if (request.AvailableAt.HasValue)
        {
            var local = TimeZoneInfo.ConvertTime(request.AvailableAt.Value, GetTurkeyTimeZone());
            var day = local.DayOfWeek == DayOfWeek.Sunday ? 7 : (int)local.DayOfWeek;
            var time = local.TimeOfDay;
            query = _db.BarberProfiles.FromSqlInterpolated($$"""
                SELECT b.* FROM "BarberProfiles" AS b
                WHERE EXISTS (
                    SELECT 1 FROM jsonb_array_elements(b."WorkingHours") AS wh
                    WHERE COALESCE((COALESCE(wh->>'closed', wh->>'Closed'))::boolean, false) = false
                      AND COALESCE(wh->>'day', wh->>'Day')::integer = {{day}}
                      AND COALESCE(wh->>'open', wh->>'Open')::time <= {{time}}
                      AND COALESCE(wh->>'close', wh->>'Close')::time > {{time}})
                """).AsNoTracking();
        }
        query = query
            .Where(b => b.Status == BarberStatus.Approved && b.IsOnline && b.Location != null)
            .Where(b => b.User.AccountStatus == AccountStatus.Active && b.User.OnboardingCompleted)
            .Where(b => b.Location!.IsWithinDistance(client, radiusKm * 1000.0)
                     && b.Location!.IsWithinDistance(client, b.ServiceRadiusKm * 1000.0));

        if (category != null) query = query.Where(b => b.Category != null && EF.Functions.ILike(b.Category, category, "\\"));
        if (city != null) query = query.Where(b => b.City != null && EF.Functions.ILike(b.City, city, "\\"));
        if (district != null) query = query.Where(b => b.District != null && EF.Functions.ILike(b.District, district, "\\"));
        if (neighborhood != null) query = query.Where(b => b.Neighborhood != null && EF.Functions.ILike(b.Neighborhood, neighborhood, "\\"));
        if (serviceMode != null) query = query.Where(b => b.ServiceMode == serviceMode || b.ServiceMode == "Both");
        if (request.ServiceId.HasValue || request.MinPrice.HasValue || request.MaxPrice.HasValue)
            query = query.Where(b => b.Services.Any(s => s.IsActive
                && (!request.ServiceId.HasValue || s.Id == request.ServiceId.Value || s.ServiceDefinitionId == request.ServiceId.Value)
                && (!request.MinPrice.HasValue || s.Price >= request.MinPrice.Value)
                && (!request.MaxPrice.HasValue || s.Price <= request.MaxPrice.Value)));
        if (q != null)
            query = query.Where(b =>
                (b.BusinessName != null && EF.Functions.ILike(b.BusinessName, q, "\\")) ||
                (b.Category != null && EF.Functions.ILike(b.Category, q, "\\")) ||
                (b.City != null && EF.Functions.ILike(b.City, q, "\\")) ||
                (b.District != null && EF.Functions.ILike(b.District, q, "\\")) ||
                (b.Neighborhood != null && EF.Functions.ILike(b.Neighborhood, q, "\\")) ||
                b.Services.Any(s => s.IsActive && EF.Functions.ILike(s.Name, q, "\\")));
        if (request.MinRating.HasValue)
            query = query.Where(b => (_db.Ratings.Where(r => r.RatedUserId == b.UserId && !r.IsDeleted && r.ModerationStatus == RatingModerationStatus.Visible)
                .Average(r => (double?)r.Score) ?? 0) >= request.MinRating.Value);

        var shaped = query.Select(b => new
        {
            b.Id, b.BusinessName, b.User.FirstName, b.Category, b.Description, b.ServiceMode,
            b.City, b.District, b.Neighborhood, b.Location, b.AcceptsOffers, b.AcceptsUrgentRequests,
            b.ServiceRadiusKm, b.WorkingHours,
            HasLogo = b.LogoFileName != null,
            CoverPhotoId = b.Photos.Where(p => p.IsCover).OrderBy(p => p.SortOrder).Select(p => (Guid?)p.Id).FirstOrDefault(),
            Distance = b.Location!.Distance(client),
            Rating = _db.Ratings.Where(r => r.RatedUserId == b.UserId && !r.IsDeleted && r.ModerationStatus == RatingModerationStatus.Visible).Average(r => (double?)r.Score),
            RatingCount = _db.Ratings.Count(r => r.RatedUserId == b.UserId && !r.IsDeleted && r.ModerationStatus == RatingModerationStatus.Visible),
            ServiceCount = b.Services.Count(s => s.IsActive),
            MinimumPrice = b.Services.Where(s => s.IsActive).Min(s => (decimal?)s.Price),
            TopServices = b.Services.Where(s => s.IsActive).OrderByDescending(s => s.IsPopular).ThenBy(s => s.Price)
                .Select(s => new { s.Name, s.Price }).Take(2).ToList()
        }).AsSplitQuery();

        var totalCount = await shaped.CountAsync(ct);
        var ordered = (request.Sort?.Trim().ToLowerInvariant() ?? "distance") switch
        {
            "rating" => shaped.OrderByDescending(x => x.Rating ?? 0).ThenBy(x => x.Distance).ThenBy(x => x.Id),
            "price_asc" => shaped.OrderBy(x => x.MinimumPrice == null).ThenBy(x => x.MinimumPrice).ThenBy(x => x.Distance).ThenBy(x => x.Id),
            "price_desc" => shaped.OrderBy(x => x.MinimumPrice == null).ThenByDescending(x => x.MinimumPrice).ThenBy(x => x.Distance).ThenBy(x => x.Id),
            "relevance" => shaped.OrderByDescending(x => q != null && x.BusinessName != null && EF.Functions.ILike(x.BusinessName, q, "\\"))
                .ThenBy(x => x.Distance).ThenByDescending(x => x.Rating ?? 0).ThenBy(x => x.Id),
            _ => shaped.OrderBy(x => x.Distance).ThenByDescending(x => x.Rating ?? 0).ThenBy(x => x.Id)
        };
        var rows = await ordered.Skip((request.Page - 1) * pageSize).Take(pageSize).ToListAsync(ct);

        var usesPagedContract = Request.Query.Keys.Any(k => NewDiscoveryParameters.Contains(k));
        if (!usesPagedContract)
            return Ok(rows.Select(r => new NearbyBarberDto(
                r.Id, r.BusinessName, r.FirstName, r.Category, r.Description, r.ServiceMode, r.City, r.District,
                r.Neighborhood, r.Location!.Y, r.Location.X, r.AcceptsOffers, r.AcceptsUrgentRequests, r.Distance,
                r.Rating.HasValue ? Math.Round(r.Rating.Value, 1) : null, r.RatingCount, r.HasLogo,
                r.CoverPhotoId == null ? null : $"/api/barbers/{r.Id}/photos/{r.CoverPhotoId}")));

        var now = TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, GetTurkeyTimeZone());
        var items = rows.Select(r => new DiscoveryBarberDto(
            r.Id, r.BusinessName ?? r.FirstName, r.Description, r.Category, r.District, r.City, r.Neighborhood, Math.Round(r.Distance / 1000.0, 2),
            r.Rating.HasValue ? Math.Round(r.Rating.Value, 1) : null, r.RatingCount,
            r.CoverPhotoId == null ? null : $"/api/barbers/{r.Id}/photos/{r.CoverPhotoId}",
            r.HasLogo ? $"/api/barbers/{r.Id}/logo" : null, r.ServiceCount, r.MinimumPrice,
            true, r.ServiceRadiusKm,
            r.Location?.Y ?? 0, r.Location?.X ?? 0,
            r.TopServices?.Select(s => new TopServiceDto(s.Name, s.Price)).ToList())).ToList();
        return Ok(new DiscoveryPageDto<DiscoveryBarberDto>(items, request.Page, pageSize, totalCount,
            request.Page * pageSize < totalCount));
    }

    [HttpGet("{id:guid}")]
    [Authorize(Roles = "Musteri,Berber")]
    public async Task<IActionResult> Detail(Guid id, CancellationToken ct)
    {
        if (User.IsInRole(UserRole.Berber.ToString()) && User.GetBarberProfileId() != id)
            return Forbid();

        var b = await _db.BarberProfiles.AsNoTracking().Include(x => x.User)
            .FirstOrDefaultAsync(x => x.Id == id && x.Status == BarberStatus.Approved && x.IsOnline
                && x.User.AccountStatus == AccountStatus.Active && x.User.OnboardingCompleted, ct);
        if (b == null) return NotFound();

        var currentUserId = User.GetUserId();
        var allRatings = await _db.Ratings
            .Where(r => r.RatedUserId == b.UserId && !r.IsDeleted && r.ModerationStatus == RatingModerationStatus.Visible)
            .OrderByDescending(r => r.CreatedAt)
            .Select(r => new {
                r.RaterUserId,
                RaterName = (!string.IsNullOrEmpty(r.RaterUser.FirstName) ? r.RaterUser.FirstName!.Substring(0,1) : "M") + "***",
                r.Score, r.Comment, r.CreatedAt, r.UpdatedAt, r.Id,
                r.RaterUser.ProfileImageUrl
            })
            .ToListAsync(ct);

        // Müşteri bazında birleştirilmiş rating istatistikleri
        var uniqueRaters = allRatings.Select(r => r.RaterUserId).Distinct().Count();
        var ratingAvg = allRatings.Count > 0 ? allRatings.Average(r => (double)r.Score) : (double?)null;

        var reviews = allRatings
            .GroupBy(r => r.RaterUserId)
            .Select(g => new ReviewDto(
                (int)Math.Round(g.Average(r => r.Score)),
                g.OrderByDescending(r => r.CreatedAt).First().Comment,
                g.First().RaterName,
                g.Max(r => r.CreatedAt),
                g.OrderByDescending(r => r.CreatedAt).First().Id,
                g.Max(r => r.UpdatedAt) ?? g.Max(r => r.CreatedAt),
                g.First().RaterName,
                g.First().ProfileImageUrl,
                g.Key == currentUserId
            ))
            .OrderByDescending(r => r.CreatedAt)
            .Take(10)
            .ToList();

        var services = await _db.BarberServices.AsNoTracking()
            .Where(s => s.BarberProfileId == id && s.IsActive)
            .OrderBy(s => s.SortOrder).ThenBy(s => s.Name).ThenBy(s => s.Id)
            .Select(s => new BarberServiceDto(s.Id, s.Name, s.Price, s.Description,
                s.PriceType, s.DurationMinutes, s.IsPopular)).ToListAsync(ct);
        var photos = await _db.BusinessPhotos.AsNoTracking().Where(p => p.BarberProfileId == id)
            .OrderByDescending(p => p.IsCover).ThenBy(p => p.SortOrder).ThenBy(p => p.Id)
            .Select(p => new BusinessPhotoDto(p.Id, $"/api/barbers/{id}/photos/{p.Id}",
                p.Caption, p.IsCover, p.SortOrder)).ToListAsync(ct);
        var coverImageUrl = photos.FirstOrDefault(p => p.IsCover)?.Url;
        var now = TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, GetTurkeyTimeZone());

        return Ok(new BarberDetailDto(
            b.Id, b.BusinessName, b.User.FirstName, b.User.LastName,
            b.Category, b.Description, b.ServiceMode,
            b.City, b.District, b.Neighborhood, b.AddressLine,
            b.WorkingHours, b.AcceptsOffers, b.AcceptsUrgentRequests,
            services,
            photos,
            b.Location?.Y,
            b.Location?.X,
            ratingAvg.HasValue ? Math.Round(ratingAvg.Value, 1) : null,
            uniqueRaters,
            b.LogoFileName != null,
            reviews,
            coverImageUrl,
            b.LogoFileName == null ? null : $"/api/barbers/{id}/logo",
            true,
            b.ServiceRadiusKm));
    }

    [HttpGet("{id:guid}/reviews")]
    [Authorize(Roles = "Musteri,Berber")]
    public async Task<IActionResult> Reviews(Guid id, [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20, CancellationToken ct = default)
    {
        if (page < 1 || pageSize < 1)
            return BadRequest(new { code = "barber_reviews_invalid_query" });
        pageSize = Math.Min(pageSize, 50);
        var target = await VisibleBarberAsync(id, ct);
        if (target == null) return NotFound();
        if (User.IsInRole(UserRole.Berber.ToString()) && User.GetBarberProfileId() != id) return Forbid();

        var currentUserId = User.GetUserId();
        var allData = await _db.Ratings.AsNoTracking()
            .Where(r => r.RatedUserId == target.Value.UserId && !r.IsDeleted && r.ModerationStatus == RatingModerationStatus.Visible)
            .OrderByDescending(r => r.CreatedAt)
            .Select(r => new { r.RaterUserId, RaterName = (!string.IsNullOrEmpty(r.RaterUser.FirstName) ? r.RaterUser.FirstName!.Substring(0,1) : "M") + "***", r.Score, r.Comment, r.CreatedAt, r.UpdatedAt, r.Id, r.RaterUser.ProfileImageUrl })
            .ToListAsync(ct);
        // Müşteri bazında birleştir
        var grouped = allData.GroupBy(r => r.RaterUserId).Select(g => new ReviewDto(
            (int)Math.Round(g.Average(r => r.Score)),
            g.OrderByDescending(r => r.CreatedAt).First().Comment,
            g.First().RaterName, g.Max(r => r.CreatedAt),
            g.OrderByDescending(r => r.CreatedAt).First().Id,
            g.Max(r => r.UpdatedAt) ?? g.Max(r => r.CreatedAt),
            g.First().RaterName, g.First().ProfileImageUrl,
            g.Key == currentUserId
        )).OrderByDescending(r => r.CreatedAt).ToList();
        var total = grouped.Count;
        var average = grouped.Count > 0 ? grouped.Average(r => (double)r.Score) : (double?)null;
        var items = grouped.Skip((page - 1) * pageSize).Take(pageSize).ToList();
        return Ok(new BarberReviewsPageDto(items, page, pageSize, total,
            page * pageSize < total, average.HasValue ? Math.Round(average.Value, 1) : null));
    }

    [HttpGet("{id:guid}/availability-summary")]
    [Authorize(Roles = "Musteri,Berber")]
    public async Task<IActionResult> AvailabilitySummary(Guid id, [FromQuery] DateOnly? date,
        CancellationToken ct)
    {
        if (!date.HasValue) return BadRequest(new { code = "barber_availability_invalid_date" });
        var target = await VisibleBarberAsync(id, ct);
        if (target == null) return NotFound();
        if (User.IsInRole(UserRole.Berber.ToString()) && User.GetBarberProfileId() != id) return Forbid();
        var intervals = WorkingIntervalsFor(target.Value.WorkingHours, date.Value);
        var localNow = TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, GetTurkeyTimeZone());
        var isToday = DateOnly.FromDateTime(localNow.DateTime) == date.Value;
        return Ok(new BarberAvailabilitySummaryDto(id, date.Value, "Europe/Istanbul",
            intervals.Count > 0, isToday, intervals,
            "working_hours_only"));
    }

    [HttpGet("{id:guid}/photos/{photoId:guid}")]
    [AllowAnonymous]
    public async Task<IActionResult> Photo(Guid id, Guid photoId, CancellationToken ct)
    {
        var photo = await _db.BusinessPhotos
            .FirstOrDefaultAsync(p => p.Id == photoId && p.BarberProfileId == id, ct);
        if (photo == null) return NotFound();

        var stream = _fileStorage.OpenRead(photo.StoredFileName);
        if (stream == null) return NotFound();
        return File(stream, photo.ContentType);
    }

    /// <summary>İşletme logosu (müşteri ve işletme erişebilir).</summary>
    [HttpGet("{id:guid}/logo")]
    [AllowAnonymous]
    public async Task<IActionResult> Logo(Guid id, CancellationToken ct)
    {
        var b = await _db.BarberProfiles.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (b?.LogoFileName == null) return NotFound();

        var stream = _fileStorage.OpenRead(b.LogoFileName);
        if (stream == null) return NotFound();

        var contentType = b.LogoFileName.EndsWith(".png") ? "image/png" : "image/jpeg";
        return File(stream, contentType);
    }

    [HttpPost("me/logo")]
    [Authorize(Roles = "Berber")]
    [RequestSizeLimit(12_000_000)]
    public async Task<IActionResult> UploadLogo([FromForm] IFormFile file, CancellationToken ct)
    {
        if (!file.ContentType.StartsWith("image/"))
            return BadRequest(new { message = "Logo yalnızca JPG veya PNG olabilir." });

        var barberProfileId = User.GetBarberProfileId();
        var b = await _db.BarberProfiles.FirstOrDefaultAsync(x => x.Id == barberProfileId, ct);
        if (b == null) return NotFound();

        try
        {
            var (storedFileName, _, _) = await _fileStorage.SaveAsync(file, ct);
            if (!string.IsNullOrWhiteSpace(b.LogoFileName))
            {
                try { _fileStorage.Delete(b.LogoFileName); } catch { /* Silinmezse devam et */ }
            }
            b.LogoFileName = storedFileName;
            await _db.SaveChangesAsync(ct);
        }
        catch (FileValidationException ex)
        {
            return BadRequest(new { message = ex.Message });
        }

        return Ok(new { message = "Logo güncellendi." });
    }

    [HttpDelete("me/logo")]
    [Authorize(Roles = "Berber")]
    public async Task<IActionResult> DeleteLogo(CancellationToken ct)
    {
        var barberProfileId = User.GetBarberProfileId();
        var b = await _db.BarberProfiles.FirstOrDefaultAsync(x => x.Id == barberProfileId, ct);
        if (b == null) return NotFound();
        if (string.IsNullOrWhiteSpace(b.LogoFileName))
            return NotFound(new { message = "Logo bulunamadı." });

        try { _fileStorage.Delete(b.LogoFileName); } catch { /* Silinmezse devam et */ }
        b.LogoFileName = null;
        await _db.SaveChangesAsync(ct);
        return Ok(new { message = "Logo kaldırıldı." });
    }

    [HttpPut("me/online")]
    [Authorize(Roles = "Berber")]
    public async Task<IActionResult> SetOnline(UpdateOnlineRequest request, CancellationToken ct)
    {
        var b = await GetOwnApprovedProfileAsync(ct);
        if (b == null) return BadRequest(new { message = "Hesabınız henüz onaylanmadı." });

        b.IsOnline = request.IsOnline;
        await _db.SaveChangesAsync(ct);
        await _notifier.ToMapWatchersAsync("BarberOnlineChanged",
            new { barberProfileId = b.Id, isOnline = b.IsOnline });
        return Ok(new { message = b.IsOnline ? "Çevrimiçi oldunuz." : "Çevrimdışı oldunuz." });
    }

    [HttpPut("me/location")]
    [Authorize(Roles = "Berber")]
    public async Task<IActionResult> UpdateLocation(UpdateLocationRequest request, CancellationToken ct)
    {
        if (request.Lat is < -90 or > 90 || request.Lng is < -180 or > 180)
            return BadRequest(new { message = "Geçersiz konum." });

        var b = await GetOwnApprovedProfileAsync(ct);
        if (b == null) return BadRequest(new { message = "Hesabınız henüz onaylanmadı." });

        b.Location = Geo.CreatePoint(new Coordinate(request.Lng, request.Lat));
        b.LastLocationAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);

        if (b.IsOnline)
            await _notifier.ToMapWatchersAsync("BarberLocationUpdated",
                new { barberProfileId = b.Id, lat = request.Lat, lng = request.Lng });
        return Ok(new { message = "Konum güncellendi." });
    }

    [HttpGet("me/profile")]
    [Authorize(Roles = "Berber")]
    public async Task<IActionResult> MyProfile(CancellationToken ct)
    {
        var barberProfileId = User.GetBarberProfileId();
        var b = await _db.BarberProfiles
            .Include(x => x.User).Include(x => x.Services).Include(x => x.Photos).Include(x => x.Documents)
            .FirstOrDefaultAsync(x => x.Id == barberProfileId, ct);
        if (b == null) return NotFound();

        var ratingStats = await _db.Ratings
            .Where(r => r.RatedUserId == b.UserId)
            .GroupBy(r => 1)
            .Select(g => new { Avg = g.Average(r => (double)r.Score), Count = g.Count() })
            .FirstOrDefaultAsync(ct);

        var coverPhoto = b.Photos.FirstOrDefault(p => p.IsCover);
        return Ok(new BarberProfileDto(
            BarberProfileId: b.Id,
            BusinessName: b.BusinessName,
            Category: b.Category,
            Description: b.Description,
            ServiceMode: b.ServiceMode ?? "Mobile",
            City: b.City,
            District: b.District,
            Neighborhood: b.Neighborhood,
            AddressLine: b.AddressLine,
            FirstName: b.User.FirstName,
            LastName: b.User.LastName,
            Status: b.Status.ToString(),
            RejectionReason: b.RejectionReason,
            SharePhone: b.SharePhone,
            AcceptsOffers: b.AcceptsOffers,
            AcceptsUrgentRequests: b.AcceptsUrgentRequests,
            ServiceRadiusKm: b.ServiceRadiusKm,
            IsOnline: b.IsOnline,
            WorkingHours: b.WorkingHours,
            Lat: b.Location?.Y,
            Lng: b.Location?.X,
            Photos: b.Photos.OrderByDescending(p => p.IsCover).ThenBy(p => p.SortOrder).Select(ToPhotoDto).ToList(),
            Services: b.Services.Where(s => s.IsActive).OrderBy(s => s.SortOrder).Select(ToServiceDto).ToList(),
            PhoneNumber: b.User.PhoneNumber,
            Email: b.User.Email,
            LogoUrl: b.LogoFileName == null ? null : $"/api/barbers/{b.Id}/logo",
            CoverPhotoUrl: coverPhoto == null ? null : $"/api/barbers/{b.Id}/photos/{coverPhoto.Id}",
            AvgRating: ratingStats?.Avg != null ? Math.Round(ratingStats.Avg, 1) : null,
            RatingCount: ratingStats?.Count ?? 0,
            HasLogo: b.LogoFileName != null
        ));
    }

    /// <summary>Oturum açmış işletmenin aldığı yorumları sayfalı ve filtrelenebilir döndürür.</summary>
    [HttpGet("me/reviews")]
    [Authorize(Roles = "Berber")]
    public async Task<IActionResult> MyReviews(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] int? rating = null,
        CancellationToken ct = default)
    {
        if (page < 1)
            return BadRequest(new { message = "Sayfa numarası en az 1 olmalıdır." });
        if (pageSize is < 1 or > 50)
            return BadRequest(new { message = "Sayfa boyutu 1-50 aralığında olmalıdır." });
        if (rating is < 1 or > 5)
            return BadRequest(new { message = "Puan filtresi 1-5 aralığında olmalıdır." });

        var barberProfileId = User.GetBarberProfileId();
        if (barberProfileId == null) return Forbid();

        var barberUserId = await _db.BarberProfiles
            .AsNoTracking()
            .Where(b => b.Id == barberProfileId)
            .Select(b => (Guid?)b.UserId)
            .FirstOrDefaultAsync(ct);
        if (barberUserId == null) return NotFound();

        var ownRatings = _db.Ratings
            .AsNoTracking()
            .Where(r => r.RatedUserId == barberUserId.Value);

        var summaryRows = await ownRatings
            .GroupBy(r => r.Score)
            .Select(g => new { Rating = g.Key, Count = g.Count(), Sum = g.Sum(r => r.Score) })
            .ToListAsync(ct);
        var totalCount = summaryRows.Sum(x => x.Count);
        var averageRating = totalCount == 0
            ? 0
            : Math.Round((double)summaryRows.Sum(x => x.Sum) / totalCount, 1);
        var distribution = Enumerable.Range(1, 5)
            .ToDictionary(score => score, score => summaryRows.FirstOrDefault(x => x.Rating == score)?.Count ?? 0);

        var filteredRatings = rating == null
            ? ownRatings
            : ownRatings.Where(r => r.Score == rating.Value);
        var filteredCount = await filteredRatings.CountAsync(ct);
        var totalPages = filteredCount == 0 ? 0 : (int)Math.Ceiling((double)filteredCount / pageSize);

        var items = await filteredRatings
            .OrderByDescending(r => r.CreatedAt)
            .ThenByDescending(r => r.Id)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(r => new BusinessReviewItemDto(
                r.Id,
                r.Score,
                r.Comment,
                r.CreatedAt,
                string.IsNullOrWhiteSpace(r.RaterUser.FirstName) ? "Müşteri" : r.RaterUser.FirstName,
                null,
                r.ServiceRequest.Items.OrderBy(i => i.Id).Select(i => i.ServiceName).FirstOrDefault(),
                r.ServiceRequestId))
            .ToListAsync(ct);

        return Ok(new BusinessReviewsPageDto(
            items,
            page,
            pageSize,
            filteredCount,
            totalPages,
            new BusinessReviewsSummaryDto(averageRating, totalCount, distribution)));
    }
    [HttpGet("me/dashboard")]
    [Authorize(Roles = "Berber")]
    public async Task<IActionResult> MyDashboard(CancellationToken ct)
    {
        var barberProfileId = User.GetBarberProfileId();
        var b = await _db.BarberProfiles
            .Include(x => x.User)
            .Include(x => x.Documents)
            .FirstOrDefaultAsync(x => x.Id == barberProfileId, ct);
        if (b == null) return NotFound();

        var now = DateTimeOffset.UtcNow;
        var todayStart = new DateTimeOffset(now.Year, now.Month, now.Day, 0, 0, 0, TimeSpan.Zero);
        var weekStart = todayStart.AddDays(-6);

        var requests = await _db.ServiceRequests
            .Include(r => r.Items)
            .Where(r => r.BarberProfileId == b.Id)
            .ToListAsync(ct);
        var offers = await _db.PriceOffers
            .Where(o => o.BarberProfileId == b.Id)
            .ToListAsync(ct);
        var ratingStats = await _db.Ratings
            .Where(r => r.RatedUserId == b.UserId)
            .GroupBy(r => 1)
            .Select(g => new { Avg = g.Average(r => (double)r.Score), Count = g.Count() })
            .FirstOrDefaultAsync(ct);

        var completed = requests.Where(r => r.Status == RequestStatus.Completed).ToList();
        var todayCompleted = completed.Where(r => (r.CompletedAt ?? r.RequestedTime.DateTime) >= todayStart.UtcDateTime).ToList();
        var weekCompleted = completed.Where(r => (r.CompletedAt ?? r.RequestedTime.DateTime) >= weekStart.UtcDateTime).ToList();
        var topService = completed
            .SelectMany(r => r.Items)
            .GroupBy(i => i.ServiceName)
            .Select(g => new { Name = g.Key, Count = g.Count() })
            .OrderByDescending(x => x.Count)
            .FirstOrDefault();

        var uniqueCustomers = completed.Select(r => r.ClientUserId).Distinct().Count();
        var activeStatuses = new[] { RequestStatus.Accepted, RequestStatus.OnTheWay, RequestStatus.Started };
        var responseMinutes = requests
            .Where(r => r.RespondedAt != null)
            .Select(r => (r.RespondedAt!.Value - r.CreatedAt).TotalMinutes)
            .Concat(offers
                .Where(o => o.RespondedAt != null)
                .Select(o => (o.RespondedAt!.Value - o.CreatedAt).TotalMinutes))
            .Where(minutes => minutes >= 0)
            .ToList();
        var averageResponseMinutes = responseMinutes.Count == 0
            ? 0
            : (int)Math.Ceiling(responseMinutes.Average());
        var weekAnsweredRequestCount = requests.Count(r =>
            r.RespondedAt != null && r.RespondedAt.Value >= weekStart.UtcDateTime);
        var actionableRequestCount = requests.Count(r =>
            r.Status is not RequestStatus.Cancelled and not RequestStatus.Rejected);
        var conversionRate = actionableRequestCount == 0
            ? 0
            : (int)Math.Round((double)completed.Count / actionableRequestCount * 100);

        return Ok(new BusinessDashboardDto(
            TodayRequestCount: requests.Count(r => r.RequestedTime >= todayStart && r.Status is not RequestStatus.Cancelled and not RequestStatus.Rejected),
            PendingRequestCount: requests.Count(r => r.Status == RequestStatus.Pending),
            PendingOfferCount: offers.Count(o => o.Status is OfferStatus.Pending or OfferStatus.Countered),
            ActiveRequestCount: requests.Count(r => activeStatuses.Contains(r.Status)),
            CompletedThisWeek: weekCompleted.Count,
            CompletedTotal: completed.Count,
            TodayRevenue: todayCompleted.Sum(r => r.TotalPrice),
            WeekRevenue: weekCompleted.Sum(r => r.TotalPrice),
            TotalRevenue: completed.Sum(r => r.TotalPrice),
            AvgRating: ratingStats == null ? null : Math.Round(ratingStats.Avg, 1),
            RatingCount: ratingStats?.Count ?? 0,
            UniqueCustomerCount: uniqueCustomers,
            TopServiceName: topService?.Name,
            TopServiceCount: topService?.Count ?? 0,
            AverageResponseMinutes: averageResponseMinutes,
            WeekAnsweredRequestCount: weekAnsweredRequestCount,
            ConversionRate: conversionRate,
            OfferTotalCount: offers.Count
        ));
    }

    [HttpGet("me/customers")]
    [Authorize(Roles = "Berber")]
    public async Task<IActionResult> MyCustomers(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        CancellationToken ct = default)
    {
        var barberProfileId = User.GetBarberProfileId();
        if (barberProfileId == null)
            return Forbid();

        var profileExists = await _db.BarberProfiles
            .AsNoTracking()
            .AnyAsync(b => b.Id == barberProfileId, ct);
        if (!profileExists) return NotFound();

        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);

        var completedRequests = await _db.ServiceRequests
            .AsNoTracking()
            .Include(r => r.ClientUser)
            .Include(r => r.Items)
            .Where(r => r.BarberProfileId == barberProfileId && r.Status == RequestStatus.Completed)
            .ToListAsync(ct);

        var allCustomers = completedRequests
            .GroupBy(r => r.ClientUserId)
            .Select(group =>
            {
                var orderedRequests = group
                    .OrderByDescending(GetVisitDate)
                    .ThenByDescending(r => r.CreatedAt)
                    .ThenBy(r => r.Id)
                    .ToList();
                var firstVisit = group.Min(GetVisitDate);
                var lastVisit = GetVisitDate(orderedRequests[0]);
                var totalSpent = group.Sum(r => r.TotalPrice);
                var completedJobCount = group.Count();
                var displayName = BuildCustomerDisplayName(orderedRequests[0].ClientUser);
                var phone = orderedRequests[0].ClientUser?.PhoneNumber?.Trim();
                if (string.IsNullOrWhiteSpace(phone)) phone = null;
                var preferredServices = group
                    .SelectMany(r => r.Items)
                    .Select(i => i.ServiceName?.Trim())
                    .Where(name => !string.IsNullOrWhiteSpace(name))
                    .GroupBy(name => name!)
                    .OrderByDescending(g => g.Count())
                    .ThenBy(g => g.Key)
                    .Take(3)
                    .Select(g => g.Key)
                    .ToList();
                var recentJobs = orderedRequests
                    .Take(3)
                    .Select(r => new BarberCustomerRecentJobDto(
                        r.Id,
                        GetVisitDate(r),
                        r.TotalPrice,
                        r.Items
                            .Select(i => i.ServiceName?.Trim())
                            .Where(name => !string.IsNullOrWhiteSpace(name))
                            .Select(name => name!)
                            .Distinct()
                            .OrderBy(name => name)
                            .ToList()))
                    .ToList();

                return new BarberCustomerDto(
                    group.Key,
                    displayName,
                    phone,
                    firstVisit,
                    lastVisit,
                    completedJobCount,
                    totalSpent,
                    completedJobCount == 0 ? 0 : totalSpent / completedJobCount,
                    preferredServices,
                    recentJobs);
            })
            .OrderByDescending(c => c.LastVisit)
            .ThenBy(c => c.DisplayName)
            .ThenBy(c => c.CustomerId)
            .ToList();

        var totalCount = allCustomers.Count;
        var items = allCustomers
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToList();

        return Ok(new
        {
            items,
            page,
            pageSize,
            totalCount,
            totalPages = (int)Math.Ceiling((double)totalCount / pageSize),
        });
    }

    [HttpPut("me/profile")]
    [Authorize(Roles = "Berber")]
    public async Task<IActionResult> UpdateProfile(UpdateBarberProfileRequest request, CancellationToken ct)
    {
        if (request.ServiceRadiusKm is < 1 or > 30)
            return BadRequest(new { message = "Hizmet yarıçapı 1-30 km aralığında olmalıdır." });

        var barberProfileId = User.GetBarberProfileId();
        var b = await _db.BarberProfiles.FirstOrDefaultAsync(x => x.Id == barberProfileId, ct);
        if (b == null) return NotFound();

        b.BusinessName = request.BusinessName?.Trim();
        b.Category = NormalizeOptional(request.Category, 80);
        b.Description = NormalizeOptional(request.Description, 1000);
        b.ServiceMode = NormalizeServiceMode(request.ServiceMode);
        b.City = NormalizeOptional(request.City, 80);
        b.District = NormalizeOptional(request.District, 80);
        b.Neighborhood = NormalizeOptional(request.Neighborhood, 120);
        b.AddressLine = NormalizeOptional(request.AddressLine, 300);
        b.SharePhone = request.SharePhone;
        b.AcceptsOffers = request.AcceptsOffers;
        b.AcceptsUrgentRequests = request.AcceptsUrgentRequests;
        b.ServiceRadiusKm = request.ServiceRadiusKm;
        if (request.WorkingHours != null)
            b.WorkingHours = JsonSerializer.Serialize(request.WorkingHours);
        await _db.SaveChangesAsync(ct);
        return Ok(new { message = "Profil güncellendi." });
    }

    [HttpPost("me/services")]
    [Authorize(Roles = "Berber")]
    public async Task<IActionResult> AddService(UpsertServiceRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Name) || request.Price is < 1 or > 100000)
            return BadRequest(new { message = "Geçerli bir hizmet adı ve fiyat girin." });

        var barberProfileId = User.GetBarberProfileId();
        var maxOrder = await _db.BarberServices
            .Where(s => s.BarberProfileId == barberProfileId)
            .Select(s => (int?)s.SortOrder).MaxAsync(ct) ?? -1;
        var profileCategory = await _db.BarberProfiles.Where(x => x.Id == barberProfileId)
            .Select(x => x.Category).FirstOrDefaultAsync(ct);
        var definition = await ServiceCatalogLinker.GetOrCreateAsync(_db, request.Name, profileCategory, ct);

        var service = new BarberService
        {
            Id = Guid.NewGuid(),
            BarberProfileId = barberProfileId!.Value,
            ServiceDefinition = definition,
            Name = request.Name.Trim(),
            Price = request.Price,
            Description = NormalizeOptional(request.Description, 500),
            PriceType = NormalizePriceType(request.PriceType),
            DurationMinutes = request.DurationMinutes is > 0 and <= 1440 ? request.DurationMinutes : null,
            IsPopular = request.IsPopular,
            SortOrder = maxOrder + 1,
            IsActive = true
        };
        _db.BarberServices.Add(service);
        await _db.SaveChangesAsync(ct);
        return Ok(ToServiceDto(service));
    }

    [HttpPut("me/services/{serviceId:guid}")]
    [Authorize(Roles = "Berber")]
    public async Task<IActionResult> UpdateService(Guid serviceId, UpsertServiceRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Name) || request.Price is < 1 or > 100000)
            return BadRequest(new { message = "Geçerli bir hizmet adı ve fiyat girin." });

        var barberProfileId = User.GetBarberProfileId();
        var service = await _db.BarberServices
            .FirstOrDefaultAsync(s => s.Id == serviceId && s.BarberProfileId == barberProfileId && s.IsActive, ct);
        if (service == null) return NotFound();

        var profileCategory = await _db.BarberProfiles.Where(x => x.Id == barberProfileId)
            .Select(x => x.Category).FirstOrDefaultAsync(ct);
        service.ServiceDefinition = await ServiceCatalogLinker.GetOrCreateAsync(_db, request.Name, profileCategory, ct);

        service.Name = request.Name.Trim();
        service.Price = request.Price;
        service.Description = NormalizeOptional(request.Description, 500);
        service.PriceType = NormalizePriceType(request.PriceType);
        service.DurationMinutes = request.DurationMinutes is > 0 and <= 1440 ? request.DurationMinutes : null;
        service.IsPopular = request.IsPopular;
        await _db.SaveChangesAsync(ct);
        return Ok(ToServiceDto(service));
    }

    [HttpPost("me/photos")]
    [Authorize(Roles = "Berber")]
    [RequestSizeLimit(12_000_000)]
    public async Task<IActionResult> UploadPhoto([FromForm] IFormFile file, [FromForm] string? caption, [FromForm] bool isCover, CancellationToken ct)
    {
        if (!file.ContentType.StartsWith("image/"))
            return BadRequest(new { message = "Vitrin fotoğrafı yalnızca JPG veya PNG olabilir." });

        var barberProfileId = User.GetBarberProfileId();
        var b = await _db.BarberProfiles.Include(x => x.Photos).FirstOrDefaultAsync(x => x.Id == barberProfileId, ct);
        if (b == null) return NotFound();
        if (b.Photos.Count >= 12) return BadRequest(new { message = "En fazla 12 vitrin fotoğrafı ekleyebilirsiniz." });

        try
        {
            var (storedFileName, contentType, size) = await _fileStorage.SaveAsync(file, ct);
            if (isCover)
            {
                foreach (var existing in b.Photos) existing.IsCover = false;
            }
            var photo = new BusinessPhoto
            {
                Id = Guid.NewGuid(),
                BarberProfileId = b.Id,
                StoredFileName = storedFileName,
                OriginalFileName = file.FileName,
                ContentType = contentType,
                SizeBytes = size,
                Caption = NormalizeOptional(caption, 160),
                IsCover = isCover || b.Photos.Count == 0,
                SortOrder = b.Photos.Count,
                CreatedAt = DateTime.UtcNow
            };
            _db.BusinessPhotos.Add(photo);
            await _db.SaveChangesAsync(ct);
            return Ok(ToPhotoDto(photo));
        }
        catch (FileValidationException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpPut("me/photos/{photoId:guid}/cover")]
    [Authorize(Roles = "Berber")]
    public async Task<IActionResult> SetCoverPhoto(Guid photoId, CancellationToken ct)
    {
        var barberProfileId = User.GetBarberProfileId();
        var photos = await _db.BusinessPhotos.Where(p => p.BarberProfileId == barberProfileId).ToListAsync(ct);
        var selected = photos.FirstOrDefault(p => p.Id == photoId);
        if (selected == null) return NotFound();

        foreach (var photo in photos) photo.IsCover = photo.Id == photoId;
        await _db.SaveChangesAsync(ct);
        return Ok(new { message = "Kapak fotoğrafı güncellendi." });
    }

    [HttpDelete("me/photos/{photoId:guid}")]
    [Authorize(Roles = "Berber")]
    public async Task<IActionResult> DeletePhoto(Guid photoId, CancellationToken ct)
    {
        var barberProfileId = User.GetBarberProfileId();
        var photo = await _db.BusinessPhotos.FirstOrDefaultAsync(p => p.Id == photoId && p.BarberProfileId == barberProfileId, ct);
        if (photo == null) return NotFound();

        _db.BusinessPhotos.Remove(photo);
        try { _fileStorage.Delete(photo.StoredFileName); } catch { /* Silinmezse devam et */ }
        await _db.SaveChangesAsync(ct);
        return Ok(new { message = "Fotoğraf kaldırıldı." });
    }

    [HttpDelete("me/services/{serviceId:guid}")]
    [Authorize(Roles = "Berber")]
    public async Task<IActionResult> DeleteService(Guid serviceId, CancellationToken ct)
    {
        var barberProfileId = User.GetBarberProfileId();
        var service = await _db.BarberServices
            .FirstOrDefaultAsync(s => s.Id == serviceId && s.BarberProfileId == barberProfileId, ct);
        if (service == null) return NotFound();

        // Geçmiş taleplerde referans olabilir: soft delete
        service.IsActive = false;
        await _db.SaveChangesAsync(ct);
        return Ok(new { message = "Hizmet silindi." });
    }

    private async Task<BarberProfile?> GetOwnApprovedProfileAsync(CancellationToken ct)
    {
        var barberProfileId = User.GetBarberProfileId();
        if (barberProfileId == null) return null;
        return await _db.BarberProfiles
            .FirstOrDefaultAsync(b => b.Id == barberProfileId && b.Status == BarberStatus.Approved, ct);
    }

    private static BarberServiceDto ToServiceDto(BarberService s) =>
        new(s.Id, s.Name, s.Price, s.Description, s.PriceType, s.DurationMinutes, s.IsPopular);

    private BusinessPhotoDto ToPhotoDto(BusinessPhoto p) =>
        new(p.Id, $"/api/barbers/{p.BarberProfileId}/photos/{p.Id}", p.Caption, p.IsCover, p.SortOrder);

    private static string? NormalizeOptional(string? value, int maxLength)
    {
        var trimmed = value?.Trim();
        if (string.IsNullOrWhiteSpace(trimmed)) return null;
        return trimmed.Length <= maxLength ? trimmed : trimmed[..maxLength];
    }

    internal static object? ValidateDiscoveryQuery(NearbyDiscoveryQuery request)
    {
        static object Error(string code, string message) => new { code, message };
        if (!request.Lat.HasValue || !request.Lng.HasValue || request.Lat is < -90 or > 90 || request.Lng is < -180 or > 180)
            return Error("discovery_invalid_location", "Geçerli lat ve lng zorunludur.");
        if (request.RadiusKm is <= 0 or > 50)
            return Error("discovery_invalid_location", "radiusKm 0 ile 50 arasında olmalıdır.");
        if (request.Page < 1 || request.PageSize < 1)
            return Error("discovery_invalid_query", "page ve pageSize pozitif olmalıdır.");
        if (request.MinPrice < 0 || request.MaxPrice < 0 ||
            request.MinPrice.HasValue && request.MaxPrice.HasValue && request.MaxPrice < request.MinPrice)
            return Error("discovery_invalid_filter", "Fiyat aralığı geçersizdir.");
        if (request.MinRating is < 0 or > 5)
            return Error("discovery_invalid_filter", "minRating 0 ile 5 arasında olmalıdır.");
        if (request.Q?.Trim().Length > 80)
            return Error("discovery_invalid_query", "q en fazla 80 karakter olabilir.");
        if (request.Sort != null && request.Sort.Trim().ToLowerInvariant() is not ("distance" or "rating" or "price_asc" or "price_desc" or "relevance"))
            return Error("discovery_invalid_filter", "Desteklenmeyen sıralama değeri.");
        if (request.ServiceMode != null && NormalizeDiscoveryServiceMode(request.ServiceMode) == null)
            return Error("discovery_invalid_filter", "Desteklenmeyen hizmet modu.");
        return null;
    }

    internal static string? NormalizeSearch(string? value)
    {
        var trimmed = value?.Trim();
        if (string.IsNullOrWhiteSpace(trimmed)) return null;
        var escaped = trimmed.Replace("\\", "\\\\").Replace("%", "\\%").Replace("_", "\\_");
        return $"%{escaped}%";
    }

    internal static string? NormalizeDiscoveryServiceMode(string? value) => value?.Trim().ToLowerInvariant() switch
    {
        null or "" => null,
        "mobile" or "atcustomerlocation" or "müşteri" => "Mobile",
        "onsite" or "atbusiness" or "yerinde" => "Onsite",
        "both" or "ikisi" => "Both",
        _ => null
    };

    internal static List<AvailabilityIntervalDto> WorkingIntervalsFor(string workingHoursJson, DateOnly date)
    {
        var result = new List<AvailabilityIntervalDto>();
        try
        {
            using var document = JsonDocument.Parse(workingHoursJson);
            var day = date.DayOfWeek == DayOfWeek.Sunday ? 7 : (int)date.DayOfWeek;
            foreach (var item in document.RootElement.EnumerateArray())
            {
                var dayElement = GetJsonProperty(item, "day", "Day");
                var closedElement = GetJsonProperty(item, "closed", "Closed");
                var openElement = GetJsonProperty(item, "open", "Open");
                var closeElement = GetJsonProperty(item, "close", "Close");
                if (dayElement == null || dayElement.Value.GetInt32() != day ||
                    closedElement is { } closed && closed.GetBoolean() ||
                    openElement == null || closeElement == null) continue;
                var open = openElement.Value.GetString();
                var close = closeElement.Value.GetString();
                if (TimeSpan.TryParse(open, out _) && TimeSpan.TryParse(close, out _))
                    result.Add(new AvailabilityIntervalDto(open!, close!));
            }
        }
        catch (JsonException) { }
        return result.OrderBy(x => x.Open, StringComparer.Ordinal).ThenBy(x => x.Close, StringComparer.Ordinal).ToList();
    }

    private async Task<(Guid UserId, string WorkingHours)?> VisibleBarberAsync(Guid id, CancellationToken ct)
        => await _db.BarberProfiles.AsNoTracking()
            .Where(b => b.Id == id && b.Status == BarberStatus.Approved && b.IsOnline
                && b.User.AccountStatus == AccountStatus.Active && b.User.OnboardingCompleted)
            .Select(b => new ValueTuple<Guid, string>(b.UserId, b.WorkingHours))
            .FirstOrDefaultAsync(ct) is { } value && value.Item1 != Guid.Empty ? value : null;

    private static JsonElement? GetJsonProperty(JsonElement element, string camelCase, string pascalCase)
    {
        if (element.TryGetProperty(camelCase, out var value) || element.TryGetProperty(pascalCase, out value)) return value;
        return null;
    }

    private static TimeZoneInfo GetTurkeyTimeZone()
    {
        try { return TimeZoneInfo.FindSystemTimeZoneById("Europe/Istanbul"); }
        catch (TimeZoneNotFoundException) { return TimeZoneInfo.FindSystemTimeZoneById("Turkey Standard Time"); }
    }

    private static string NormalizeServiceMode(string? value)
    {
        var normalized = value?.Trim().ToLowerInvariant();
        return normalized switch
        {
            "onsite" or "yerinde" => "Onsite",
            "both" or "ikisi" => "Both",
            _ => "Mobile"
        };
    }

    private static string NormalizePriceType(string? value)
    {
        var normalized = value?.Trim().ToLowerInvariant();
        return normalized switch
        {
            "from" or "startingfrom" or "baslangic" => "From",
            "quote" or "offer" or "teklif" => "Quote",
            _ => "Fixed"
        };
    }

    private static DateTimeOffset GetVisitDate(ServiceRequest request)
    {
        if (request.CompletedAt.HasValue)
            return new DateTimeOffset(DateTime.SpecifyKind(request.CompletedAt.Value, DateTimeKind.Utc));

        return request.RequestedTime.ToUniversalTime();
    }

    private static string BuildCustomerDisplayName(User user)
    {
        var fullName = $"{user.FirstName} {user.LastName}".Trim();
        return string.IsNullOrWhiteSpace(fullName) ? "Müşteri" : fullName;
    }


}
