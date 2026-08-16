using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Berbergelsin.Api.Auth;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Dtos;
using Berbergelsin.Api.Entities;
using Berbergelsin.Api.Enums;
using Berbergelsin.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using NetTopologySuite.Geometries;

namespace Berbergelsin.Api.Controllers;

[ApiController]
[Route("api/offers")]
[Authorize]
public class OffersController : ControllerBase
{
    private static readonly GeometryFactory Geo = new(new PrecisionModel(), 4326);
    private static readonly ConcurrentDictionary<string, SemaphoreSlim> Locks = new();
    private static readonly JsonSerializerOptions WebJson = new(JsonSerializerDefaults.Web);
    private readonly AppDbContext _db;
    private readonly RealtimeNotifier _notifier;
    private readonly TimeSpan _lifetime;

    public OffersController(AppDbContext db, RealtimeNotifier notifier, IConfiguration configuration)
    {
        _db = db; _notifier = notifier;
        _lifetime = TimeSpan.FromMinutes(Math.Clamp(configuration.GetValue("Offer:LifetimeMinutes", 1440), 5, 10080));
    }

    [HttpPost]
    [Authorize(Roles = "Musteri")]
    [EnableRateLimiting("offer-write")]
    public async Task<IActionResult> Create(CreatePriceOfferDto request, CancellationToken ct)
    {
        var actor = await ActiveActor(UserRole.Musteri, ct); if (actor == null) return Error(403, "offer_forbidden");
        if (!ValidPrice(request.ProposedPrice)) return Error(400, "offer_price_invalid");
        if (request.Lat is < -90 or > 90 || request.Lng is < -180 or > 180 || request.RequestedTime <= DateTimeOffset.UtcNow)
            return Error(400, "offer_invalid");
        var hash = Hash(new { action="create", request.BarberProfileId, request.ProposedPrice,
            time=request.RequestedTime.ToUniversalTime(), request.Lat, request.Lng, note=request.Note?.Trim() });
        return await CreateLocked(actor.Id, hash, async () =>
        {
            var barber = await _db.BarberProfiles.Include(b=>b.User).FirstOrDefaultAsync(b=>b.Id==request.BarberProfileId
                && b.Status==BarberStatus.Approved && b.IsOnline && b.AcceptsOffers
                && b.User.AccountStatus==AccountStatus.Active && b.User.OnboardingCompleted,ct);
            if(barber==null) return (Error(409,"offer_request_unavailable") as IActionResult,null as PriceOffer,string.Empty);
            if(await _db.PriceOffers.AnyAsync(o=>o.ClientUserId==actor.Id && o.BarberProfileId==barber.Id
                && (o.Status==OfferStatus.Pending||o.Status==OfferStatus.Countered) && o.ExpiresAt>DateTime.UtcNow,ct))
                return (Error(409,"offer_invalid_transition") as IActionResult,null,string.Empty);
            var now=DateTime.UtcNow;
            var offer=new PriceOffer{Id=Guid.NewGuid(),ClientUserId=actor.Id,BarberProfileId=barber.Id,
                ProposedPrice=request.ProposedPrice,Status=OfferStatus.Pending,Note=request.Note?.Trim(),
                RequestedTime=request.RequestedTime.ToUniversalTime(),ClientLocation=Geo.CreatePoint(new Coordinate(request.Lng,request.Lat)),
                CreatedAt=now,ExpiresAt=now.Add(_lifetime)};
            _db.PriceOffers.Add(offer);
            var json=Json(new { offerId=offer.Id });
            return (Content(json,"application/json") as IActionResult,offer,json);
        }, "NewOffer", ct);
    }

    [HttpGet("mine")]
    public async Task<IActionResult> Mine(CancellationToken ct)
    {
        var actor=await ActiveActor(null,ct); if(actor==null)return Error(403,"offer_forbidden");
        var profileId=actor.Role==UserRole.Berber?await _db.BarberProfiles.Where(b=>b.UserId==actor.Id).Select(b=>(Guid?)b.Id).FirstOrDefaultAsync(ct):null;
        var query=_db.PriceOffers.Include(o=>o.BarberProfile).ThenInclude(b=>b.User).Include(o=>o.ClientUser).AsQueryable();
        query=actor.Role==UserRole.Berber?query.Where(o=>o.BarberProfileId==profileId):query.Where(o=>o.ClientUserId==actor.Id);
        var list=await query.OrderByDescending(o=>o.CreatedAt).ThenByDescending(o=>o.Id).Take(100).ToListAsync(ct);
        var expired=list.Where(Expire).ToList();
        foreach(var offer in expired) await EnqueueOfferUpdatedBoth(offer,ct);
        if(expired.Count>0) await _db.SaveChangesAsync(ct);
        return Ok(list.Select(ToDto));
    }

