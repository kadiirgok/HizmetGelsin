namespace Berbergelsin.Api.Services;

public class FileStorageService
{
    private static readonly Dictionary<string, string> AllowedTypes = new()
    {
        ["application/pdf"] = ".pdf",
        ["image/jpeg"] = ".jpg",
        ["image/png"] = ".png"
    };

    private readonly string _rootPath;
    private readonly long _maxSize;

    public FileStorageService(IConfiguration config, IWebHostEnvironment env)
    {
        var configured = config["FileStorage:RootPath"] ?? "uploads";
        _rootPath = Path.IsPathRooted(configured)
            ? configured
            : Path.Combine(env.ContentRootPath, configured);
        _maxSize = config.GetValue("FileStorage:MaxSizeBytes", 10_485_760L);
        Directory.CreateDirectory(_rootPath);
    }

    public long MaxSizeBytes => _maxSize;

    /// <summary>Doğrulama + kaydetme. Hata durumunda kullanıcıya gösterilebilir Türkçe mesajla exception fırlatır.</summary>
    public async Task<(string storedFileName, string contentType, long size)> SaveAsync(
        IFormFile file, CancellationToken ct = default)
    {
        if (file.Length == 0)
            throw new FileValidationException("Dosya boş.");
        if (file.Length > _maxSize)
            throw new FileValidationException($"Dosya boyutu {_maxSize / 1024 / 1024} MB'ı aşamaz.");
        if (!AllowedTypes.TryGetValue(file.ContentType.ToLowerInvariant(), out var ext))
            throw new FileValidationException("Yalnızca PDF, JPG veya PNG yükleyebilirsiniz.");

        // Magic-byte kontrolü — içerik tipi beyanı ile dosya başlığı uyuşmalı
        byte[] header = new byte[8];
        int read;
        await using (var stream = file.OpenReadStream())
        {
            read = await stream.ReadAtLeastAsync(header, 4, throwOnEndOfStream: false, ct);
        }
        if (read < 4 || !MatchesMagic(header, ext))
            throw new FileValidationException("Dosya içeriği geçersiz veya bozuk.");

        var storedFileName = Guid.NewGuid().ToString("N") + ext;
        var fullPath = Path.Combine(_rootPath, storedFileName);
        await using (var target = File.Create(fullPath))
        {
            await file.CopyToAsync(target, ct);
        }

        return (storedFileName, file.ContentType.ToLowerInvariant(), file.Length);
    }

    public void Delete(string storedFileName)
    {
        if (storedFileName.Contains("..") || storedFileName.Contains('/') || storedFileName.Contains('\\'))
            return;
        var fullPath = Path.Combine(_rootPath, storedFileName);
        try { File.Delete(fullPath); } catch { /* Silinmezse devam et */ }
    }

    public FileStream? OpenRead(string storedFileName)
    {
        // Path traversal koruması: yalnızca dosya adı, dizin bileşeni yok
        if (storedFileName.Contains("..") || storedFileName.Contains('/') || storedFileName.Contains('\\'))
            return null;
        var fullPath = Path.Combine(_rootPath, storedFileName);
        return File.Exists(fullPath) ? File.OpenRead(fullPath) : null;
    }

    private static bool MatchesMagic(byte[] header, string ext) => ext switch
    {
        ".pdf" => header[0] == 0x25 && header[1] == 0x50 && header[2] == 0x44 && header[3] == 0x46, // %PDF
        ".jpg" => header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF,
        ".png" => header[0] == 0x89 && header[1] == 0x50 && header[2] == 0x4E && header[3] == 0x47,
        _ => false
    };
}

public class FileValidationException : Exception
{
    public FileValidationException(string message) : base(message) { }
}
