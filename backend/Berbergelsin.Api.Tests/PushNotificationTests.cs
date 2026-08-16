using Berbergelsin.Api.Services;
using FirebaseAdmin.Messaging;
using Xunit;

namespace Berbergelsin.Api.Tests;

public sealed class PushNotificationTests
{
    [Fact]
    public async Task NoOp_provider_never_sends_or_throws()
    {
        await new NoOpPushNotificationSender().SendAsync(Message());
    }

    [Fact]
    public void Payload_contains_only_safe_contract_fields()
    {
        var data = PushPayloadPolicy.Data(Message());
        Assert.Equal(new[] { "notificationId", "route", "type" }, data.Keys.Order().ToArray());
        Assert.DoesNotContain(data, x => x.Key.Contains("token", StringComparison.OrdinalIgnoreCase));
    }

    [Theory]
    [InlineData(MessagingErrorCode.Unregistered, "push_token_invalid", true)]
    [InlineData(MessagingErrorCode.InvalidArgument, "push_token_invalid", true)]
    [InlineData(MessagingErrorCode.SenderIdMismatch, "push_token_invalid", true)]
    [InlineData(MessagingErrorCode.ThirdPartyAuthError, "push_provider_auth_failed", true)]
    [InlineData(MessagingErrorCode.QuotaExceeded, "push_provider_rate_limited", false)]
    [InlineData(MessagingErrorCode.Unavailable, "push_provider_transient", false)]
    public void Provider_errors_are_safely_classified(MessagingErrorCode value, string code, bool permanent)
    {
        var result = FirebasePushNotificationSender.Classify(value);
        Assert.Equal(code, result.Code);
        Assert.Equal(permanent, result.Permanent);
    }

    [Fact]
    public void Arbitrary_route_is_rejected()
    {
        var invalid = Message() with { Route = "https://evil.example/path" };
        Assert.Throws<PushDeliveryException>(() => PushPayloadPolicy.Data(invalid));
    }

    private static PushNotificationMessage Message() => new(
        Guid.Parse("00000000-0000-0000-0000-000000000121"),
        Guid.Parse("00000000-0000-0000-0000-000000000001"),
        "RequestUpdated", "Yeni bildirim", "Uygulamada yeni bir gelişme var.", "request",
        Guid.Parse("00000000-0000-0000-0000-000000000002"),
        "/talepler/00000000-0000-0000-0000-000000000002");
}
