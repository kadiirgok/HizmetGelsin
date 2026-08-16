using Berbergelsin.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Berbergelsin.Api.Controllers;

/// <summary>
/// Geliştirme aşamasında OTP kodlarına erişmek için geçici endpoint.
/// Email/SMS altyapısı hazır olduğunda kaldırılacaktır.
/// </summary>
[ApiController]
[Route("api/auth/dev")]
public class DevOtpController : ControllerBase
{
    private readonly DevOtpStore _store;
    private readonly IHostEnvironment _env;

    public DevOtpController(DevOtpStore store, IHostEnvironment env)
    {
        _store = store;
        _env = env;
    }

    [HttpGet("latest-code")]
    [AllowAnonymous]
    public IActionResult GetLatestCode([FromQuery] string? email, [FromQuery] string? phone)
    {
        // Sadece development ortamında çalışır
        if (!_env.IsDevelopment())
            return NotFound();

        var key = email ?? phone;
        if (string.IsNullOrWhiteSpace(key))
            return BadRequest(new { message = "email veya phone parametresi gerekli." });

        var entry = _store.Retrieve(key);
        if (entry == null)
            return NotFound(new { message = "Bu email/telefon için bekleyen kod bulunamadı." });

        return Ok(new
        {
            key,
            code = entry.Code,
            createdAt = entry.CreatedAt,
            hint = "Bu kod 5 dakika geçerlidir. Bu endpoint sadece geliştirme amaçlıdır."
        });
    }
}
