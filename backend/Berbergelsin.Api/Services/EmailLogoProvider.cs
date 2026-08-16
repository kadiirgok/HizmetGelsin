namespace Berbergelsin.Api.Services;

/// <summary>
/// Email şablonlarında kullanılmak üzere logo dosyasını base64 olarak sağlar.
/// </summary>
public class EmailLogoProvider
{
    private string? _base64Logo;
    private readonly string _logoPath;

    public EmailLogoProvider(IConfiguration config, IHostEnvironment env)
    {
        _logoPath = config["Email:LogoPath"] ?? Path.Combine(env.ContentRootPath, "email-logo.png");
    }

    public string GetBase64Logo()
    {
        if (_base64Logo != null)
            return _base64Logo;

        if (!File.Exists(_logoPath))
            return "";

        var bytes = File.ReadAllBytes(_logoPath);
        _base64Logo = Convert.ToBase64String(bytes);
        return _base64Logo;
    }
}
