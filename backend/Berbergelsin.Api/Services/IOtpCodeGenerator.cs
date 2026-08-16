using System.Security.Cryptography;

namespace Berbergelsin.Api.Services;

public interface IOtpCodeGenerator
{
    string GenerateCode();
}

public class CryptoOtpCodeGenerator : IOtpCodeGenerator
{
    public string GenerateCode()
    {
        return RandomNumberGenerator.GetInt32(100000, 1000000).ToString();
    }
}
