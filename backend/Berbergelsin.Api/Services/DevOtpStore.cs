using System.Collections.Concurrent;

namespace Berbergelsin.Api.Services;

/// <summary>
/// Geliştirme aşamasında OTP kodlarına API üzerinden erişmek için geçici depo.
/// Email/SMS gönderimi yapılandırıldığında kaldırılacaktır.
/// </summary>
public class DevOtpStore
{
    private readonly ConcurrentDictionary<string, OtpEntry> _codes = new();

    public void Store(string key, string code)
    {
        _codes[key] = new OtpEntry(code, DateTime.UtcNow);
    }

    public OtpEntry? Retrieve(string key)
    {
        _codes.TryGetValue(key, out var entry);
        return entry;
    }

    public bool Remove(string key)
    {
        return _codes.TryRemove(key, out _);
    }
}

public record OtpEntry(string Code, DateTime CreatedAt);
