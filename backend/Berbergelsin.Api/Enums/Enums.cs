namespace Berbergelsin.Api.Enums;

public enum UserRole
{
    Musteri = 1,
    Berber = 2,
    Admin = 3
}

public enum AccountStatus
{
    Active = 1,
    DeletionPending = 2,
    Pending = 3,
    Deleted = 4,
    Suspended = 5,
    Blocked = 6
}

public enum BarberStatus
{
    Onboarding = 0,
    PendingApproval = 1,
    Approved = 2,
    Rejected = 3
}

public enum DocumentType
{
    UstalikBelgesi = 1,
    EsnafOdasiKaydi = 2,
    ScılBelgesi = 3,
    IkametAdresi = 4
}

public enum RequestStatus
{
    Pending = 1,
    Accepted = 2,
    Rejected = 3,
    Completed = 4,
    Cancelled = 5,
    /// <summary>Hizmet veren yola çıktı, canlı takip aktif</summary>
    OnTheWay = 6,
    /// <summary>Hizmet veren müşteri konumuna ulaştı, hizmet sürüyor</summary>
    Started = 7,
    ReschedulePending = 8
}

public enum OfferStatus
{
    Pending = 1,
    Accepted = 2,
    Rejected = 3,
    Countered = 4,
    CounterAccepted = 5,
    CounterRejected = 6,
    Expired = 7
}
public enum RatingModerationStatus { Visible=1,UnderReview=2,Hidden=3 }
