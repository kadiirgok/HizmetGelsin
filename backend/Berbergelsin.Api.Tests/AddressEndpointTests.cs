using System.Net;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json;
using Berbergelsin.Api.Dtos;
using Berbergelsin.Api.Services;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Xunit;

namespace Berbergelsin.Api.Tests;

public sealed class AddressEndpointTests
{
    const string Token="11111111-1111-4111-8111-111111111111";
    static HttpClient Client(AddressApiFactory f,string user="user-a"){var c=f.CreateClient();c.DefaultRequestHeaders.Authorization=new AuthenticationHeaderValue("Test");c.DefaultRequestHeaders.Add("X-Test-User",user);return c;}
    [Fact] public async Task Anonymous_is_401(){using var f=new AddressApiFactory();using var c=f.CreateClient();Assert.Equal(HttpStatusCode.Unauthorized,(await c.GetAsync($"/api/locations/address-suggestions?q=abc&sessionToken={Token}")).StatusCode);}
    [Theory][InlineData("")][InlineData("ab")]
    public async Task Missing_or_short_query_is_400(string q){using var f=new AddressApiFactory();using var c=Client(f);Assert.Equal(HttpStatusCode.BadRequest,(await c.GetAsync($"/api/locations/address-suggestions?q={q}&sessionToken={Token}")).StatusCode);}
    [Fact] public async Task Long_query_is_400(){using var f=new AddressApiFactory();using var c=Client(f);Assert.Equal(HttpStatusCode.BadRequest,(await c.GetAsync($"/api/locations/address-suggestions?q={new string('x',121)}&sessionToken={Token}")).StatusCode);}
    [Theory][InlineData("")][InlineData("not-uuid")]
    public async Task Missing_or_invalid_suggestion_token_is_400(string token){using var f=new AddressApiFactory();using var c=Client(f);Assert.Equal(HttpStatusCode.BadRequest,(await c.GetAsync($"/api/locations/address-suggestions?q=abc&sessionToken={token}")).StatusCode);}
    [Fact] public async Task Suggestion_success_has_exact_contract(){using var f=new AddressApiFactory();f.Provider.Predictions=[new("p1","Primary","Secondary","Display")];using var c=Client(f);using var r=await c.GetAsync($"/api/locations/address-suggestions?q=abc&sessionToken={Token}");Assert.Equal(HttpStatusCode.OK,r.StatusCode);var e=JsonDocument.Parse(await r.Content.ReadAsStringAsync()).RootElement[0];Assert.Equal(new[]{"displayText","placeId","primaryText","secondaryText"},e.EnumerateObject().Select(x=>x.Name).Order().ToArray());}
    [Theory][InlineData(AddressProviderFailure.Unavailable,503,"address_search_unavailable")][InlineData(AddressProviderFailure.RateLimited,429,"address_search_rate_limited")][InlineData(AddressProviderFailure.ProviderError,502,"address_provider_error")]
    public async Task Provider_errors_are_safe(AddressProviderFailure failure,int status,string code){using var f=new AddressApiFactory();f.Provider.Failure=failure;using var c=Client(f);using var r=await c.GetAsync($"/api/locations/address-suggestions?q=private-address&sessionToken={Token}");Assert.Equal(status,(int)r.StatusCode);var body=await r.Content.ReadAsStringAsync();Assert.Contains(code,body);Assert.DoesNotContain("Google",body);Assert.DoesNotContain("private-address",body);Assert.DoesNotContain("stack",body,StringComparison.OrdinalIgnoreCase);}
    [Theory][InlineData("POST")][InlineData("PUT")][InlineData("DELETE")]
    public async Task Unsupported_suggestion_methods_are_405(string method){using var f=new AddressApiFactory();using var c=Client(f);Assert.Equal(HttpStatusCode.MethodNotAllowed,(await c.SendAsync(new HttpRequestMessage(new HttpMethod(method),$"/api/locations/address-suggestions?q=abc&sessionToken={Token}"))).StatusCode);}
    [Theory][InlineData("")][InlineData("bad")]
    public async Task Missing_or_invalid_details_token_is_400(string token){using var f=new AddressApiFactory();using var c=Client(f);Assert.Equal(HttpStatusCode.BadRequest,(await c.GetAsync($"/api/locations/places/p1?sessionToken={token}")).StatusCode);}
    [Fact] public async Task Details_success_has_exact_contract(){using var f=new AddressApiFactory();f.Provider.Resolved=new("p1","Synthetic","Province","District","Neighborhood","Street","1","00000",40,29,"TR");using var c=Client(f);using var r=await c.GetAsync($"/api/locations/places/p1?sessionToken={Token}");Assert.Equal(HttpStatusCode.OK,r.StatusCode);var e=JsonDocument.Parse(await r.Content.ReadAsStringAsync()).RootElement;Assert.Equal(new[]{"countryCode","district","formattedAddress","latitude","longitude","neighborhood","placeId","postalCode","province","street","streetNumber"},e.EnumerateObject().Select(x=>x.Name).Order().ToArray());}
    [Fact] public async Task Details_not_found_is_safe(){using var f=new AddressApiFactory();using var c=Client(f);using var r=await c.GetAsync($"/api/locations/places/missing?sessionToken={Token}");Assert.Equal(HttpStatusCode.NotFound,r.StatusCode);Assert.Contains("address_not_found",await r.Content.ReadAsStringAsync());}
    [Fact] public async Task Incomplete_details_are_422(){using var f=new AddressApiFactory();f.Provider.Resolved=new("p1",null,null,null,null,null,null,null,40,29,"TR");using var c=Client(f);using var r=await c.GetAsync($"/api/locations/places/p1?sessionToken={Token}");Assert.Equal((HttpStatusCode)422,r.StatusCode);Assert.Contains("address_incomplete",await r.Content.ReadAsStringAsync());}
    [Fact] public async Task Health_is_preserved(){using var f=new AddressApiFactory();using var c=f.CreateClient();Assert.Equal(HttpStatusCode.OK,(await c.GetAsync("/health")).StatusCode);}
}

