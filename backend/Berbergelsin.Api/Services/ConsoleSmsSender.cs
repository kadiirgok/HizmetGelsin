namespace Berbergelsin.Api.Services;

/// <summary>Geliştirme ortamı: SMS göndermek yerine içeriği log'a yazar.</summary>
public class ConsoleSmsSender : ISmsSender
{
    private readonly ILogger<ConsoleSmsSender> _logger;

    public ConsoleSmsSender(ILogger<ConsoleSmsSender> logger) => _logger = logger;

    public Task SendAsync(string phone, string content, CancellationToken ct = default)
    {
        _logger.LogWarning("[DEV SMS] {Phone} -> {Content}", phone, content);
        return Task.CompletedTask;
    }
}
