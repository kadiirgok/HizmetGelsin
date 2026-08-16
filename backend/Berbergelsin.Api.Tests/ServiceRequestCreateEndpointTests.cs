using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Berbergelsin.Api.Controllers;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Entities;
using Berbergelsin.Api.Enums;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using NetTopologySuite.Geometries;
using Xunit;

namespace Berbergelsin.Api.Tests;

public sealed class ServiceRequestCreateEndpointTests
{
    [Fact] public async Task Authentication_and_customer_role_are_required()
    {
        using var f = new RequestApiFactory(); f.Seed();
        Assert.Equal(HttpStatusCode.Unauthorized, (await Post(f.CreateClient(), f, "anon-key-123")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await Post(f.Client(f.BarberUserId, "Berber"), f, "barber-key-123")).StatusCode);
    }

    [Fact] public async Task Valid_request_snapshots_backend_price_and_audit_fields()
    {
        using var f = new RequestApiFactory(); f.Seed(); var c = f.Client(f.ClientId, "Musteri");
        var response = await Post(c, f, "valid-key-123");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var json = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(175m, json.GetProperty("totalPrice").GetDecimal());
        Assert.Equal("Pending", json.GetProperty("status").GetString());
        using var scope = f.Services.CreateScope(); var saved = await scope.ServiceProvider.GetRequiredService<AppDbContext>().ServiceRequests.SingleAsync();
        Assert.Equal(f.ClientId, saved.ClientUserId); Assert.Equal(f.ClientId, saved.CreatedBy);
        Assert.Equal("valid-key-123", saved.IdempotencyKey); Assert.True(saved.ScheduledEndTime > saved.RequestedTime);
    }

    [Fact] public async Task Same_key_and_payload_returns_same_request_without_duplicate()
    {
        using var f = new RequestApiFactory(); f.Seed(); var c = f.Client(f.ClientId, "Musteri");
        var one = await (await Post(c, f, "retry-key-123")).Content.ReadFromJsonAsync<JsonElement>();
        var two = await (await Post(c, f, "retry-key-123")).Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(one.GetProperty("id").GetGuid(), two.GetProperty("id").GetGuid());
        using var scope = f.Services.CreateScope(); Assert.Equal(1, await scope.ServiceProvider.GetRequiredService<AppDbContext>().ServiceRequests.CountAsync());
    }

    [Fact] public async Task Same_key_with_changed_payload_conflicts()
    {
        using var f = new RequestApiFactory(); f.Seed(); var c = f.Client(f.ClientId, "Musteri");
        Assert.Equal(HttpStatusCode.OK, (await Post(c, f, "conflict-key-123")).StatusCode);
        using var response = await Post(c, f, "conflict-key-123", note: "different");
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Contains("request_idempotency_conflict", await response.Content.ReadAsStringAsync());
    }

    [Fact] public async Task Duplicate_unknown_and_inactive_services_are_rejected()
    {
        using var f = new RequestApiFactory(); f.Seed(); var c = f.Client(f.ClientId, "Musteri");
        Assert.Contains("request_invalid", await (await Post(c, f, "dup-key-123", services: [f.ServiceId, f.ServiceId])).Content.ReadAsStringAsync());
        Assert.Contains("request_service_unavailable", await (await Post(c, f, "unknown-key-123", services: [Guid.NewGuid()])).Content.ReadAsStringAsync());
        Assert.Contains("request_service_unavailable", await (await Post(c, f, "inactive-key-123", services: [f.InactiveServiceId])).Content.ReadAsStringAsync());
    }

