namespace Berbergelsin.Api.Services;

public interface ISmsSender
{
    /// <summary>phone: "90XXXXXXXXXX" formatında</summary>
    Task SendAsync(string phone, string content, CancellationToken ct = default);
}
