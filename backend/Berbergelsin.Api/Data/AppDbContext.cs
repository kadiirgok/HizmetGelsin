using Berbergelsin.Api.Entities;
using Microsoft.EntityFrameworkCore;

namespace Berbergelsin.Api.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<User> Users => Set<User>();
    public DbSet<OtpCode> OtpCodes => Set<OtpCode>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<BarberProfile> BarberProfiles => Set<BarberProfile>();
    public DbSet<BarberDocument> BarberDocuments => Set<BarberDocument>();
    public DbSet<BarberService> BarberServices => Set<BarberService>();
    public DbSet<ServiceDefinition> ServiceDefinitions => Set<ServiceDefinition>();
    public DbSet<BusinessPhoto> BusinessPhotos => Set<BusinessPhoto>();
    public DbSet<ServiceRequest> ServiceRequests => Set<ServiceRequest>();
    public DbSet<ServiceRequestItem> ServiceRequestItems => Set<ServiceRequestItem>();
    public DbSet<PriceOffer> PriceOffers => Set<PriceOffer>();
    public DbSet<OfferOperation> OfferOperations => Set<OfferOperation>();
    public DbSet<RequestOperation> RequestOperations => Set<RequestOperation>();
    public DbSet<RequestStatusHistory> RequestStatusHistories => Set<RequestStatusHistory>();
    public DbSet<ClientAddress> ClientAddresses => Set<ClientAddress>();
    public DbSet<RatingReport> RatingReports => Set<RatingReport>();
    public DbSet<Rating> Ratings => Set<Rating>();
    public DbSet<Notification> Notifications => Set<Notification>();
    public DbSet<NotificationOutbox> NotificationOutbox => Set<NotificationOutbox>();
    public DbSet<DevicePushToken> DevicePushTokens => Set<DevicePushToken>();
    public DbSet<CategoryGroup> CategoryGroups => Set<CategoryGroup>();
    public DbSet<ServiceCategory> ServiceCategories => Set<ServiceCategory>();
    public DbSet<UserNotificationPreference> UserNotificationPreferences =>
        Set<UserNotificationPreference>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        var isNpgsql = Database.IsNpgsql();
        if (isNpgsql) modelBuilder.HasPostgresExtension("postgis");

        modelBuilder.Entity<User>(e =>
        {
            e.Property(u => u.PhoneNumber).HasMaxLength(15).IsRequired();
            e.HasIndex(u => new { u.PhoneNumber, u.Role }).IsUnique();
            e.Property(u => u.FirebaseUid).HasMaxLength(128);
            e.HasIndex(u => new { u.FirebaseUid, u.Role }).IsUnique();
            e.Property(u => u.FirstName).HasMaxLength(100);
            e.Property(u => u.LastName).HasMaxLength(100);
            e.Property(u => u.Email).HasMaxLength(200);
            e.HasIndex(u => new { u.Email, u.Role }).IsUnique();
            e.Property(u => u.ProfileImageUrl).HasMaxLength(2048);
            e.Property(u => u.PasswordHash).HasMaxLength(256);
            e.Property(u => u.ProfileVersion).IsConcurrencyToken();
        });

        modelBuilder.Entity<OtpCode>(e =>
        {
            e.Property(o => o.PhoneNumber).HasMaxLength(15).IsRequired(false);
            e.Property(o => o.Email).HasMaxLength(200);
            e.Property(o => o.Subject).HasMaxLength(128);
            e.HasIndex(o => new { o.PhoneNumber, o.Email, o.Purpose });
            e.Property(o => o.CodeHash).HasMaxLength(128);
        });

        modelBuilder.Entity<RefreshToken>(e =>
        {
            e.Property(r => r.TokenHash).HasMaxLength(128);
            e.HasIndex(r => r.TokenHash).IsUnique();
            e.HasOne(r => r.User).WithMany(u => u.RefreshTokens).HasForeignKey(r => r.UserId);
        });

        modelBuilder.Entity<BarberProfile>(e =>
        {
            e.HasIndex(b => b.UserId).IsUnique();
            e.HasOne(b => b.User).WithOne(u => u.BarberProfile).HasForeignKey<BarberProfile>(b => b.UserId);
            e.Property(b => b.BusinessName).HasMaxLength(200);
            e.Property(b => b.Category).HasMaxLength(80);
            e.Property(b => b.Description).HasMaxLength(1000);
            e.Property(b => b.ServiceMode).HasMaxLength(30);
            e.Property(b => b.City).HasMaxLength(80);
            e.Property(b => b.District).HasMaxLength(80);
            e.Property(b => b.Neighborhood).HasMaxLength(120);
            e.Property(b => b.AddressLine).HasMaxLength(300);
            e.Property(b => b.TcKimlikNo).HasMaxLength(11);
            if (isNpgsql)
            {
                e.Property(b => b.Location).HasColumnType("geography (point, 4326)");
                e.HasIndex(b => b.Location).HasMethod("gist");
            }
            e.Property(b => b.WorkingHours).HasColumnType("jsonb");
        });

        modelBuilder.Entity<BarberDocument>(e =>
        {
            e.HasOne(d => d.BarberProfile).WithMany(b => b.Documents).HasForeignKey(d => d.BarberProfileId);
            e.Property(d => d.StoredFileName).HasMaxLength(100);
            e.Property(d => d.OriginalFileName).HasMaxLength(300);
            e.Property(d => d.ContentType).HasMaxLength(100);
        });

        modelBuilder.Entity<BarberService>(e =>
        {
            e.HasOne(s => s.BarberProfile).WithMany(b => b.Services).HasForeignKey(s => s.BarberProfileId);
            e.Property(s => s.Name).HasMaxLength(150);
            e.Property(s => s.Description).HasMaxLength(500);
            e.Property(s => s.Price).HasColumnType("numeric(10,2)");
            e.Property(s => s.PriceType).HasMaxLength(20);
            e.HasOne(s => s.ServiceDefinition).WithMany(d => d.BusinessServices)
                .HasForeignKey(s => s.ServiceDefinitionId).OnDelete(DeleteBehavior.SetNull);
        });

        modelBuilder.Entity<ServiceDefinition>(e =>
        {
            e.Property(s => s.Name).HasMaxLength(150);
            e.Property(s => s.NormalizedName).HasMaxLength(150);
            e.Property(s => s.CategoryName).HasMaxLength(80);
            e.Property(s => s.NormalizedCategoryName).HasMaxLength(80);
            e.HasIndex(s => new { s.NormalizedCategoryName, s.NormalizedName }).IsUnique();
            e.HasIndex(s => new { s.IsActive, s.SortOrder, s.Name });
        });

        modelBuilder.Entity<BusinessPhoto>(e =>
        {
            e.HasOne(p => p.BarberProfile).WithMany(b => b.Photos).HasForeignKey(p => p.BarberProfileId);
            e.Property(p => p.StoredFileName).HasMaxLength(100);
            e.Property(p => p.OriginalFileName).HasMaxLength(300);
            e.Property(p => p.ContentType).HasMaxLength(100);
            e.Property(p => p.Caption).HasMaxLength(160);
            e.HasIndex(p => new { p.BarberProfileId, p.SortOrder });
        });

        modelBuilder.Entity<ServiceRequest>(e =>
        {
            e.HasOne(r => r.ClientUser).WithMany().HasForeignKey(r => r.ClientUserId);
            e.HasOne(r => r.BarberProfile).WithMany().HasForeignKey(r => r.BarberProfileId);
            e.HasOne(r => r.OriginPriceOffer).WithMany().HasForeignKey(r => r.OriginPriceOfferId);
            e.HasOne(r => r.ClientAddress).WithMany().HasForeignKey(r => r.ClientAddressId).OnDelete(DeleteBehavior.SetNull);
            if (isNpgsql) e.Property(r => r.ClientLocation).HasColumnType("geography (point, 4326)");
            e.Property(r => r.TotalPrice).HasColumnType("numeric(10,2)");
            e.Property(r => r.AddressNote).HasMaxLength(500);
            e.Property(r => r.AddressSnapshot).HasMaxLength(500);
            e.Property(r => r.IdempotencyKey).HasMaxLength(100);
            e.Property(r => r.IdempotencyPayloadHash).HasMaxLength(64);
            e.Property(r => r.CancellationReasonCode).HasMaxLength(50);
            e.Property(r => r.CancellationReasonText).HasMaxLength(500);
            e.Property(r => r.CancelledByRole).HasMaxLength(20);
            e.Property(r => r.RescheduleRequestedByRole).HasMaxLength(20);
            e.Property(r => r.Version).IsConcurrencyToken();
            e.HasIndex(r => new { r.ClientUserId, r.IdempotencyKey }).IsUnique()
                .HasFilter("\"IdempotencyKey\" IS NOT NULL");
            e.HasIndex(r => new { r.BarberProfileId, r.RequestedTime, r.ScheduledEndTime });
        });

        modelBuilder.Entity<RequestStatusHistory>(e =>
        {
            e.HasOne(h => h.Request).WithMany(r => r.StatusHistory).HasForeignKey(h => h.RequestId);
            e.Property(h => h.ChangedByRole).HasMaxLength(20);
            e.Property(h => h.ReasonCode).HasMaxLength(50);
            e.Property(h => h.ReasonText).HasMaxLength(500);
            e.HasIndex(h => new { h.RequestId, h.CreatedAt, h.Id });
        });

        modelBuilder.Entity<RequestOperation>(e =>
        {
            e.Property(o => o.IdempotencyKey).HasMaxLength(100);
            e.Property(o => o.PayloadHash).HasMaxLength(64);
            e.Property(o => o.ResultJson).HasColumnType("jsonb");
            e.HasIndex(o => new { o.UserId, o.IdempotencyKey }).IsUnique();
        });

        modelBuilder.Entity<ClientAddress>(e =>
        {
            e.HasOne(a => a.User).WithMany().HasForeignKey(a => a.UserId).OnDelete(DeleteBehavior.Restrict);
            e.Property(a => a.Label).HasMaxLength(50);
            e.Property(a => a.PlaceId).HasMaxLength(300);
            e.Property(a => a.FormattedAddress).HasMaxLength(500);
            e.Property(a => a.Province).HasMaxLength(100);
            e.Property(a => a.District).HasMaxLength(100);
            e.Property(a => a.Neighborhood).HasMaxLength(150);
            e.Property(a => a.Street).HasMaxLength(150);
            e.Property(a => a.StreetNumber).HasMaxLength(30);
            e.Property(a => a.PostalCode).HasMaxLength(20);
            e.Property(a => a.AddressLine).HasMaxLength(500);
            e.Property(a => a.Version).IsConcurrencyToken();
            e.HasIndex(a => new { a.UserId, a.IsDefault }).IsUnique()
                .HasFilter("\"IsDefault\" = TRUE AND \"IsDeleted\" = FALSE");
            e.HasIndex(a => new { a.UserId, a.IsDeleted, a.UpdatedAt });
        });
        modelBuilder.Entity<ServiceRequestItem>(e =>
        {
            e.HasOne(i => i.ServiceRequest).WithMany(r => r.Items).HasForeignKey(i => i.ServiceRequestId);
            e.Property(i => i.ServiceName).HasMaxLength(150);
            e.Property(i => i.PriceAtRequest).HasColumnType("numeric(10,2)");
        });

        modelBuilder.Entity<Rating>(e =>
        {
            e.HasOne(r => r.ServiceRequest).WithMany().HasForeignKey(r => r.ServiceRequestId);
            e.HasOne(r => r.RaterUser).WithMany().HasForeignKey(r => r.RaterUserId)
                .OnDelete(DeleteBehavior.Restrict);
            e.HasOne(r => r.RatedUser).WithMany().HasForeignKey(r => r.RatedUserId)
                .OnDelete(DeleteBehavior.Restrict);
            e.HasIndex(r => new { r.ServiceRequestId, r.RaterUserId }).IsUnique();
            e.HasIndex(r => r.RatedUserId);
            e.Property(r => r.Comment).HasMaxLength(600);
            e.Property(r=>r.Version).IsConcurrencyToken();
        });
        modelBuilder.Entity<RatingReport>(e=>{e.HasOne(r=>r.Rating).WithMany().HasForeignKey(r=>r.RatingId).OnDelete(DeleteBehavior.Restrict);e.Property(r=>r.ReasonCode).HasMaxLength(50);e.Property(r=>r.Description).HasMaxLength(500);e.HasIndex(r=>new{r.RatingId,r.ReporterUserId,r.ReasonCode}).IsUnique();});

        modelBuilder.Entity<Notification>(e =>
        {
            e.HasOne(n => n.User).WithMany().HasForeignKey(n => n.UserId).OnDelete(DeleteBehavior.Restrict);
            e.Property(n => n.Type).HasMaxLength(50);
            e.Property(n => n.Title).HasMaxLength(120);
            e.Property(n => n.Body).HasMaxLength(300);
            e.Property(n => n.EntityType).HasMaxLength(30);
            e.Property(n => n.Route).HasMaxLength(160);
            e.Property(n => n.DeduplicationKey).HasMaxLength(200);
            e.Property(n => n.DataJson).HasColumnType("jsonb");
            e.HasIndex(n => new { n.UserId, n.DeduplicationKey }).IsUnique();
            e.HasIndex(n => new { n.UserId, n.IsRead, n.CreatedAt, n.Id });
        });

        modelBuilder.Entity<NotificationOutbox>(e =>
        {
            e.HasOne(o => o.Notification).WithOne().HasForeignKey<NotificationOutbox>(o => o.NotificationId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(o => o.NotificationId).IsUnique();
            e.HasIndex(o => new { o.Status, o.NextAttemptAt });
            e.HasIndex(o => new { o.Status, o.LockedAt });
            e.Property(o => o.EventType).HasMaxLength(80);
            e.Property(o => o.PayloadJson).HasColumnType("jsonb");
            e.Property(o => o.LockedBy).HasMaxLength(100);
            e.Property(o => o.LastErrorCode).HasMaxLength(80);
            e.Property(o => o.ConcurrencyToken).IsConcurrencyToken();
        });
        modelBuilder.Entity<DevicePushToken>(e =>
        {
            e.HasOne(d => d.User).WithMany().HasForeignKey(d => d.UserId).OnDelete(DeleteBehavior.Restrict);
            e.Property(d => d.Platform).HasMaxLength(10);
            e.Property(d => d.Token).HasMaxLength(4096);
            e.Property(d => d.DeviceId).HasMaxLength(200);
            e.HasIndex(d => d.Token).IsUnique();
            e.HasIndex(d => new { d.UserId, d.DeviceId }).IsUnique();
            e.HasIndex(d => new { d.UserId, d.IsActive });
        });

        modelBuilder.Entity<UserNotificationPreference>(e =>
        {
            e.HasOne(p => p.User).WithMany()
                .HasForeignKey(p => p.UserId).OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(p => p.UserId).IsUnique();
        });

        modelBuilder.Entity<PriceOffer>(e =>
        {
            e.HasOne(o => o.ClientUser).WithMany().HasForeignKey(o => o.ClientUserId);
            e.HasOne(o => o.BarberProfile).WithMany().HasForeignKey(o => o.BarberProfileId);
            e.HasOne(o => o.SourceServiceRequest).WithMany().HasForeignKey(o => o.SourceServiceRequestId);
            if (isNpgsql) e.Property(o => o.ClientLocation).HasColumnType("geography (point, 4326)");
            e.Property(o => o.ProposedPrice).HasColumnType("numeric(10,2)");
            e.Property(o => o.CounterPrice).HasColumnType("numeric(10,2)");
            e.Property(o => o.Note).HasMaxLength(500);
            e.Property(o => o.AcceptedPrice).HasColumnType("numeric(10,2)");
            e.Property(o => o.Version).IsConcurrencyToken();
            e.HasIndex(o => new { o.ClientUserId, o.BarberProfileId, o.Status });
        });

        modelBuilder.Entity<OfferOperation>(e =>
        {
            e.Property(o => o.IdempotencyKey).HasMaxLength(100);
            e.Property(o => o.PayloadHash).HasMaxLength(64);
            e.Property(o => o.ResultJson).HasColumnType("jsonb");
            e.HasIndex(o => new { o.UserId, o.IdempotencyKey }).IsUnique();
        });

        modelBuilder.Entity<CategoryGroup>(e =>
        {
            e.Property(g => g.Name).HasMaxLength(100).IsRequired();
            e.Property(g => g.Icon).HasMaxLength(50);
            e.HasIndex(g => g.Name).IsUnique();
        });

        modelBuilder.Entity<ServiceCategory>(e =>
        {
            e.Property(c => c.Name).HasMaxLength(100).IsRequired();
            e.HasIndex(c => new { c.GroupId, c.Name }).IsUnique();
            e.HasOne(c => c.Group).WithMany(g => g.Categories)
                .HasForeignKey(c => c.GroupId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<BarberProfile>(e =>
        {
            e.HasOne(b => b.ServiceCategory).WithMany()
                .HasForeignKey(b => b.CategoryId).OnDelete(DeleteBehavior.SetNull);
        });
    }
}
