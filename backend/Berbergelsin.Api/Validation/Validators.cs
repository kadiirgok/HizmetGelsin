using Berbergelsin.Api.Dtos;
using FluentValidation;

namespace Berbergelsin.Api.Validation;

public static class TcKimlikValidator
{
    /// <summary>Resmi T.C. Kimlik No checksum doğrulaması.</summary>
    public static bool IsValid(string? tc)
    {
        if (string.IsNullOrWhiteSpace(tc) || tc.Length != 11 || !tc.All(char.IsDigit) || tc[0] == '0')
            return false;

        var d = tc.Select(c => c - '0').ToArray();
        var oddSum = d[0] + d[2] + d[4] + d[6] + d[8];
        var evenSum = d[1] + d[3] + d[5] + d[7];
        var d10 = ((oddSum * 7) - evenSum) % 10;
        if (d10 < 0) d10 += 10;
        var d11 = (d.Take(10).Sum()) % 10;
        return d[9] == d10 && d[10] == d11;
    }
}

public static class PhoneNormalizer
{
    /// <summary>Girilen numarayı "905XXXXXXXXX" formatına çevirir; geçersizse null.</summary>
    public static string? Normalize(string? input)
    {
        if (string.IsNullOrWhiteSpace(input)) return null;
        var digits = new string(input.Where(char.IsDigit).ToArray());
        if (digits.StartsWith("90")) digits = digits[2..];
        digits = digits.TrimStart('0');
        if (digits.Length != 10 || !digits.StartsWith('5')) return null;
        return "90" + digits;
    }
}

public class ClientOnboardingValidator : AbstractValidator<ClientOnboardingRequest>
{
    public ClientOnboardingValidator()
    {
        RuleFor(x => x.FirstName).NotEmpty().WithMessage("Ad zorunludur.").MaximumLength(100);
        RuleFor(x => x.LastName).NotEmpty().WithMessage("Soyad zorunludur.").MaximumLength(100);
        RuleFor(x => x.Email).NotEmpty().WithMessage("E-posta zorunludur.").EmailAddress().WithMessage("Geçerli bir e-posta girin.").MaximumLength(200);
        RuleFor(x => x.KvkkAccepted).Equal(true).WithMessage("KVKK metnini kabul etmelisiniz.");
    }
}

public class BarberProfileStepValidator : AbstractValidator<BarberProfileStepRequest>
{
    public BarberProfileStepValidator()
    {
        RuleFor(x => x.FirstName).NotEmpty().WithMessage("Ad zorunludur.").MaximumLength(100);
        RuleFor(x => x.LastName).NotEmpty().WithMessage("Soyad zorunludur.").MaximumLength(100);
        RuleFor(x => x.Email).NotEmpty().WithMessage("E-posta zorunludur.").EmailAddress().WithMessage("Geçerli bir e-posta girin.").MaximumLength(200);
        RuleFor(x => x.TcKimlikNo).Must(TcKimlikValidator.IsValid).WithMessage("Geçerli bir T.C. Kimlik No girin.");
        RuleFor(x => x.BusinessName).MaximumLength(200);
        RuleFor(x => x.Category).MaximumLength(80).WithMessage("Kategori en fazla 80 karakter olabilir.");
        RuleFor(x => x.KvkkAccepted).Equal(true).WithMessage("KVKK metnini kabul etmelisiniz.");
    }
}

public class BarberServicesStepValidator : AbstractValidator<BarberServicesStepRequest>
{
    public BarberServicesStepValidator()
    {
        RuleFor(x => x.Services).NotEmpty().WithMessage("En az bir hizmet eklemelisiniz.");
        RuleForEach(x => x.Services).ChildRules(s =>
        {
            s.RuleFor(i => i.Name).NotEmpty().WithMessage("Hizmet adı zorunludur.").MaximumLength(150);
            s.RuleFor(i => i.Price).InclusiveBetween(1, 100000).WithMessage("Fiyat 1-100000 TL aralığında olmalıdır.");
        });
    }
}

public class BarberCompleteStepValidator : AbstractValidator<BarberCompleteStepRequest>
{
    public BarberCompleteStepValidator()
    {
        RuleFor(x => x.ServiceRadiusKm).InclusiveBetween(1, 30).WithMessage("Hizmet yarıçapı 1-30 km aralığında olmalıdır.");
    }
}
