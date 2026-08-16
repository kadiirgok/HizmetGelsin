using Twilio;
using Twilio.Rest.Verify.V2.Service;

namespace Berbergelsin.Api.Services;

/// <summary>
/// Twilio Verify API ile telefon doğrulama servisi.
/// OTP kodunu Twilio üretir ve doğrular — bizim veritabanında saklanmaz.
/// </summary>
public class TwilioVerifyService
{
    private readonly string _accountSid;
    private readonly string _authToken;
    private readonly string _serviceSid;
    private readonly ILogger<TwilioVerifyService> _logger;

    public TwilioVerifyService(IConfiguration config, ILogger<TwilioVerifyService> logger)
    {
        _accountSid = config["Twilio:AccountSid"] ?? throw new InvalidOperationException("Twilio:AccountSid tanımlı değil");
        _authToken = config["Twilio:AuthToken"] ?? throw new InvalidOperationException("Twilio:AuthToken tanımlı değil");
        _serviceSid = config["Twilio:ServiceSid"] ?? throw new InvalidOperationException("Twilio:ServiceSid tanımlı değil");
        _logger = logger;

        TwilioClient.Init(_accountSid, _authToken);
    }

    public enum SendResult
    {
        Sent,
        TooSoon,
        SmsFailed
    }

    public enum VerifyResult
    {
        Success,
        Invalid,
        Expired,
        TooManyAttempts
    }

    /// <summary>
    /// Telefon numarasına doğrulama kodu gönderir.
    /// </summary>
    /// <param name="phone">90XXXXXXXXXX formatında (başında + olmadan)</param>
    public async Task<SendResult> SendVerificationAsync(string phone)
    {
        try
        {
            var options = new CreateVerificationOptions(
                pathServiceSid: _serviceSid,
                to: $"+{phone}",
                channel: "sms"
            );

            var verification = await VerificationResource.CreateAsync(options);

            _logger.LogInformation("Twilio Verify gönderildi: {Phone} → Status: {Status}", phone, verification.Status);

            return verification.Status switch
            {
                "pending" => SendResult.Sent,
                "approved" => SendResult.Sent,
                "max_attempts_reached" => SendResult.TooSoon,
                _ => SendResult.Sent
            };
        }
        catch (Twilio.Exceptions.ApiException ex) when (ex.Code == 60200)
        {
            // 60200: Too many requests — rate limit
            _logger.LogWarning("Twilio rate limit: {Phone}", phone);
            return SendResult.TooSoon;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Twilio Verify gönderim hatası: {Phone}", phone);
            return SendResult.SmsFailed;
        }
    }

    /// <summary>
    /// Kullanıcının girdiği kodu doğrular.
    /// </summary>
    /// <param name="phone">90XXXXXXXXXX formatında (başında + olmadan)</param>
    /// <param name="code">Doğrulama kodu</param>
    public async Task<VerifyResult> CheckVerificationAsync(string phone, string code)
    {
        try
        {
            var options = new CreateVerificationCheckOptions(_serviceSid)
            {
                To = $"+{phone}",
                Code = code
            };

            var check = await VerificationCheckResource.CreateAsync(options);

            _logger.LogInformation("Twilio Verify kontrol: {Phone} → Status: {Status}", phone, check.Status);

            if (check.Status == "approved")
            {
                return VerifyResult.Success;
            }

            // "pending" → kod yanlış
            if (check.Status == "pending")
            {
                return VerifyResult.Invalid;
            }

            return VerifyResult.Invalid;
        }
        catch (Twilio.Exceptions.ApiException ex) when (ex.Code == 60202)
        {
            // 60202: Max attempts reached
            _logger.LogWarning("Twilio max attempts: {Phone}", phone);
            return VerifyResult.TooManyAttempts;
        }
        catch (Twilio.Exceptions.ApiException ex) when (ex.Code == 20404)
        {
            // 20404: Verification not found (expired or never sent)
            _logger.LogWarning("Twilio verification expired/missing: {Phone}", phone);
            return VerifyResult.Expired;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Twilio Verify kontrol hatası: {Phone}", phone);
            return VerifyResult.Invalid;
        }
    }
}
