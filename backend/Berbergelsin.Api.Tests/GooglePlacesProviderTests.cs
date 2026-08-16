using System.Net;
using System.Text;
using System.Text.Json;
using Berbergelsin.Api.Dtos;
using Berbergelsin.Api.Services;
using Microsoft.Extensions.Configuration;
using Xunit;

namespace Berbergelsin.Api.Tests;

public sealed class GooglePlacesProviderTests
{
    const string Token = "11111111-1111-4111-8111-111111111111";
    static string Fixture(string name) => File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "GooglePlaces", name));
    static GooglePlacesAddressSearchProvider Provider(RecordingHandler handler, bool key = true, TimeSpan? timeout = null)
    {
        var values = key ? new Dictionary<string,string?> { ["GOOGLE_MAPS_SERVER_API_KEY"]="synthetic-test-key" } : [];
        var config = new ConfigurationBuilder().AddInMemoryCollection(values).Build();
        return new GooglePlacesAddressSearchProvider(new HttpClient(handler) { BaseAddress=new Uri("https://places.googleapis.com/"), Timeout=timeout??TimeSpan.FromSeconds(5) }, config);
    }
    static AddressAutocompleteRequest Request() => new() { Q="  Ornek  ", SessionToken=Token, Province="Test Ili", District="Test Ilcesi", Latitude=40.1, Longitude=29.2 };

    [Fact] public async Task Autocomplete_sends_Turkey_Turkish_token_trim_context_bias_and_headers()
    {
        var h=new RecordingHandler(Response(HttpStatusCode.OK,"autocomplete-success.json")); var result=await Provider(h).AutocompleteAsync(Request(),default);
        Assert.Single(result); var body=JsonDocument.Parse(h.Bodies.Single()).RootElement;
        Assert.Equal("tr",body.GetProperty("languageCode").GetString()); Assert.Equal("TR",body.GetProperty("regionCode").GetString());
        Assert.Equal("tr",body.GetProperty("includedRegionCodes")[0].GetString()); Assert.Equal(Token,body.GetProperty("sessionToken").GetString());
        Assert.Equal("Ornek, Test Ilcesi, Test Ili",body.GetProperty("input").GetString());
        Assert.Equal(40.1,body.GetProperty("locationBias").GetProperty("circle").GetProperty("center").GetProperty("latitude").GetDouble());
        Assert.Contains("placePrediction.placeId",h.Headers.Single()["X-Goog-FieldMask"]);
        Assert.DoesNotContain("synthetic-test-key",h.Bodies.Single());
    }
    [Fact] public async Task Autocomplete_filters_explicit_foreign_prediction(){var h=new RecordingHandler(Response(HttpStatusCode.OK,"autocomplete-turkey-and-foreign.json"));var r=await Provider(h).AutocompleteAsync(Request(),default);Assert.Single(r);Assert.Equal("synthetic-tr",r[0].PlaceId);}
    [Fact] public async Task Autocomplete_empty_is_safe(){var h=new RecordingHandler(Response(HttpStatusCode.OK,"autocomplete-empty.json"));Assert.Empty(await Provider(h).AutocompleteAsync(Request(),default));}
    [Fact] public async Task Autocomplete_is_capped_at_ten(){var item=JsonDocument.Parse(Fixture("autocomplete-success.json")).RootElement.GetProperty("suggestions")[0].GetRawText();var h=new RecordingHandler(new HttpResponseMessage(HttpStatusCode.OK){Content=new StringContent("{\"suggestions\":["+string.Join(",",Enumerable.Repeat(item,12))+"]}")});Assert.Equal(10,(await Provider(h).AutocompleteAsync(Request(),default)).Count);}
    [Fact] public async Task Missing_key_is_controlled(){var e=await Assert.ThrowsAsync<AddressProviderException>(()=>Provider(new RecordingHandler(),false).AutocompleteAsync(Request(),default));Assert.Equal(AddressProviderFailure.Unavailable,e.Failure);}
    [Fact] public async Task Invalid_json_is_provider_error(){var h=new RecordingHandler(new HttpResponseMessage(HttpStatusCode.OK){Content=new StringContent("{bad")});var e=await Assert.ThrowsAsync<AddressProviderException>(()=>Provider(h).AutocompleteAsync(Request(),default));Assert.Equal(AddressProviderFailure.ProviderError,e.Failure);}
    [Fact] public async Task Details_maps_all_components_and_minimum_mask()
    {
        var h=new RecordingHandler(Response(HttpStatusCode.OK,"place-details-full.json"));var x=await Provider(h).ResolvePlaceAsync("id with/slash",Token,default);
        Assert.NotNull(x);Assert.Equal("Test Ili",x.Province);Assert.Equal("Test Ilcesi",x.District);Assert.Equal("Ornek Mahallesi",x.Neighborhood);Assert.Equal("Ornek Caddesi",x.Street);Assert.Equal("42",x.StreetNumber);Assert.Equal("34000",x.PostalCode);Assert.Equal(40.1,x.Latitude);Assert.Equal(29.2,x.Longitude);Assert.Equal("TR",x.CountryCode);
        Assert.Contains("id%20with%2Fslash",h.Uris.Single().AbsoluteUri);Assert.Contains("sessionToken="+Token,h.Uris.Single().Query);Assert.Equal("id,formattedAddress,addressComponents,location",h.Headers.Single()["X-Goog-FieldMask"]);
    }
    [Theory][InlineData("place-details-missing-neighborhood.json")][InlineData("place-details-missing-street.json")]
    public async Task Missing_components_remain_null(string fixture){var h=new RecordingHandler(Response(HttpStatusCode.OK,fixture));var x=await Provider(h).ResolvePlaceAsync("x",Token,default);Assert.NotNull(x);Assert.True(x.Neighborhood is null||x.Street is null);}
    [Fact] public async Task Foreign_details_are_rejected(){var h=new RecordingHandler(Response(HttpStatusCode.OK,"place-details-invalid-country.json"));Assert.Null(await Provider(h).ResolvePlaceAsync("x",Token,default));}
    [Fact] public async Task Not_found_is_null_and_not_retried(){var h=new RecordingHandler(new HttpResponseMessage(HttpStatusCode.NotFound));Assert.Null(await Provider(h).ResolvePlaceAsync("x",Token,default));Assert.Single(h.Uris);}
    [Theory][InlineData(429)][InlineData(500)]
    public async Task Transient_status_retries_once_then_succeeds(int status){var h=new RecordingHandler(new HttpResponseMessage((HttpStatusCode)status),Response(HttpStatusCode.OK,"autocomplete-success.json"));Assert.Single(await Provider(h).AutocompleteAsync(Request(),default));Assert.Equal(2,h.Uris.Count);}
    [Fact] public async Task Repeated_429_is_rate_limited_after_two_calls(){var h=new RecordingHandler(new HttpResponseMessage((HttpStatusCode)429),new HttpResponseMessage((HttpStatusCode)429));var e=await Assert.ThrowsAsync<AddressProviderException>(()=>Provider(h).AutocompleteAsync(Request(),default));Assert.Equal(AddressProviderFailure.RateLimited,e.Failure);Assert.Equal(2,h.Uris.Count);}
    [Fact] public async Task Repeated_500_is_provider_error_after_two_calls(){var h=new RecordingHandler(new HttpResponseMessage(HttpStatusCode.InternalServerError),new HttpResponseMessage(HttpStatusCode.InternalServerError));var e=await Assert.ThrowsAsync<AddressProviderException>(()=>Provider(h).AutocompleteAsync(Request(),default));Assert.Equal(AddressProviderFailure.ProviderError,e.Failure);Assert.Equal(2,h.Uris.Count);}
    [Fact] public async Task Bad_request_is_not_retried(){var h=new RecordingHandler(new HttpResponseMessage(HttpStatusCode.BadRequest));await Assert.ThrowsAsync<AddressProviderException>(()=>Provider(h).AutocompleteAsync(Request(),default));Assert.Single(h.Uris);}
    [Fact] public async Task Caller_cancellation_propagates_without_retry(){var h=new RecordingHandler(async ct=>{await Task.Delay(Timeout.Infinite,ct);return new HttpResponseMessage(HttpStatusCode.OK);});using var c=new CancellationTokenSource(30);await Assert.ThrowsAnyAsync<OperationCanceledException>(()=>Provider(h).AutocompleteAsync(Request(),c.Token));Assert.Single(h.Uris);}
    [Fact] public async Task Http_timeout_becomes_unavailable(){var h=new RecordingHandler(async ct=>{await Task.Delay(Timeout.Infinite,ct);return new HttpResponseMessage(HttpStatusCode.OK);});var e=await Assert.ThrowsAsync<AddressProviderException>(()=>Provider(h,timeout:TimeSpan.FromMilliseconds(30)).AutocompleteAsync(Request(),default));Assert.Equal(AddressProviderFailure.Unavailable,e.Failure);}
    static HttpResponseMessage Response(HttpStatusCode code,string fixture)=>new(code){Content=new StringContent(Fixture(fixture),Encoding.UTF8,"application/json")};
}

public sealed class RecordingHandler : HttpMessageHandler
{
    readonly Queue<object> responses=new();
    public List<Uri> Uris {get;}=[]; public List<string> Bodies {get;}=[]; public List<Dictionary<string,string>> Headers {get;}=[];
    public RecordingHandler(params HttpResponseMessage[] items){foreach(var x in items)responses.Enqueue(x);}
    public RecordingHandler(Func<CancellationToken,Task<HttpResponseMessage>> action){responses.Enqueue(action);}
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken ct)
    {
        Uris.Add(request.RequestUri!);Bodies.Add(request.Content==null?"":await request.Content.ReadAsStringAsync(ct));
        Headers.Add(request.Headers.ToDictionary(x=>x.Key,x=>string.Join(",",x.Value),StringComparer.OrdinalIgnoreCase));
        if(responses.Count==0)throw new InvalidOperationException("No fake response");
        var next=responses.Count>1?responses.Dequeue():responses.Peek();
        return next is Func<CancellationToken,Task<HttpResponseMessage>> f?await f(ct):(HttpResponseMessage)next;
    }
}