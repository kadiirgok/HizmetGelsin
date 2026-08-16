namespace Berbergelsin.Api.Services;

/// <summary>
/// Gmail SMTP veya başka bir SMTP sunucusu üzerinden e-posta gönderimi.
/// </summary>
public interface IEmailSender
{
    Task SendAsync(string to, string subject, string body, CancellationToken ct = default);
}

public class SmtpEmailSender : IEmailSender
{
    private readonly IConfiguration _config;
    private readonly ILogger<SmtpEmailSender> _logger;

    public SmtpEmailSender(IConfiguration config, ILogger<SmtpEmailSender> logger)
    {
        _config = config;
        _logger = logger;
    }

    public async Task SendAsync(string to, string subject, string body, CancellationToken ct = default)
    {
        var host = _config["Email:Host"] ?? "smtp.gmail.com";
        if (!int.TryParse(_config["Email:Port"] ?? "587", out var port)) port = 587;
        var user = _config["Email:User"];
        var pass = _config["Email:Password"];
        var from = _config["Email:From"] ?? user;

        if (string.IsNullOrWhiteSpace(user) || string.IsNullOrWhiteSpace(pass))
        {
            _logger.LogWarning("Email ayarları eksik. Host:{Host} User:{User} Pass:{(var)}", host, user, string.IsNullOrWhiteSpace(pass) ? "bos" : "***");
            throw new InvalidOperationException("Email gönderimi yapılandırılmamış.");
        }

        using var client = new System.Net.Mail.SmtpClient(host, port)
        {
            EnableSsl = true,
            Credentials = new System.Net.NetworkCredential(user, pass)
        };

        var fromName = _config["Email:FromName"] ?? "HizmetGelsin";
        var fromAddress = new System.Net.Mail.MailAddress(from, fromName);
        var mail = new System.Net.Mail.MailMessage(fromAddress, new System.Net.Mail.MailAddress(to))
        {
            Subject = subject,
            Body = body,
            IsBodyHtml = true
        };

        await client.SendMailAsync(mail, ct);
        _logger.LogInformation("Email gönderildi: {To} - {Subject}", to, subject);
    }
}

/// <summary>
/// Email altyapısı yoksa log'a yazan yerine-geçen (fallback) gönderici.
/// </summary>
public class ConsoleEmailSender : IEmailSender
{
    private readonly ILogger<ConsoleEmailSender> _logger;

    public ConsoleEmailSender(ILogger<ConsoleEmailSender> logger)
    {
        _logger = logger;
    }

    public Task SendAsync(string to, string subject, string body, CancellationToken ct = default)
    {
        _logger.LogInformation("EMAIL [{To}] Konu:{Subject} Icerik:{Body}", to, subject, body);
        return Task.CompletedTask;
    }
}
