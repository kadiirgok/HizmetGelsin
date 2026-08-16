using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Berbergelsin.Api.Data;
using Berbergelsin.Api.Entities;
using Berbergelsin.Api.Enums;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Berbergelsin.Api.Tests;

public sealed class PublicRatingContractTests
{
    [Fact]
    public async Task Public_review_contains_real_rating_id_without_sensitive_ids()
    {
        using var factory = new RequestApiFactory();
        factory.Seed();
        var rating = SeedRating(factory, RatingModerationStatus.Visible);

        var response = await factory.Client(factory.OtherClientId, "Musteri")
            .GetAsync($"/api/barbers/{factory.ProfileId}/reviews?page=1&pageSize=20");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var item = json.RootElement.GetProperty("items")[0];
        Assert.Equal(rating.Id, item.GetProperty("id").GetGuid());
        Assert.False(item.GetProperty("isOwn").GetBoolean());
        foreach (var forbidden in new[] { "userId", "requestId", "phone", "email" })
            Assert.False(item.TryGetProperty(forbidden, out _));
    }

    [Fact]
    public async Task Hidden_and_deleted_reviews_are_not_public_or_reportable()
    {
        using var factory = new RequestApiFactory();
        factory.Seed();
        var hidden = SeedRating(factory, RatingModerationStatus.Hidden);
        var deleted = SeedRating(factory, RatingModerationStatus.Visible, deleted: true);
        var client = factory.Client(factory.OtherClientId, "Musteri");

        var page = await client.GetFromJsonAsync<JsonElement>($"/api/barbers/{factory.ProfileId}/reviews");
        Assert.Empty(page.GetProperty("items").EnumerateArray());
        Assert.Equal(HttpStatusCode.NotFound, (await client.PostAsJsonAsync($"/api/ratings/{hidden.Id}/report", new { reasonCode = "spam" })).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.PostAsJsonAsync($"/api/ratings/{deleted.Id}/report", new { reasonCode = "spam" })).StatusCode);
    }

    [Fact]
    public async Task Review_order_and_owner_marker_are_deterministic()
    {
        using var factory = new RequestApiFactory();
        factory.Seed();
        var older = SeedRating(factory, RatingModerationStatus.Visible, createdAt: DateTime.UtcNow.AddDays(-2));
        var newer = SeedRating(factory, RatingModerationStatus.Visible, createdAt: DateTime.UtcNow.AddDays(-1));
        var page = await factory.Client(factory.ClientId, "Musteri")
            .GetFromJsonAsync<JsonElement>($"/api/barbers/{factory.ProfileId}/reviews?page=1&pageSize=1");
        var item = page.GetProperty("items")[0];
        Assert.Equal(newer.Id, item.GetProperty("id").GetGuid());
        Assert.True(item.GetProperty("isOwn").GetBoolean());
        Assert.True(page.GetProperty("hasNextPage").GetBoolean());
        Assert.NotEqual(older.Id, newer.Id);
    }

    static Rating SeedRating(RequestApiFactory factory, RatingModerationStatus status, bool deleted = false, DateTime? createdAt = null)
    {
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var request = new ServiceRequest
        {
            Id = Guid.NewGuid(), ClientUserId = factory.ClientId, BarberProfileId = factory.ProfileId,
            Status = RequestStatus.Completed, RequestedTime = DateTimeOffset.UtcNow.AddDays(-3),
            ScheduledEndTime = DateTimeOffset.UtcNow.AddDays(-3).AddHours(1), CreatedAt = DateTime.UtcNow.AddDays(-3),
            UpdatedAt = DateTime.UtcNow, CreatedBy = factory.ClientId
        };
        var rating = new Rating
        {
            Id = Guid.NewGuid(), ServiceRequestId = request.Id, RaterUserId = factory.ClientId,
            RatedUserId = factory.BarberUserId, Score = 5, Comment = "Güvenli yorum",
            CreatedAt = createdAt ?? DateTime.UtcNow, ModerationStatus = status, IsDeleted = deleted,
            DeletedAt = deleted ? DateTime.UtcNow : null, Version = Guid.NewGuid()
        };
        db.ServiceRequests.Add(request);
        db.Ratings.Add(rating);
        db.SaveChanges();
        return rating;
    }
}