public sealed class AddressRateLimitTests
{
    const string Url="/api/locations/address-suggestions?q=abc&sessionToken=11111111-1111-4111-8111-111111111111";
    static HttpClient Client(AddressApiFactory f,string user){var c=f.CreateClient();c.DefaultRequestHeaders.Authorization=new AuthenticationHeaderValue("Test");c.DefaultRequestHeaders.Add("X-Test-User",user);return c;}
    [Fact] public async Task Third_request_is_429_with_safe_contract_and_users_are_isolated()
    {
        using var f=new AddressApiFactory(2);using var a=Client(f,"rate-a");Assert.Equal(HttpStatusCode.OK,(await a.GetAsync(Url)).StatusCode);Assert.Equal(HttpStatusCode.OK,(await a.GetAsync(Url)).StatusCode);
        using var blocked=await a.GetAsync(Url);Assert.Equal(HttpStatusCode.TooManyRequests,blocked.StatusCode);Assert.Contains("address_search_rate_limited",await blocked.Content.ReadAsStringAsync());Assert.True(blocked.Headers.RetryAfter is not null);
        using var b=Client(f,"rate-b");Assert.Equal(HttpStatusCode.OK,(await b.GetAsync(Url)).StatusCode);
    }
}

public sealed class AddressApiFactory : WebApplicationFactory<Program>
{
    public FakeAddressSearchProvider Provider {get;}=new(); readonly int limit;
    public AddressApiFactory(int limit=100)=>this.limit=limit;
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.ConfigureAppConfiguration((_,c)=>c.AddInMemoryCollection(new Dictionary<string,string?>{{"Jwt:Key","integration-test-key-with-at-least-32-characters"},{"Jwt:Issuer","integration-tests"},{"Jwt:Audience","integration-tests"},{"ConnectionStrings:Default","Host=127.0.0.1;Port=1;Database=unused;Username=unused;Password=unused"},{"AddressSearch:PermitLimit",limit.ToString()},{"AddressSearch:WindowSeconds","60"}}));
        builder.ConfigureServices(s=>{s.RemoveAll<IAddressSearchProvider>();s.AddSingleton<IAddressSearchProvider>(Provider);s.AddAuthentication(o=>{o.DefaultAuthenticateScheme="Test";o.DefaultChallengeScheme="Test";}).AddScheme<AuthenticationSchemeOptions,TestAuthHandler>("Test",_=>{});});
    }
}
public sealed class FakeAddressSearchProvider:IAddressSearchProvider
{
    public IReadOnlyList<AddressPredictionDto> Predictions {get;set;}=[];public ResolvedAddressDto? Resolved {get;set;} public AddressProviderFailure? Failure {get;set;}
    public Task<IReadOnlyList<AddressPredictionDto>> AutocompleteAsync(AddressAutocompleteRequest r,CancellationToken c){if(Failure is{}f)throw new AddressProviderException(f);return Task.FromResult(Predictions);}
    public Task<ResolvedAddressDto?> ResolvePlaceAsync(string p,string s,CancellationToken c){if(Failure is{}f)throw new AddressProviderException(f);return Task.FromResult(Resolved);}
}
public sealed class TestAuthHandler(IOptionsMonitor<AuthenticationSchemeOptions> o,ILoggerFactory l,UrlEncoder e):AuthenticationHandler<AuthenticationSchemeOptions>(o,l,e)
{
    protected override Task<AuthenticateResult> HandleAuthenticateAsync(){if(Request.Headers.Authorization.Count==0)return Task.FromResult(AuthenticateResult.NoResult());var id=Request.Headers["X-Test-User"].FirstOrDefault()??"test-user";var p=new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier,id)],Scheme.Name));return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(p,Scheme.Name)));}
}