    [HttpPost("from-request")]
    [Authorize(Roles = "Berber")]
    [EnableRateLimiting("offer-write")]
    public async Task<IActionResult> CreateFromRequest(CreateBarberOfferDto request,CancellationToken ct)
    {
        var actor=await ActiveActor(UserRole.Berber,ct);if(actor==null)return Error(403,"offer_forbidden");
        if(!ValidPrice(request.Price))return Error(400,"offer_price_invalid");
        var hash=Hash(new{action="from-request",request.ServiceRequestId,request.Price,
            time=request.RequestedTime?.ToUniversalTime(),note=request.Note?.Trim()});
        return await CreateLocked(actor.Id,hash,async()=>
        {
            var profile=await _db.BarberProfiles.FirstOrDefaultAsync(b=>b.UserId==actor.Id&&b.Status==BarberStatus.Approved,ct);
            if(profile==null)return(Error(403,"offer_forbidden") as IActionResult,null as PriceOffer,string.Empty);
            var source=await _db.ServiceRequests.FirstOrDefaultAsync(r=>r.Id==request.ServiceRequestId,ct);
            if(source==null)return(Error(404,"offer_not_found") as IActionResult,null,string.Empty);
            if(source.BarberProfileId!=profile.Id)return(Error(403,"offer_forbidden") as IActionResult,null,string.Empty);
            if(source.Status is not(RequestStatus.Pending or RequestStatus.Accepted))return(Error(409,"offer_request_unavailable") as IActionResult,null,string.Empty);
            if(await _db.PriceOffers.AnyAsync(o=>o.SourceServiceRequestId==source.Id&&(o.Status==OfferStatus.Pending||o.Status==OfferStatus.Countered)&&o.ExpiresAt>DateTime.UtcNow,ct))
                return(Error(409,"offer_invalid_transition") as IActionResult,null,string.Empty);
            var time=(request.RequestedTime??source.RequestedTime).ToUniversalTime();if(time<=DateTimeOffset.UtcNow)return(Error(400,"offer_invalid") as IActionResult,null,string.Empty);
            var now=DateTime.UtcNow;var offer=new PriceOffer{Id=Guid.NewGuid(),ClientUserId=source.ClientUserId,
                BarberProfileId=source.BarberProfileId,SourceServiceRequestId=source.Id,ProposedPrice=source.TotalPrice,
                CounterPrice=request.Price,Status=OfferStatus.Countered,Note=request.Note?.Trim(),RequestedTime=time,
                ClientLocation=source.ClientLocation,CreatedAt=now,RespondedAt=now,ExpiresAt=now.Add(_lifetime)};
            if(offer.ClientLocation==null)return(Error(400,"offer_location_missing") as IActionResult,null,string.Empty);
            _db.PriceOffers.Add(offer);var json=Json(new{offerId=offer.Id});return(Content(json,"application/json") as IActionResult,offer,json);
        },"NewOffer",ct);
    }

    [HttpPost("{id:guid}/accept")][Authorize(Roles="Berber")]
    public Task<IActionResult> Accept(Guid id,CancellationToken ct)=>Mutate(id,UserRole.Berber,"accept",null,OfferStatus.Pending,OfferStatus.Accepted,true,ct);
    [HttpPost("{id:guid}/reject")][Authorize(Roles="Berber")]
    public Task<IActionResult> Reject(Guid id,CancellationToken ct)=>Mutate(id,UserRole.Berber,"reject",null,OfferStatus.Pending,OfferStatus.Rejected,false,ct);
    [HttpPost("{id:guid}/counter")][Authorize(Roles="Berber")][EnableRateLimiting("offer-write")]
    public Task<IActionResult> Counter(Guid id,CounterOfferDto request,CancellationToken ct)=>
        !ValidPrice(request.CounterPrice)?Task.FromResult<IActionResult>(Error(400,"offer_price_invalid")):
        Mutate(id,UserRole.Berber,"counter",request.CounterPrice,OfferStatus.Pending,OfferStatus.Countered,false,ct);
    [HttpPost("{id:guid}/accept-counter")][Authorize(Roles="Musteri")]
    public Task<IActionResult> AcceptCounter(Guid id,CancellationToken ct)=>Mutate(id,UserRole.Musteri,"accept-counter",null,OfferStatus.Countered,OfferStatus.CounterAccepted,true,ct);
    [HttpPost("{id:guid}/reject-counter")][Authorize(Roles="Musteri")]
    public Task<IActionResult> RejectCounter(Guid id,CancellationToken ct)=>Mutate(id,UserRole.Musteri,"reject-counter",null,OfferStatus.Countered,OfferStatus.CounterRejected,false,ct);

