using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Encodings.Web;
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
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using NetTopologySuite.Geometries;
using Xunit;

namespace Berbergelsin.Api.Tests;

public sealed class BarberDetailEndpointTests : IClassFixture<BarberDetailFactory>
{
    private readonly BarberDetailFactory f;
    public BarberDetailEndpointTests(BarberDetailFactory factory) => f = factory;

    [Fact] public async Task Visible_business_is_200_and_contract_is_safe()
    {
        var response = await f.Client(f.ClientId, "Musteri").GetAsync($"/api/barbers/{f.ProfileId}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync()); var root = json.RootElement;
        Assert.False(root.TryGetProperty("phoneNumber", out _)); Assert.False(root.TryGetProperty("tcKimlikNo", out _));
        Assert.False(root.TryGetProperty("documents", out _)); Assert.False(root.TryGetProperty("user", out _));
        Assert.Single(root.GetProperty("services").EnumerateArray());
        Assert.Equal(125, root.GetProperty("services")[0].GetProperty("price").GetDecimal());
        Assert.Equal("/api/barbers/" + f.ProfileId + "/logo", root.GetProperty("profileImageUrl").GetString());
        Assert.Contains("/photos/", root.GetProperty("coverImageUrl").GetString());
        Assert.Equal(10, root.GetProperty("serviceRadiusKm").GetInt32());
    }

    [Fact] public async Task Anonymous_is_401()
        => Assert.Equal(HttpStatusCode.Unauthorized, (await f.CreateClient().GetAsync($"/api/barbers/{f.ProfileId}")).StatusCode);

    [Fact] public async Task Unknown_is_404()
        => Assert.Equal(HttpStatusCode.NotFound, (await f.Client(f.ClientId,"Musteri").GetAsync($"/api/barbers/{Guid.NewGuid()}")).StatusCode);

    [Fact] public async Task Offline_and_deleted_account_are_404()
    {
        await f.SetVisible(false); Assert.Equal(HttpStatusCode.NotFound,(await f.Client(f.ClientId,"Musteri").GetAsync($"/api/barbers/{f.ProfileId}")).StatusCode);
        await f.SetVisible(true, AccountStatus.DeletionPending); Assert.Equal(HttpStatusCode.NotFound,(await f.Client(f.ClientId,"Musteri").GetAsync($"/api/barbers/{f.ProfileId}")).StatusCode);
        await f.SetVisible(true, AccountStatus.Active);
    }

    [Fact] public async Task Other_barber_is_forbidden()
        => Assert.Equal(HttpStatusCode.Forbidden,(await f.Client(Guid.NewGuid(),"Berber",Guid.NewGuid()).GetAsync($"/api/barbers/{f.ProfileId}")).StatusCode);

    [Fact] public async Task Reviews_are_paged_stable_and_average_is_correct()
    {
        var page1 = await f.Client(f.ClientId,"Musteri").GetFromJsonAsync<JsonElement>($"/api/barbers/{f.ProfileId}/reviews?page=1&pageSize=2");
        var page2 = await f.Client(f.ClientId,"Musteri").GetFromJsonAsync<JsonElement>($"/api/barbers/{f.ProfileId}/reviews?page=2&pageSize=2");
        Assert.Equal(3,page1.GetProperty("totalCount").GetInt32()); Assert.True(page1.GetProperty("hasNextPage").GetBoolean());
        Assert.Equal(4,page1.GetProperty("averageRating").GetDouble()); Assert.Equal(2,page1.GetProperty("items").GetArrayLength());
        Assert.Single(page2.GetProperty("items").EnumerateArray());
        var again = await f.Client(f.ClientId,"Musteri").GetStringAsync($"/api/barbers/{f.ProfileId}/reviews?page=1&pageSize=2");
        Assert.Equal(page1.GetRawText(), again);
    }

    [Fact] public async Task Empty_reviews_return_empty_page()
    {
        await using var scope=f.Services.CreateAsyncScope();var db=scope.ServiceProvider.GetRequiredService<AppDbContext>();db.Ratings.RemoveRange(db.Ratings);await db.SaveChangesAsync();
        var json=await f.Client(f.ClientId,"Musteri").GetFromJsonAsync<JsonElement>($"/api/barbers/{f.ProfileId}/reviews");
        Assert.Equal(0,json.GetProperty("totalCount").GetInt32());Assert.Equal(0,json.GetProperty("items").GetArrayLength());
        await f.RestoreRatings();
    }

    [Fact] public async Task Availability_uses_real_working_hours_without_slots()
    {
        var json=await f.Client(f.ClientId,"Musteri").GetFromJsonAsync<JsonElement>($"/api/barbers/{f.ProfileId}/availability-summary?date=2026-07-16");
        Assert.True(json.GetProperty("isWorkingDay").GetBoolean()); Assert.Single(json.GetProperty("workingIntervals").EnumerateArray());
        Assert.Equal("09:00",json.GetProperty("workingIntervals")[0].GetProperty("open").GetString());
        Assert.Equal("working_hours_only",json.GetProperty("precision").GetString()); Assert.False(json.TryGetProperty("slots",out _));
    }

    [Fact] public async Task Invalid_paging_and_date_are_safe_400()
    {
        Assert.Equal(HttpStatusCode.BadRequest,(await f.Client(f.ClientId,"Musteri").GetAsync($"/api/barbers/{f.ProfileId}/reviews?page=0")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest,(await f.Client(f.ClientId,"Musteri").GetAsync($"/api/barbers/{f.ProfileId}/availability-summary")).StatusCode);
    }
}

public sealed class BarberDetailFactory : WebApplicationFactory<Program>
{
    public Guid ClientId {get;}=Guid.NewGuid(); public Guid BarberId {get;}=Guid.NewGuid(); public Guid ProfileId {get;}=Guid.NewGuid();
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing"); builder.UseSetting("Jwt:Key","integration-test-key-with-at-least-32-characters");
        builder.UseSetting("Jwt:Issuer","integration-tests");builder.UseSetting("Jwt:Audience","integration-tests");builder.UseSetting("SmsSettings:UseConsoleSender","true");
        builder.ConfigureServices(services=>{services.RemoveAll<DbContextOptions<AppDbContext>>();services.AddDbContext<AppDbContext>(o=>o.UseInMemoryDatabase("detail-"+ProfileId));
            services.AddAuthentication(o=>{o.DefaultAuthenticateScheme="DetailTest";o.DefaultChallengeScheme="DetailTest";o.DefaultForbidScheme="DetailTest";}).AddScheme<AuthenticationSchemeOptions,DetailAuthHandler>("DetailTest",_=>{});});
    }
    public HttpClient Client(Guid id,string role,Guid? profile=null){EnsureSeed();var c=CreateClient();c.DefaultRequestHeaders.Add("X-Test-UserId",id.ToString());c.DefaultRequestHeaders.Add("X-Test-Role",role);if(profile.HasValue)c.DefaultRequestHeaders.Add("X-Test-BarberProfileId",profile.ToString());return c;}
    private bool seeded;
    private void EnsureSeed(){if(seeded)return;using var s=Services.CreateScope();var db=s.ServiceProvider.GetRequiredService<AppDbContext>();var client=new User{Id=ClientId,PhoneNumber="905550000001",Role=UserRole.Musteri,FirstName="Ayşe",OnboardingCompleted=true,CreatedAt=DateTime.UtcNow};var barber=new User{Id=BarberId,PhoneNumber="905550000002",Role=UserRole.Berber,FirstName="Gizli",LastName="Kişi",OnboardingCompleted=true,CreatedAt=DateTime.UtcNow};var p=new BarberProfile{Id=ProfileId,UserId=BarberId,User=barber,BusinessName="Test İşletme",Category="Kuaför",Description="Açıklama",ServiceMode="Both",City="İstanbul",District="Kadıköy",Neighborhood="Moda",AddressLine="Test",TcKimlikNo="11111111111",Status=BarberStatus.Approved,IsOnline=true,LogoFileName="logo.png",ServiceRadiusKm=10,Location=new Point(29,41){SRID=4326},WorkingHours="[{\"day\":4,\"open\":\"09:00\",\"close\":\"18:00\",\"closed\":false}]",CreatedAt=DateTime.UtcNow};db.AddRange(client,barber,p);db.BarberServices.AddRange(new BarberService{Id=Guid.NewGuid(),BarberProfileId=ProfileId,Name="Saç",Price=125,IsActive=true},new BarberService{Id=Guid.NewGuid(),BarberProfileId=ProfileId,Name="Pasif",Price=1,IsActive=false});db.BusinessPhotos.Add(new BusinessPhoto{Id=Guid.NewGuid(),BarberProfileId=ProfileId,StoredFileName="cover.jpg",OriginalFileName="cover.jpg",ContentType="image/jpeg",IsCover=true,CreatedAt=DateTime.UtcNow});SeedRatings(db,client,p);db.SaveChanges();seeded=true;}
    private static void SeedRatings(AppDbContext db,User client,BarberProfile p){for(var i=0;i<3;i++){var req=new ServiceRequest{Id=Guid.NewGuid(),ClientUserId=client.Id,ClientUser=client,BarberProfileId=p.Id,BarberProfile=p,Status=RequestStatus.Completed,RequestedTime=DateTimeOffset.UtcNow,ClientLocation=new Point(29,41){SRID=4326},CreatedAt=DateTime.UtcNow};db.ServiceRequests.Add(req);db.Ratings.Add(new Rating{Id=Guid.NewGuid(),ServiceRequest=req,ServiceRequestId=req.Id,RaterUser=client,RaterUserId=client.Id,RatedUser=p.User,RatedUserId=p.UserId,Score=3+i,Comment="Yorum "+i,CreatedAt=DateTime.UtcNow.AddMinutes(-i)});}}
    public async Task SetVisible(bool online,AccountStatus status=AccountStatus.Active){EnsureSeed();await using var s=Services.CreateAsyncScope();var db=s.ServiceProvider.GetRequiredService<AppDbContext>();(await db.BarberProfiles.FindAsync(ProfileId))!.IsOnline=online;(await db.Users.FindAsync(BarberId))!.AccountStatus=status;await db.SaveChangesAsync();}
    public async Task RestoreRatings(){await using var s=Services.CreateAsyncScope();var db=s.ServiceProvider.GetRequiredService<AppDbContext>();var client=await db.Users.FindAsync(ClientId);var p=await db.BarberProfiles.Include(x=>x.User).FirstAsync(x=>x.Id==ProfileId);SeedRatings(db,client!,p);await db.SaveChangesAsync();}
}

public sealed class DetailAuthHandler(IOptionsMonitor<AuthenticationSchemeOptions> options,ILoggerFactory logger,UrlEncoder encoder):AuthenticationHandler<AuthenticationSchemeOptions>(options,logger,encoder)
{
    protected override Task<AuthenticateResult> HandleAuthenticateAsync(){if(!Request.Headers.TryGetValue("X-Test-UserId",out var id))return Task.FromResult(AuthenticateResult.NoResult());var claims=new List<Claim>{new(ClaimTypes.NameIdentifier,id.ToString()),new(ClaimTypes.Role,Request.Headers["X-Test-Role"].ToString())};if(Request.Headers.TryGetValue("X-Test-BarberProfileId",out var pid))claims.Add(new("barberProfileId",pid.ToString()));return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(new ClaimsIdentity(claims,Scheme.Name)),Scheme.Name)));}
}