    [Fact] public async Task Outside_hours_and_overlap_are_rejected_but_cancelled_does_not_block()
    {
        using var f = new RequestApiFactory(); f.Seed(); var c = f.Client(f.ClientId, "Musteri");
        using var closed = await Post(c, f, "closed-key-123", time: f.ValidTime.AddHours(10));
        Assert.Contains("request_outside_working_hours", await closed.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.OK, (await Post(c, f, "first-key-123")).StatusCode);
        using var overlap = await Post(c, f, "overlap-key-123", time: f.ValidTime.AddMinutes(15));
        Assert.Contains("request_time_conflict", await overlap.Content.ReadAsStringAsync());
        using (var scope = f.Services.CreateScope()) { var db = scope.ServiceProvider.GetRequiredService<AppDbContext>(); (await db.ServiceRequests.SingleAsync()).Status = RequestStatus.Cancelled; await db.SaveChangesAsync(); }
        Assert.Equal(HttpStatusCode.OK, (await Post(c, f, "after-cancel-key-123", time: f.ValidTime.AddMinutes(15))).StatusCode);
    }

    [Fact] public void Working_hours_are_evaluated_in_istanbul_and_require_full_duration()
    {
        var start = new DateTimeOffset(2026, 7, 16, 7, 0, 0, TimeSpan.Zero); // 10:00 Istanbul
        const string hours = "[{\"day\":4,\"open\":\"09:00\",\"close\":\"11:00\",\"closed\":false}]";
        Assert.True(RequestsController.InsideWorkingHours(hours, start, start.AddMinutes(60)));
        Assert.False(RequestsController.InsideWorkingHours(hours, start, start.AddMinutes(121)));
    }

    [Fact] public async Task Concurrent_overlapping_requests_create_only_one_active_record()
    {
        using var f = new RequestApiFactory(); f.Seed();
        var first = Post(f.Client(f.ClientId, "Musteri"), f, "race-one-123");
        var second = Post(f.Client(f.OtherClientId, "Musteri"), f, "race-two-123");
        var results = await Task.WhenAll(first, second);
        Assert.Single(results, x => x.StatusCode == HttpStatusCode.OK);
        Assert.Single(results, x => x.StatusCode == HttpStatusCode.Conflict);
        using var scope = f.Services.CreateScope();
        Assert.Equal(1, await scope.ServiceProvider.GetRequiredService<AppDbContext>().ServiceRequests.CountAsync());
    }

    [Fact] public async Task Same_idempotency_key_is_scoped_to_customer()
    {
        using var f = new RequestApiFactory(); f.Seed();
        Assert.Equal(HttpStatusCode.OK, (await Post(f.Client(f.ClientId, "Musteri"), f, "shared-key-123")).StatusCode);
        using (var scope = f.Services.CreateScope()) { var db=scope.ServiceProvider.GetRequiredService<AppDbContext>(); (await db.ServiceRequests.SingleAsync()).Status=RequestStatus.Cancelled; await db.SaveChangesAsync(); }
        Assert.Equal(HttpStatusCode.OK, (await Post(f.Client(f.OtherClientId, "Musteri"), f, "shared-key-123")).StatusCode);
    }

    private static Task<HttpResponseMessage> Post(HttpClient c, RequestApiFactory f, string key, DateTimeOffset? time = null,
        Guid[]? services = null, string? note = null)
    {
        c.DefaultRequestHeaders.Remove("Idempotency-Key"); c.DefaultRequestHeaders.Add("Idempotency-Key", key);
        return c.PostAsJsonAsync("/api/requests", new { barberProfileId = f.ProfileId,
            serviceIds = services ?? [f.ServiceId], requestedTime = time ?? f.ValidTime, lat = 41.0001, lng = 29.0001, addressNote = note });
    }
}