    private async Task<IActionResult> Mutate(Guid id,UserRole role,string action,decimal? price,OfferStatus from,OfferStatus to,bool createsRequest,CancellationToken ct)
    {
        var actor=await ActiveActor(role,ct);if(actor==null)return Error(403,"offer_forbidden");
        var key=Key();if(key==null)return Error(400,"offer_invalid");var hash=Hash(new{action,id,price});
        var gate=Locks.GetOrAdd($"offer:{id}",_=>new SemaphoreSlim(1,1));await gate.WaitAsync(ct);
        try
        {
            var replay=await Replay(actor.Id,key,hash,ct);if(replay!=null)return replay;
            await using var tx=_db.Database.IsRelational()?await _db.Database.BeginTransactionAsync(System.Data.IsolationLevel.Serializable,ct):null;
            if(_db.Database.ProviderName?.Contains("Npgsql",StringComparison.OrdinalIgnoreCase)==true)
                await _db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtext({id.ToString()}))",ct);
            replay=await Replay(actor.Id,key,hash,ct);if(replay!=null)return replay;
            var offer=await _db.PriceOffers.Include(o=>o.BarberProfile).FirstOrDefaultAsync(o=>o.Id==id,ct);
            if(offer==null)return Error(404,"offer_not_found");
            if(role==UserRole.Berber&&offer.BarberProfile.UserId!=actor.Id||role==UserRole.Musteri&&offer.ClientUserId!=actor.Id)return Error(403,"offer_forbidden");
            if(Expire(offer)){await EnqueueOfferUpdatedBoth(offer,ct);await _db.SaveChangesAsync(ct);if(tx!=null)await tx.CommitAsync(ct);return Error(409,"offer_expired");}
            if(offer.Status!=from)return Error(409,"offer_invalid_transition");
            offer.Status=to;offer.RespondedAt=DateTime.UtcNow;offer.Version=Guid.NewGuid();if(price!=null)offer.CounterPrice=price;
            ServiceRequest? created=null;
            if(createsRequest)
            {
                if(await _db.ServiceRequests.AnyAsync(r=>r.OriginPriceOfferId==offer.Id,ct))return Error(409,"offer_invalid_transition");
                var final=to==OfferStatus.CounterAccepted?offer.CounterPrice!.Value:offer.ProposedPrice;offer.AcceptedPrice=final;
                if(offer.SourceServiceRequestId is Guid sourceId)
                {
                    created=await _db.ServiceRequests.FirstOrDefaultAsync(r=>r.Id==sourceId,ct);
                    if(created==null||created.Status is not(RequestStatus.Pending or RequestStatus.Accepted))
                        return Error(409,"offer_request_unavailable");
                    created.Status=RequestStatus.Accepted;created.RequestedTime=offer.RequestedTime;
                    created.ScheduledEndTime=offer.RequestedTime.AddHours(1);created.TotalPrice=final;
                    created.OriginPriceOfferId=offer.Id;created.RespondedAt=DateTime.UtcNow;created.UpdatedAt=DateTime.UtcNow;
                }
                else created=CreateRequestFromOffer(offer,final);
                var others=await _db.PriceOffers.Where(o=>o.Id!=offer.Id&&o.ClientUserId==offer.ClientUserId&&o.BarberProfileId==offer.BarberProfileId
                    &&(o.Status==OfferStatus.Pending||o.Status==OfferStatus.Countered)).ToListAsync(ct);
                foreach(var other in others){other.Status=OfferStatus.Rejected;other.RespondedAt=DateTime.UtcNow;other.Version=Guid.NewGuid();}
            }
            var json=Json(new{message="Teklif güncellendi.",status=to.ToString(),requestId=created?.Id});
            AddOperation(actor.Id,key,hash,json);
            await EnqueueOfferUpdatedBoth(offer,ct);
            if(created!=null)await _notifier.EnqueueAsync(offer.BarberProfile.UserId,"NewRequest",new{requestId=created.Id},ct);
            await _db.SaveChangesAsync(ct);if(tx!=null)await tx.CommitAsync(ct);
            return Content(json,"application/json");
        }
        catch(DbUpdateConcurrencyException){return Error(409,"offer_concurrency_conflict");}
        finally{gate.Release();}
    }

    private async Task<IActionResult> CreateLocked(Guid actorId,string hash,
        Func<Task<(IActionResult Result,PriceOffer? Offer,string Json)>> create,string eventName,CancellationToken ct)
    {
        var key=Key();if(key==null)return Error(400,"offer_invalid");var gate=Locks.GetOrAdd($"op:{actorId}:{key}",_=>new SemaphoreSlim(1,1));await gate.WaitAsync(ct);
        try
        {
            var replay=await Replay(actorId,key,hash,ct);if(replay!=null)return replay;
            await using var tx=_db.Database.IsRelational()?await _db.Database.BeginTransactionAsync(System.Data.IsolationLevel.Serializable,ct):null;
            var made=await create();if(made.Offer==null)return made.Result;
            var targetUserId=made.Offer.BarberProfile?.UserId??await _db.BarberProfiles.Where(b=>b.Id==made.Offer.BarberProfileId).Select(b=>b.UserId).SingleAsync(ct);
            await _notifier.EnqueueAsync(targetUserId,eventName,new{offerId=made.Offer.Id},ct);
            await _db.SaveChangesAsync(ct);
            var resultJson=Json(await ToDtoAsync(made.Offer.Id,ct));
            AddOperation(actorId,key,hash,resultJson);await _db.SaveChangesAsync(ct);if(tx!=null)await tx.CommitAsync(ct);
            return Content(resultJson,"application/json");
        }
        catch(DbUpdateException){return Error(409,"offer_concurrency_conflict");}
        finally{gate.Release();}
    }

    private async Task<User?> ActiveActor(UserRole? role,CancellationToken ct){var id=User.GetUserId();return await _db.Users.AsNoTracking().FirstOrDefaultAsync(u=>u.Id==id&&u.AccountStatus==AccountStatus.Active&&(role==null||u.Role==role),ct);}
    private string? Key(){var key=Request.Headers["Idempotency-Key"].FirstOrDefault()?.Trim();return key is{Length:>=8 and<=100}&&key.All(c=>char.IsAsciiLetterOrDigit(c)||c is '-' or '_' or '.')?key:null;}
    private async Task<IActionResult?> Replay(Guid user,string key,string hash,CancellationToken ct){var op=await _db.OfferOperations.AsNoTracking().FirstOrDefaultAsync(o=>o.UserId==user&&o.IdempotencyKey==key,ct);return op==null?null:op.PayloadHash==hash?Content(op.ResultJson,"application/json"):Error(409,"offer_idempotency_conflict");}
    private void AddOperation(Guid user,string key,string hash,string json)=>_db.OfferOperations.Add(new OfferOperation{Id=Guid.NewGuid(),UserId=user,IdempotencyKey=key,PayloadHash=hash,ResultJson=json,CreatedAt=DateTime.UtcNow});
    private static string Hash(object value)=>Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(value,WebJson))));
    private static string Json(object value)=>JsonSerializer.Serialize(value,WebJson);
    private static bool ValidPrice(decimal price)=>price is>=1 and<=100000;
    private static bool Expire(PriceOffer o){if(o.Status is OfferStatus.Pending or OfferStatus.Countered&&o.ExpiresAt<=DateTime.UtcNow){o.Status=OfferStatus.Expired;o.RespondedAt??=DateTime.UtcNow;o.Version=Guid.NewGuid();return true;}return false;}
    private ObjectResult Error(int status,string code)=>StatusCode(status,new{code});
    private async Task EnqueueOfferUpdatedBoth(PriceOffer o,CancellationToken ct){var payload=new{offerId=o.Id,status=o.Status.ToString()};await _notifier.EnqueueAsync(o.ClientUserId,"OfferUpdated",payload,ct);await _notifier.EnqueueAsync(o.BarberProfile.UserId,"OfferUpdated",payload,ct);}

    private ServiceRequest CreateRequestFromOffer(PriceOffer offer,decimal finalPrice){var now=DateTime.UtcNow;var request=new ServiceRequest{Id=Guid.NewGuid(),ClientUserId=offer.ClientUserId,BarberProfileId=offer.BarberProfileId,Status=RequestStatus.Accepted,RequestedTime=offer.RequestedTime,ScheduledEndTime=offer.RequestedTime.AddHours(1),ClientLocation=offer.ClientLocation,AddressNote=offer.Note,TotalPrice=finalPrice,OriginPriceOfferId=offer.Id,CreatedAt=now,UpdatedAt=now,CreatedBy=offer.ClientUserId,RespondedAt=now};_db.ServiceRequests.Add(request);return request;}
    private async Task<PriceOfferDto> ToDtoAsync(Guid id,CancellationToken ct){var o=await _db.PriceOffers.Include(x=>x.BarberProfile).ThenInclude(b=>b.User).Include(x=>x.ClientUser).FirstAsync(x=>x.Id==id,ct);return ToDto(o);}
    private static PriceOfferDto ToDto(PriceOffer o)=>new(o.Id,o.BarberProfileId,o.BarberProfile.BusinessName??o.BarberProfile.User.FirstName,$"{o.ClientUser.FirstName} {o.ClientUser.LastName}".Trim(),o.ProposedPrice,o.CounterPrice,o.Status,o.RequestedTime,o.Note,o.CreatedAt,o.ExpiresAt,o.AcceptedPrice);
}
