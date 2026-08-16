using Berbergelsin.Api.Auth;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Dtos;
using Berbergelsin.Api.Enums;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Berbergelsin.Api.Controllers;

[ApiController]
[Route("api/client")]
[Authorize]
public sealed class ClientController(AppDbContext db) : ControllerBase
{
    [HttpGet("profile")]
    public async Task<IActionResult> GetProfile(CancellationToken ct)
    {
        if (!User.IsInRole(UserRole.Musteri.ToString())) return Error(403, "client_profile_forbidden");
        var user = await db.Users.AsNoTracking().SingleOrDefaultAsync(x => x.Id == User.GetUserId(), ct);
        if (user == null) return Error(404, "client_profile_not_found");
        if (user.Role != UserRole.Musteri) return Error(403, "client_profile_forbidden");
        if (user.AccountStatus == AccountStatus.DeletionPending)
            return Error(409, "client_profile_deletion_pending");
        return Ok(ToDto(user));
    }

    [HttpPut("profile")]
    public async Task<IActionResult> UpdateProfile(UpdateClientProfileRequest request, CancellationToken ct)
    {
        if (!User.IsInRole(UserRole.Musteri.ToString())) return Error(403, "client_profile_forbidden");
        var firstName = request.FirstName?.Trim();
        var lastName = request.LastName?.Trim();
        var email = NormalizeOptional(request.Email)?.ToLowerInvariant();
        var image = NormalizeOptional(request.ProfileImageUrl);
        if (string.IsNullOrWhiteSpace(firstName) || string.IsNullOrWhiteSpace(lastName) ||
            firstName.Length > 100 || lastName.Length > 100 ||
            (email != null && (!new System.ComponentModel.DataAnnotations.EmailAddressAttribute().IsValid(email) || email.Length > 200)) ||
            (image != null && (!Uri.TryCreate(image, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps)))
            return Error(400, "client_profile_invalid");
        if (!Guid.TryParse(request.Version, out var expectedVersion))
            return Error(409, "client_profile_conflict");

        var user = await db.Users.SingleOrDefaultAsync(x => x.Id == User.GetUserId(), ct);
        if (user == null) return Error(404, "client_profile_not_found");
        if (user.Role != UserRole.Musteri) return Error(403, "client_profile_forbidden");
        if (user.AccountStatus == AccountStatus.DeletionPending)
            return Error(409, "client_profile_deletion_pending");
        if (user.ProfileVersion != expectedVersion)
            return Error(409, "client_profile_conflict");
        if (email != null && await db.Users.AnyAsync(x => x.Id != user.Id && x.Email != null && x.Email.ToLower() == email, ct))
            return Error(409, "client_profile_email_in_use");

        user.FirstName = firstName;
        user.LastName = lastName;
        user.Email = email;
        user.ProfileImageUrl = image;
        user.ProfileVersion = Guid.NewGuid();
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateConcurrencyException) { return Error(409, "client_profile_conflict"); }
        return Ok(ToDto(user));
    }

    [HttpDelete("profile")]
    public async Task<IActionResult> DeleteProfile(CancellationToken ct)
    {
        if (!User.IsInRole(UserRole.Musteri.ToString())) return Error(403, "client_profile_forbidden");
        var user = await db.Users.SingleOrDefaultAsync(x => x.Id == User.GetUserId(), ct);
        if (user == null) return Error(404, "client_profile_not_found");
        if (user.Role != UserRole.Musteri) return Error(403, "client_profile_forbidden");
        if (user.AccountStatus != AccountStatus.DeletionPending)
        {
            user.AccountStatus = AccountStatus.DeletionPending;
            user.DeletionRequestedAt = DateTime.UtcNow;
            user.ProfileVersion = Guid.NewGuid();
            user.TokenVersion++;
            var tokens = await db.RefreshTokens.Where(x => x.UserId == user.Id && x.RevokedAt == null).ToListAsync(ct);
            foreach (var token in tokens) token.RevokedAt = DateTime.UtcNow;
            await db.SaveChangesAsync(ct);
        }
        return Ok(new { code = "client_profile_deletion_pending", deletionRequestedAt = user.DeletionRequestedAt });
    }

    private static ClientProfileDto ToDto(Entities.User u) => new(u.Id, u.FirstName, u.LastName,
        u.PhoneNumber, u.Email, u.ProfileImageUrl, u.IsPhoneVerified, u.CreatedAt, u.ProfileVersion.ToString("D"));
    private static string? NormalizeOptional(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    private ObjectResult Error(int status, string code) => StatusCode(status, new { code });
}
