using System.Text;
using System.Text.Json;

namespace Berbergelsin.Api.Services;

public class NacSmsSender : ISmsSender
{
    private readonly HttpClient _http;
    private readonly IConfiguration _config;
    private readonly ILogger<NacSmsSender> _logger;

    public NacSmsSender(HttpClient http, IConfiguration config, ILogger<NacSmsSender> logger)
    {
        _http = http;
        _config = config;
        _logger = logger;
    }

    public async Task SendAsync(string phone, string content, CancellationToken ct = default)
    {
        var sms = _config.GetSection("SmsSettings");
        var body = new
        {
            type = 1,
            sendingType = 0,
            title = "HizmetGelsin",
            content,
            number = phone,
            encoding = 0,
            sender = sms["Origin"],
            periodicSettings = (object?)null,
            sendingDate = (object?)null,
            validity = 60,
            pushSettings = (object?)null
        };

        using var request = new HttpRequestMessage(HttpMethod.Post, $"{sms["BaseUrl"]}/sms/create");
        request.Headers.TryAddWithoutValidation("Authorization", sms["AuthHeader"]);
        request.Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");

        var response = await _http.SendAsync(request, ct);
        _logger.LogInformation("SMS sağlayıcı yanıtı alındı: {Status}",
            (int)response.StatusCode);

        if (!response.IsSuccessStatusCode)
            throw new SmsSendException($"SMS servisi {(int)response.StatusCode} döndü");
    }
}

public class SmsSendException : Exception
{
    public SmsSendException(string message) : base(message) { }
}
