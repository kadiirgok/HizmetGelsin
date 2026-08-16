using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
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

public sealed class OfferEndpointTests
{
    [Fact] public async Task Create_requires_customer_and_active_account()
    {
        using var f=new OfferApiFactory();f.Seed();
        Assert.Equal(HttpStatusCode.Unauthorized,(await Create(f.CreateClient(),f,"anon-key-123")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden,(await Create(f.Client(f.BarberId,"Berber"),f,"barber-key-123")).StatusCode);
    }

    [Fact] public async Task Create_sets_server_expiration_and_is_idempotent()
    {
        using var f=new OfferApiFactory();f.Seed();var c=f.Client(f.ClientId,"Musteri");
        var first=await Create(c,f,"create-key-123");var second=await Create(c,f,"create-key-123");
        Assert.Equal(HttpStatusCode.OK,first.StatusCode);Assert.Equal(HttpStatusCode.OK,second.StatusCode);
        var a=await first.Content.ReadFromJsonAsync<JsonElement>();var b=await second.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(a.GetProperty("id").GetGuid(),b.GetProperty("id").GetGuid());
        Assert.True(a.GetProperty("expiresAt").GetDateTime()>a.GetProperty("createdAt").GetDateTime());
        using var s=f.Services.CreateScope();Assert.Equal(1,await s.ServiceProvider.GetRequiredService<AppDbContext>().PriceOffers.CountAsync());
    }

    [Fact] public async Task Same_key_changed_payload_conflicts_and_price_is_validated()
    {
        using var f=new OfferApiFactory();f.Seed();var c=f.Client(f.ClientId,"Musteri");
        Assert.Equal(HttpStatusCode.OK,(await Create(c,f,"payload-key-123")).StatusCode);
        var conflict=await Create(c,f,"payload-key-123",price:900);Assert.Equal(HttpStatusCode.Conflict,conflict.StatusCode);
        Assert.Contains("offer_idempotency_conflict",await conflict.Content.ReadAsStringAsync());
        Assert.Contains("offer_price_invalid",await (await Create(c,f,"price-key-123",price:-1)).Content.ReadAsStringAsync());
    }

    [Fact] public async Task Barber_offer_requires_own_active_request()
    {
        using var f=new OfferApiFactory();f.Seed();
        var own=await FromRequest(f.Client(f.BarberId,"Berber"),f,"own-key-123");Assert.Equal(HttpStatusCode.OK,own.StatusCode);
        var other=await FromRequest(f.Client(f.OtherBarberId,"Berber"),f,"other-key-123");Assert.Equal(HttpStatusCode.Forbidden,other.StatusCode);
    }

    [Fact] public async Task Pending_accept_creates_one_request_and_retry_returns_same_result()
    {
        using var f=new OfferApiFactory();f.Seed();var client=f.Client(f.ClientId,"Musteri");
        var created=await (await Create(client,f,"accept-create-123")).Content.ReadFromJsonAsync<JsonElement>();var id=created.GetProperty("id").GetGuid();
        var barber=f.Client(f.BarberId,"Berber");var one=await Action(barber,$"/api/offers/{id}/accept","accept-action-123");
        var two=await Action(barber,$"/api/offers/{id}/accept","accept-action-123");
        Assert.Equal(HttpStatusCode.OK,one.StatusCode);Assert.Equal(await one.Content.ReadAsStringAsync(),await two.Content.ReadAsStringAsync());
        using var s=f.Services.CreateScope();var db=s.ServiceProvider.GetRequiredService<AppDbContext>();Assert.Single(await db.ServiceRequests.Where(r=>r.OriginPriceOfferId==id).ToListAsync());
        Assert.Equal(500,(await db.PriceOffers.FindAsync(id))!.AcceptedPrice);
    }

    [Fact] public async Task Counter_can_only_be_resolved_by_owner_customer()
    {
        using var f=new OfferApiFactory();f.Seed();var created=await (await Create(f.Client(f.ClientId,"Musteri"),f,"counter-create-123")).Content.ReadFromJsonAsync<JsonElement>();var id=created.GetProperty("id").GetGuid();
        var counter=await Action(f.Client(f.BarberId,"Berber"),$"/api/offers/{id}/counter","counter-action-123",new{counterPrice=650});Assert.Equal(HttpStatusCode.OK,counter.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden,(await Action(f.Client(f.OtherClientId,"Musteri"),$"/api/offers/{id}/accept-counter","other-client-123")).StatusCode);
        Assert.Equal(HttpStatusCode.OK,(await Action(f.Client(f.ClientId,"Musteri"),$"/api/offers/{id}/accept-counter","owner-client-123")).StatusCode);
    }

    [Fact] public async Task Expired_offer_is_lazy_expired_and_cannot_transition()
    {
        using var f=new OfferApiFactory();f.Seed();var id=f.AddOffer(OfferStatus.Pending,DateTime.UtcNow.AddMinutes(-1));
        var response=await Action(f.Client(f.BarberId,"Berber"),$"/api/offers/{id}/accept","expired-action-123");
        Assert.Equal(HttpStatusCode.Conflict,response.StatusCode);Assert.Contains("offer_expired",await response.Content.ReadAsStringAsync());
        using var s=f.Services.CreateScope();Assert.Equal(OfferStatus.Expired,(await s.ServiceProvider.GetRequiredService<AppDbContext>().PriceOffers.FindAsync(id))!.Status);
    }

    [Fact] public async Task Accepting_barber_offer_updates_source_request_without_duplicate()
    {
        using var f=new OfferApiFactory();f.Seed();
        var json=await (await FromRequest(f.Client(f.BarberId,"Berber"),f,"source-offer-123")).Content.ReadFromJsonAsync<JsonElement>();
        var id=json.GetProperty("id").GetGuid();
        Assert.Equal(HttpStatusCode.OK,(await Action(f.Client(f.ClientId,"Musteri"),$"/api/offers/{id}/accept-counter","source-accept-123")).StatusCode);
        using var s=f.Services.CreateScope();var db=s.ServiceProvider.GetRequiredService<AppDbContext>();
        Assert.Equal(1,await db.ServiceRequests.CountAsync());var source=await db.ServiceRequests.FindAsync(f.SourceRequestId);
        Assert.Equal(id,source!.OriginPriceOfferId);Assert.Equal(600,source.TotalPrice);Assert.Equal(RequestStatus.Accepted,source.Status);
    }

    [Fact] public async Task Concurrent_accept_and_reject_allow_only_one_transition()
    {
        using var f=new OfferApiFactory();f.Seed();var id=f.AddOffer(OfferStatus.Pending,DateTime.UtcNow.AddHours(1));
        var a=Action(f.Client(f.BarberId,"Berber"),$"/api/offers/{id}/accept","race-accept-123");
        var b=Action(f.Client(f.BarberId,"Berber"),$"/api/offers/{id}/reject","race-reject-123");
        var results=await Task.WhenAll(a,b);Assert.Single(results,x=>x.StatusCode==HttpStatusCode.OK);Assert.Single(results,x=>x.StatusCode==HttpStatusCode.Conflict);
    }

    private static Task<HttpResponseMessage>Create(HttpClient c,OfferApiFactory f,string key,decimal price=500){c.DefaultRequestHeaders.Remove("Idempotency-Key");c.DefaultRequestHeaders.Add("Idempotency-Key",key);return c.PostAsJsonAsync("/api/offers",new{barberProfileId=f.ProfileId,proposedPrice=price,requestedTime=f.ValidTime,lat=41d,lng=29d,note="test"});}
    private static Task<HttpResponseMessage>FromRequest(HttpClient c,OfferApiFactory f,string key){c.DefaultRequestHeaders.Remove("Idempotency-Key");c.DefaultRequestHeaders.Add("Idempotency-Key",key);return c.PostAsJsonAsync("/api/offers/from-request",new{serviceRequestId=f.SourceRequestId,price=600,requestedTime=DateTimeOffset.UtcNow.AddDays(2),note="test"});}
    private static Task<HttpResponseMessage>Action(HttpClient c,string path,string key,object? body=null){c.DefaultRequestHeaders.Remove("Idempotency-Key");c.DefaultRequestHeaders.Add("Idempotency-Key",key);return c.PostAsJsonAsync(path,body??new{});}
}

public sealed class OfferApiFactory:WebApplicationFactory<Program>
{
    private bool seeded;public Guid ClientId{get;}=Guid.NewGuid();public Guid OtherClientId{get;}=Guid.NewGuid();public Guid BarberId{get;}=Guid.NewGuid();public Guid OtherBarberId{get;}=Guid.NewGuid();public Guid ProfileId{get;}=Guid.NewGuid();public Guid SourceRequestId{get;}=Guid.NewGuid();public DateTimeOffset ValidTime{get;}=DateTimeOffset.UtcNow.AddDays(2);
    protected override void ConfigureWebHost(IWebHostBuilder b){b.UseEnvironment("Testing");b.UseSetting("Jwt:Key","integration-test-key-with-at-least-32-characters");b.UseSetting("Jwt:Issuer","integration-tests");b.UseSetting("Jwt:Audience","integration-tests");b.UseSetting("SmsSettings:UseConsoleSender","true");b.ConfigureServices(s=>{s.RemoveAll<DbContextOptions<AppDbContext>>();s.AddDbContext<AppDbContext>(o=>o.UseInMemoryDatabase($"offers-{ClientId}"));s.AddAuthentication(o=>{o.DefaultAuthenticateScheme="ClientProfileTest";o.DefaultChallengeScheme="ClientProfileTest";o.DefaultForbidScheme="ClientProfileTest";}).AddScheme<AuthenticationSchemeOptions,ClientProfileTestAuthHandler>("ClientProfileTest",_=>{});});}
    public void Seed(){if(seeded)return;using var s=Services.CreateScope();var db=s.ServiceProvider.GetRequiredService<AppDbContext>();var client=User(ClientId,"11",UserRole.Musteri);var other=User(OtherClientId,"12",UserRole.Musteri);var barber=User(BarberId,"13",UserRole.Berber);var otherBarber=User(OtherBarberId,"14",UserRole.Berber);var profile=new BarberProfile{Id=ProfileId,UserId=BarberId,User=barber,Status=BarberStatus.Approved,IsOnline=true,AcceptsOffers=true,CreatedAt=DateTime.UtcNow};var otherProfile=new BarberProfile{Id=Guid.NewGuid(),UserId=OtherBarberId,User=otherBarber,Status=BarberStatus.Approved,IsOnline=true,CreatedAt=DateTime.UtcNow};db.AddRange(client,other,barber,otherBarber,profile,otherProfile);db.ServiceRequests.Add(new ServiceRequest{Id=SourceRequestId,ClientUserId=ClientId,ClientUser=client,BarberProfileId=ProfileId,BarberProfile=profile,Status=RequestStatus.Pending,RequestedTime=DateTimeOffset.UtcNow.AddDays(2),ScheduledEndTime=DateTimeOffset.UtcNow.AddDays(2).AddHours(1),ClientLocation=new Point(29,41){SRID=4326},TotalPrice=400,CreatedAt=DateTime.UtcNow,UpdatedAt=DateTime.UtcNow,CreatedBy=ClientId});db.SaveChanges();seeded=true;}
    private static User User(Guid id,string phone,UserRole role)=>new(){Id=id,PhoneNumber="9055500000"+phone,Role=role,AccountStatus=AccountStatus.Active,OnboardingCompleted=true,CreatedAt=DateTime.UtcNow};
    public HttpClient Client(Guid id,string role){Seed();var c=CreateClient();c.DefaultRequestHeaders.Add("X-Test-UserId",id.ToString());c.DefaultRequestHeaders.Add("X-Test-Role",role);return c;}
    public Guid AddOffer(OfferStatus status,DateTime expires){Seed();using var s=Services.CreateScope();var db=s.ServiceProvider.GetRequiredService<AppDbContext>();var id=Guid.NewGuid();db.PriceOffers.Add(new PriceOffer{Id=id,ClientUserId=ClientId,BarberProfileId=ProfileId,ProposedPrice=500,Status=status,RequestedTime=DateTimeOffset.UtcNow.AddDays(2),ClientLocation=new Point(29,41){SRID=4326},CreatedAt=DateTime.UtcNow.AddHours(-1),ExpiresAt=expires});db.SaveChanges();return id;}
}
