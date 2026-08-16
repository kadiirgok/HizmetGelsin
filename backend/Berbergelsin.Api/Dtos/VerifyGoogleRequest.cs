namespace Berbergelsin.Api.Dtos;

public record VerifyGoogleRequest(string? FirebaseIdToken, string? IdToken, string? Role)
{
    public string ActualToken => (string.IsNullOrWhiteSpace(FirebaseIdToken) ? IdToken : FirebaseIdToken) ?? "";
}

public record SendGooglePhoneOtpRequest(string? FirebaseIdToken, string? IdToken, string Phone)
{
    public string ActualToken => (string.IsNullOrWhiteSpace(FirebaseIdToken) ? IdToken : FirebaseIdToken) ?? "";
}

public record VerifyGooglePhoneOtpRequest(string? FirebaseIdToken, string? IdToken, string Phone, string? Code, string? Role)
{
    public string ActualToken => (string.IsNullOrWhiteSpace(FirebaseIdToken) ? IdToken : FirebaseIdToken) ?? "";
}

public record PhoneLoginRequest(string? FirebaseIdToken, string? IdToken, string? Role)
{
    public string ActualToken => (string.IsNullOrWhiteSpace(FirebaseIdToken) ? IdToken : FirebaseIdToken) ?? "";
}
