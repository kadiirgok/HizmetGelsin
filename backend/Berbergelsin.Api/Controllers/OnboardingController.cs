using Berbergelsin.Api.Auth;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Dtos;
using Berbergelsin.Api.Entities;
using Berbergelsin.Api.Enums;
using Berbergelsin.Api.Services;
using Berbergelsin.Api.Validation;
using FluentValidation;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;

namespace Berbergelsin.Api.Controllers;

[ApiController]
[Route("api/onboarding")]
[Authorize]
public class OnboardingController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly FileStorageService _fileStorage;
    private readonly RealtimeNotifier _notifier;

    public OnboardingController(AppDbContext db, FileStorageService fileStorage, RealtimeNotifier notifier)
    {
        _db = db;
        _fileStorage = fileStorage;
        _notifier = notifier;
    }

    [HttpPost("client")]
    [Authorize(Roles = "Musteri")]
    public async Task<IActionResult> ClientOnboarding(ClientOnboardingRequest request, CancellationToken ct)
    {
        var validation = await new ClientOnboardingValidator().ValidateAsync(request, ct);
        if (!validation.IsValid)
            return BadRequest(new { message = validation.Errors[0].ErrorMessage });

        var user = await _db.Users.FirstAsync(u => u.Id == User.GetUserId(), ct);
        user.FirstName = request.FirstName.Trim();
        user.LastName = request.LastName.Trim();
        var newEmail = request.Email.Trim();
        if (!string.Equals(user.Email, newEmail, StringComparison.OrdinalIgnoreCase)
            && await _db.Users.AnyAsync(u => u.Id != user.Id && u.Email == newEmail && u.Role == UserRole.Musteri, ct))
            return BadRequest(new { message = "Bu e-posta adresi zaten kayıtlı." });

        user.Email = newEmail;
        // user.PhoneNumber is verified during auth registration and cannot be overwritten by request payload
        user.KvkkAcceptedAt = DateTime.UtcNow;
        user.OnboardingCompleted = true;
        await _db.SaveChangesAsync(ct);

        return Ok(new { message = "Kayıt tamamlandı." });
    }

    [HttpPost("barber/profile")]
    [Authorize(Roles = "Berber")]
    public async Task<IActionResult> BarberProfileStep(BarberProfileStepRequest request, CancellationToken ct)
    {
        var validation = await new BarberProfileStepValidator().ValidateAsync(request, ct);
        if (!validation.IsValid)
            return BadRequest(new { message = validation.Errors[0].ErrorMessage });

        var user = await _db.Users.Include(u => u.BarberProfile)
            .FirstAsync(u => u.Id == User.GetUserId(), ct);
        var profile = user.BarberProfile!;

        if (profile.Status is BarberStatus.PendingApproval or BarberStatus.Approved)
            return BadRequest(new { message = "Başvurunuz zaten gönderildi." });

        user.FirstName = request.FirstName.Trim();
        user.LastName = request.LastName.Trim();
        var newEmail = request.Email.Trim();
        if (!string.Equals(user.Email, newEmail, StringComparison.OrdinalIgnoreCase)
            && await _db.Users.AnyAsync(u => u.Id != user.Id && u.Email == newEmail && u.Role == UserRole.Berber, ct))
            return BadRequest(new { message = "Bu e-posta adresi zaten kayıtlı." });

        user.Email = newEmail;
        // user.PhoneNumber is verified during auth registration and cannot be overwritten by request payload
        user.KvkkAcceptedAt = DateTime.UtcNow;
        profile.TcKimlikNo = request.TcKimlikNo;
        profile.BusinessName = request.BusinessName?.Trim();
        profile.Category = request.Category?.Trim();
        await _db.SaveChangesAsync(ct);

        return Ok(new { message = "Bilgiler kaydedildi." });
    }

    [HttpPost("barber/documents")]
    [Authorize(Roles = "Berber")]
    [RequestSizeLimit(25_000_000)]
    public async Task<IActionResult> UploadDocument(
        [FromForm] IFormFile file, [FromForm] string type, CancellationToken ct)
    {
        if (!Enum.TryParse<DocumentType>(type, ignoreCase: true, out var docType))
            return BadRequest(new { message = "Geçersiz belge tipi." });

        var profile = await GetOwnProfileAsync(ct);
        if (profile == null) return NotFound();
        if (profile.Status is BarberStatus.PendingApproval or BarberStatus.Approved)
            return BadRequest(new { message = "Başvurunuz zaten gönderildi." });

        string storedFileName, contentType;
        long size;
        try
        {
            (storedFileName, contentType, size) = await _fileStorage.SaveAsync(file, ct);
        }
        catch (FileValidationException ex)
        {
            return BadRequest(new { message = ex.Message });
        }

        // Aynı tip belge tekrar yüklenirse eskisini değiştir
        var existing = await _db.BarberDocuments
            .Where(d => d.BarberProfileId == profile.Id && d.Type == docType)
            .ToListAsync(ct);
        foreach (var old in existing)
        {
            try { _fileStorage.Delete(old.StoredFileName); } catch { /* Silinmezse devam et */ }
        }
        _db.BarberDocuments.RemoveRange(existing);

        _db.BarberDocuments.Add(new BarberDocument
        {
            Id = Guid.NewGuid(),
            BarberProfileId = profile.Id,
            Type = docType,
            StoredFileName = storedFileName,
            OriginalFileName = Path.GetFileName(file.FileName),
            ContentType = contentType,
            SizeBytes = size,
            UploadedAt = DateTime.UtcNow
        });
        await _db.SaveChangesAsync(ct);

        return Ok(new { message = "Belge yüklendi." });
    }

    [HttpPost("barber/services")]
    [Authorize(Roles = "Berber")]
    public async Task<IActionResult> BarberServicesStep(BarberServicesStepRequest request, CancellationToken ct)
    {
        var validation = await new BarberServicesStepValidator().ValidateAsync(request, ct);
        if (!validation.IsValid)
            return BadRequest(new { message = validation.Errors[0].ErrorMessage });

        var profile = await GetOwnProfileAsync(ct);
        if (profile == null) return NotFound();
        if (profile.Status is BarberStatus.PendingApproval or BarberStatus.Approved)
            return BadRequest(new { message = "Başvurunuz zaten gönderildi." });

        var existing = await _db.BarberServices
            .Where(s => s.BarberProfileId == profile.Id).ToListAsync(ct);
        _db.BarberServices.RemoveRange(existing);

        var order = 0;
        foreach (var item in request.Services)
        {
            var definition = await ServiceCatalogLinker.GetOrCreateAsync(_db, item.Name, profile.Category, ct);
            _db.BarberServices.Add(new BarberService
            {
                Id = Guid.NewGuid(),
                BarberProfileId = profile.Id,
                ServiceDefinition = definition,
                Name = item.Name.Trim(),
                Price = item.Price,
                SortOrder = order++,
                IsActive = true
            });
        }
        profile.AcceptsOffers = request.AcceptsOffers;
        await _db.SaveChangesAsync(ct);

        return Ok(new { message = "Hizmetler kaydedildi." });
    }

    [HttpPost("barber/complete")]
    [Authorize(Roles = "Berber")]
    public async Task<IActionResult> BarberComplete(BarberCompleteStepRequest request, CancellationToken ct)
    {
        var validation = await new BarberCompleteStepValidator().ValidateAsync(request, ct);
        if (!validation.IsValid)
            return BadRequest(new { message = validation.Errors[0].ErrorMessage });

        var user = await _db.Users.Include(u => u.BarberProfile)
            .FirstAsync(u => u.Id == User.GetUserId(), ct);
        var profile = user.BarberProfile!;

        if (profile.Status is BarberStatus.PendingApproval or BarberStatus.Approved)
            return BadRequest(new { message = "Başvurunuz zaten gönderildi." });

        // Ön koşullar: kimlik bilgileri, en az 1 hizmet
        if (string.IsNullOrEmpty(profile.TcKimlikNo))
            return BadRequest(new { message = "Önce kişisel bilgilerinizi kaydedin." });

        var hasServices = await _db.BarberServices.AnyAsync(s => s.BarberProfileId == profile.Id, ct);
        if (!hasServices)
            return BadRequest(new { message = "En az bir hizmet eklemelisiniz." });

        profile.SharePhone = request.SharePhone;
        profile.ServiceRadiusKm = request.ServiceRadiusKm;
        if (request.WorkingHours != null)
            profile.WorkingHours = JsonSerializer.Serialize(request.WorkingHours);
        profile.Status = BarberStatus.PendingApproval;
        profile.RejectionReason = null;
        user.OnboardingCompleted = true;
        await _db.SaveChangesAsync(ct);

        await _notifier.ToAdminsAsync("BarberPendingApproval", new
        {
            barberProfileId = profile.Id,
            firstName = user.FirstName,
            lastName = user.LastName,
            businessName = profile.BusinessName,
            phone = user.PhoneNumber
        });

        return Ok(new { message = "Başvurunuz alındı. Onay sürecine geçildi." });
    }

    [HttpGet("status")]
    public async Task<IActionResult> Status(CancellationToken ct)
    {
        var user = await _db.Users.Include(u => u.BarberProfile)
            .FirstAsync(u => u.Id == User.GetUserId(), ct);

        var hasProfileStep = false;
        var uploadedDocs = new List<string>();
        var hasServices = false;

        if (user.BarberProfile != null)
        {
            hasProfileStep = !string.IsNullOrEmpty(user.BarberProfile.TcKimlikNo);
            uploadedDocs = await _db.BarberDocuments
                .Where(d => d.BarberProfileId == user.BarberProfile.Id)
                .Select(d => d.Type.ToString()).ToListAsync(ct);
            hasServices = await _db.BarberServices
                .AnyAsync(s => s.BarberProfileId == user.BarberProfile.Id, ct);
        }

        return Ok(new OnboardingStatusResponse(
            user.OnboardingCompleted,
            user.Role.ToString(),
            user.BarberProfile?.Status.ToString(),
            user.BarberProfile?.RejectionReason,
            hasProfileStep,
            uploadedDocs,
            hasServices));
    }

    private async Task<BarberProfile?> GetOwnProfileAsync(CancellationToken ct)
    {
        var barberProfileId = User.GetBarberProfileId();
        if (barberProfileId == null) return null;
        return await _db.BarberProfiles.FirstOrDefaultAsync(b => b.Id == barberProfileId, ct);
    }
}
