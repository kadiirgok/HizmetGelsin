using Berbergelsin.Api.Data;
using Berbergelsin.Api.Dtos;
using Berbergelsin.Api.Enums;
using Berbergelsin.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Berbergelsin.Api.Controllers;

[ApiController]
[Route("api/admin")]
[Authorize(Roles = "Admin")]
public class AdminController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly FileStorageService _fileStorage;
    private readonly RealtimeNotifier _notifier;
    private readonly IEmailSender _emailSender;

    public AdminController(AppDbContext db, FileStorageService fileStorage, RealtimeNotifier notifier, IEmailSender emailSender)
    {
        _db = db;
        _fileStorage = fileStorage;
        _notifier = notifier;
        _emailSender = emailSender;
    }

    [HttpGet("barbers")]
    public async Task<IActionResult> ListBarbers([FromQuery] BarberStatus? status, CancellationToken ct)
    {
        var query = _db.BarberProfiles.Include(b => b.User).AsQueryable();
        if (status.HasValue)
            query = query.Where(b => b.Status == status.Value);

        var list = await query
            .OrderByDescending(b => b.CreatedAt)
            .Take(200)
            .Select(b => new AdminBarberListItemDto(
                b.Id, b.User.FirstName, b.User.LastName, b.User.PhoneNumber,
                b.BusinessName, b.Status, b.CreatedAt))
            .ToListAsync(ct);

        return Ok(list);
    }

    [HttpGet("barbers/{id:guid}")]
    public async Task<IActionResult> GetBarber(Guid id, CancellationToken ct)
    {
        var b = await _db.BarberProfiles
            .Include(x => x.User).Include(x => x.Documents).Include(x => x.Services)
            .FirstOrDefaultAsync(x => x.Id == id, ct);
        if (b == null) return NotFound();

        return Ok(new AdminBarberDetailDto(
            b.Id, b.User.FirstName, b.User.LastName, b.User.PhoneNumber, b.User.Email,
            b.BusinessName, b.TcKimlikNo, b.Status, b.RejectionReason,
            b.SharePhone, b.AcceptsOffers, b.ServiceRadiusKm, b.WorkingHours,
            b.Documents.Select(d => new AdminDocumentDto(d.Id, d.Type, d.OriginalFileName, d.ContentType, d.SizeBytes)).ToList(),
            b.Services.OrderBy(s => s.SortOrder)
                .Select(s => new BarberServiceDto(s.Id, s.Name, s.Price, s.Description, s.PriceType, s.DurationMinutes, s.IsPopular))
                .ToList(),
            b.CreatedAt));
    }

    [HttpGet("barbers/{id:guid}/documents/{docId:guid}")]
    public async Task<IActionResult> GetDocument(Guid id, Guid docId, CancellationToken ct)
    {
        var doc = await _db.BarberDocuments
            .FirstOrDefaultAsync(d => d.Id == docId && d.BarberProfileId == id, ct);
        if (doc == null) return NotFound();

        var stream = _fileStorage.OpenRead(doc.StoredFileName);
        if (stream == null) return NotFound();

        Response.Headers.ContentDisposition = $"inline; filename=\"{doc.StoredFileName}\"";
        return File(stream, doc.ContentType);
    }

    [HttpPost("barbers/{id:guid}/approve")]
    public async Task<IActionResult> Approve(Guid id, CancellationToken ct)
    {
        var b = await _db.BarberProfiles.Include(x => x.User).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (b == null) return NotFound();
        if (b.Status != BarberStatus.PendingApproval)
            return BadRequest(new { message = "Bu başvuru onay bekleyen durumda değil." });

        b.Status = BarberStatus.Approved;
        b.ApprovedAt = DateTime.UtcNow;
        b.RejectionReason = null;
        await _db.SaveChangesAsync(ct);

        await _notifier.ToUserAsync(b.UserId, "BarberStatusChanged",
            new { status = b.Status.ToString(), rejectionReason = (string?)null });
        await _notifier.ToAdminsAsync("BarberListChanged", new { barberProfileId = b.Id });

        // Email bildirimi gönder
        if (!string.IsNullOrWhiteSpace(b.User.Email))
        {
            try
            {
                var subject = "HizmetGelsin • İşletmeniz Onaylandı!";
                var body = $@"<!DOCTYPE html>
<html><head><meta charset=""UTF-8""></head>
<body style=""font-family:sans-serif;background:#FAFAFA;padding:40px"">
<div style=""max-width:480px;margin:0 auto;background:#FFF;border-radius:16px;padding:32px"">
<div style=""font-size:24px;font-weight:800;color:#111;margin-bottom:16px"">İşletmeniz Onaylandı!</div>
<div style=""font-size:15px;color:#444;line-height:1.6;margin-bottom:24px"">
<b>{b.BusinessName ?? "İşletmeniz"}</b> başvurunuz onaylandı. Artık müşterilerden talep alabilir, teklif gönderebilir ve hizmet vermeye başlayabilirsiniz.
</div>
<div style=""background:#111;border-radius:12px;padding:14px;text-align:center"">
<a href=""hizmetgelsin://berber"" style=""color:#FFF;text-decoration:none;font-weight:700"">HizmetGelsin'i Aç</a>
</div>
<div style=""font-size:12px;color:#999;margin-top:24px;text-align:center"">HizmetGelsin Ekibi</div>
</div></body></html>";
                await _emailSender.SendAsync(b.User.Email, subject, body, ct);
            }
            catch { /* Email başarısız olursa işlemi bozma */ }
        }

        return Ok(new { message = "İşletme onaylandı." });
    }

    [HttpPost("barbers/{id:guid}/reject")]
    public async Task<IActionResult> Reject(Guid id, RejectBarberRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Reason))
            return BadRequest(new { message = "Ret gerekçesi zorunludur." });

        var b = await _db.BarberProfiles.Include(x => x.User).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (b == null) return NotFound();
        if (b.Status != BarberStatus.PendingApproval)
            return BadRequest(new { message = "Bu başvuru onay bekleyen durumda değil." });

        b.Status = BarberStatus.Rejected;
        b.RejectionReason = request.Reason.Trim();
        await _db.SaveChangesAsync(ct);

        await _notifier.ToUserAsync(b.UserId, "BarberStatusChanged",
            new { status = b.Status.ToString(), rejectionReason = b.RejectionReason });
        await _notifier.ToAdminsAsync("BarberListChanged", new { barberProfileId = b.Id });

        return Ok(new { message = "Başvuru reddedildi." });
    }
}