public sealed class RequestApiFactory : WebApplicationFactory<Program>
{
    private bool seeded;
    public Guid ClientId { get; } = Guid.NewGuid(); public Guid OtherClientId { get; } = Guid.NewGuid(); public Guid BarberUserId { get; } = Guid.NewGuid();
    public Guid ProfileId { get; } = Guid.NewGuid(); public Guid ServiceId { get; } = Guid.NewGuid();
    public Guid AddressId { get; } = Guid.NewGuid();
    public Guid InactiveServiceId { get; } = Guid.NewGuid();
    public DateTimeOffset ValidTime { get; } = NextThursday();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing"); builder.UseSetting("Jwt:Key", "integration-test-key-with-at-least-32-characters");
        builder.UseSetting("Jwt:Issuer", "integration-tests"); builder.UseSetting("Jwt:Audience", "integration-tests"); builder.UseSetting("SmsSettings:UseConsoleSender", "true");
        builder.ConfigureServices(services => { services.RemoveAll<DbContextOptions<AppDbContext>>();
            services.AddDbContext<AppDbContext>(o => o.UseInMemoryDatabase($"requests-{ClientId}"));
            services.AddAuthentication(o => { o.DefaultAuthenticateScheme = "ClientProfileTest"; o.DefaultChallengeScheme = "ClientProfileTest"; o.DefaultForbidScheme = "ClientProfileTest"; })
                .AddScheme<AuthenticationSchemeOptions, ClientProfileTestAuthHandler>("ClientProfileTest", _ => { }); });
    }

    public void Seed()
    {
        if (seeded) return; using var s = Services.CreateScope(); var db = s.ServiceProvider.GetRequiredService<AppDbContext>();
        var client = new User { Id=ClientId,PhoneNumber="905550000011",Role=UserRole.Musteri,OnboardingCompleted=true,CreatedAt=DateTime.UtcNow };
        var other = new User { Id=OtherClientId,PhoneNumber="905550000013",Role=UserRole.Musteri,OnboardingCompleted=true,CreatedAt=DateTime.UtcNow };
        var barber = new User { Id=BarberUserId,PhoneNumber="905550000012",Role=UserRole.Berber,OnboardingCompleted=true,CreatedAt=DateTime.UtcNow };
        var profile = new BarberProfile { Id=ProfileId,UserId=BarberUserId,User=barber,Status=BarberStatus.Approved,IsOnline=true,
            ServiceMode="Both",ServiceRadiusKm=20,Location=new Point(29,41){SRID=4326},
            WorkingHours="[{\"day\":4,\"open\":\"09:00\",\"close\":\"18:00\",\"closed\":false}]",CreatedAt=DateTime.UtcNow };
        db.AddRange(client,other,barber,profile); db.BarberServices.AddRange(
            new BarberService { Id=ServiceId,BarberProfileId=ProfileId,Name="Saç",Price=175,DurationMinutes=60,IsActive=true },
            new BarberService { Id=InactiveServiceId,BarberProfileId=ProfileId,Name="Pasif",Price=1,IsActive=false });
        db.SaveChanges(); seeded=true;
    }
    public void SeedAddress()
    {
        Seed(); using var s = Services.CreateScope(); var db = s.ServiceProvider.GetRequiredService<AppDbContext>();
        if (db.ClientAddresses.Any(a => a.Id == AddressId)) return;
        db.ClientAddresses.Add(new ClientAddress { Id=AddressId, UserId=ClientId, Label="Ev", AddressLine="Bağdat Caddesi 1",
            District="Kadıköy", Province="İstanbul", Latitude=41.0002, Longitude=29.0002,
            CreatedAt=DateTime.UtcNow, UpdatedAt=DateTime.UtcNow });
        db.SaveChanges();
    }
    public HttpClient Client(Guid id,string role) { Seed(); var c=CreateClient(); c.DefaultRequestHeaders.Add("X-Test-UserId",id.ToString()); c.DefaultRequestHeaders.Add("X-Test-Role",role); return c; }
    private static DateTimeOffset NextThursday() { var now=DateTimeOffset.UtcNow.AddDays(2); while(now.DayOfWeek!=DayOfWeek.Thursday) now=now.AddDays(1); return new DateTimeOffset(now.Year,now.Month,now.Day,10,0,0,TimeSpan.FromHours(3)); }
}
