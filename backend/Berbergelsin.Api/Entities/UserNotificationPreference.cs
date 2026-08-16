namespace Berbergelsin.Api.Entities;

/// <summary>Kullanıcı başına push bildirim tercihleri.</summary>
public class UserNotificationPreference
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }

    public bool NewRequest { get; set; } = true;
    public bool RequestAccepted { get; set; } = true;
    public bool RequestRejected { get; set; } = true;
    public bool OnTheWay { get; set; } = true;
    public bool Started { get; set; } = true;
    public bool Completed { get; set; } = true;
    public bool Cancelled { get; set; } = true;
    public bool NewReview { get; set; } = true;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    public User User { get; set; } = null!;

    public Dictionary<string, bool> ToDictionary() => new()
    {
        ["new_request"] = NewRequest,
        ["request_accepted"] = RequestAccepted,
        ["request_rejected"] = RequestRejected,
        ["on_the_way"] = OnTheWay,
        ["started"] = Started,
        ["completed"] = Completed,
        ["cancelled"] = Cancelled,
        ["new_review"] = NewReview,
    };

    public void SetFromDictionary(Dictionary<string, bool> prefs)
    {
        if (prefs.TryGetValue("new_request", out var v)) NewRequest = v;
        if (prefs.TryGetValue("request_accepted", out v)) RequestAccepted = v;
        if (prefs.TryGetValue("request_rejected", out v)) RequestRejected = v;
        if (prefs.TryGetValue("on_the_way", out v)) OnTheWay = v;
        if (prefs.TryGetValue("started", out v)) Started = v;
        if (prefs.TryGetValue("completed", out v)) Completed = v;
        if (prefs.TryGetValue("cancelled", out v)) Cancelled = v;
        if (prefs.TryGetValue("new_review", out v)) NewReview = v;
        UpdatedAt = DateTime.UtcNow;
    }

    /// <summary>Tüm tercihlerin varsayılan (açık) hali.</summary>
    public static Dictionary<string, bool> Defaults() => new()
    {
        ["new_request"] = true,
        ["request_accepted"] = true,
        ["request_rejected"] = true,
        ["on_the_way"] = true,
        ["started"] = true,
        ["completed"] = true,
        ["cancelled"] = true,
        ["new_review"] = true,
    };

    /// <summary>Belirtilen olay için bildirim aktif mi?</summary>
    public bool IsEnabled(string eventKey) => eventKey switch
    {
        "new_request" => NewRequest,
        "request_accepted" => RequestAccepted,
        "request_rejected" => RequestRejected,
        "on_the_way" => OnTheWay,
        "started" => Started,
        "completed" => Completed,
        "cancelled" => Cancelled,
        "new_review" => NewReview,
        _ => true, // bilinmeyen olaylar için varsayılan: açık
    };
}
