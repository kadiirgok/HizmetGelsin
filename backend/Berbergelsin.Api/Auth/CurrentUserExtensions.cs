using System.Security.Claims;

namespace Berbergelsin.Api.Auth;

public static class CurrentUserExtensions
{
    public static Guid GetUserId(this ClaimsPrincipal user)
        => Guid.Parse(user.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? throw new InvalidOperationException("sub claim yok"));

    public static Guid? GetBarberProfileId(this ClaimsPrincipal user)
    {
        var v = user.FindFirstValue("barberProfileId");
        return v == null ? null : Guid.Parse(v);
    }

    public static string GetPhone(this ClaimsPrincipal user)
        => user.FindFirstValue("phone") ?? "";
}
