namespace Berbergelsin.Api.Entities;

public class ServiceRequestItem
{
    public Guid Id { get; set; }
    public Guid ServiceRequestId { get; set; }
    public ServiceRequest ServiceRequest { get; set; } = null!;
    public Guid BarberServiceId { get; set; }
    /// <summary>Talep anındaki hizmet adı (snapshot)</summary>
    public string ServiceName { get; set; } = null!;
    /// <summary>Talep anındaki fiyat (snapshot)</summary>
    public decimal PriceAtRequest { get; set; }
}
