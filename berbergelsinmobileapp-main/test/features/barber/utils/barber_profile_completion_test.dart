import 'package:berbergelsin/features/barber/domain/barber_profile_completion_input.dart';
import 'package:berbergelsin/features/barber/utils/barber_profile_completion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BarberProfileCompletionInput ve BarberProfileCompletion Testleri', () {
    test('tamamen bos profil icin 0 doner ve tum uyarilari listeler', () {
      const input = BarberProfileCompletionInput(
        businessName: null,
        category: null,
        description: null,
        city: null,
        district: null,
        neighborhood: null,
        addressLine: null,
        latitude: null,
        longitude: null,
        hasLogo: false,
        hasGalleryOrCoverPhoto: false,
        hasActiveService: false,
        hasValidWorkingHours: false,
      );

      final result = BarberProfileCompletion.calculateDetailed(input);

      expect(result.percentage, 0);
      expect(
        result.missingItems,
        containsAll([
          'İşletme adı ekle',
          'İşletme açıklaması ekle',
          'Kategori seç',
          'Konum bilgilerini tamamla',
          'Logo ekle',
          'Kapak veya vitrin fotoğrafı ekle',
          'En az bir hizmet ekle',
          'Çalışma saatlerini belirle',
        ]),
      );
    });

    test(
      'ayni normalized input her zaman ayni yüzdeyi doner (deterministic)',
      () {
        const input = BarberProfileCompletionInput(
          businessName: 'Ahmet Usta',
          category: 'Berber',
          description: 'Detaylı hizmet',
          city: 'İstanbul',
          district: 'Beşiktaş',
          neighborhood: 'Cihannüma',
          addressLine: 'Açık adres',
          latitude: 41.0,
          longitude: 29.0,
          hasLogo: true,
          hasGalleryOrCoverPhoto: true,
          hasActiveService: true,
          hasValidWorkingHours: true,
        );

        final result1 = BarberProfileCompletion.calculate(input);
        final result2 = BarberProfileCompletion.calculate(input);

        expect(result1, 100);
        expect(result2, 100);
      },
    );

    test('logo true/false sonucu deterministic', () {
      const withLogo = BarberProfileCompletionInput(
        businessName: null,
        category: null,
        description: null,
        city: null,
        district: null,
        neighborhood: null,
        addressLine: null,
        latitude: null,
        longitude: null,
        hasLogo: true,
        hasGalleryOrCoverPhoto: false,
        hasActiveService: false,
        hasValidWorkingHours: false,
      );

      const withoutLogo = BarberProfileCompletionInput(
        businessName: null,
        category: null,
        description: null,
        city: null,
        district: null,
        neighborhood: null,
        addressLine: null,
        latitude: null,
        longitude: null,
        hasLogo: false,
        hasGalleryOrCoverPhoto: false,
        hasActiveService: false,
        hasValidWorkingHours: false,
      );

      expect(BarberProfileCompletion.calculate(withLogo), 10);
      expect(BarberProfileCompletion.calculate(withoutLogo), 0);
    });

    test(
      'calisma saatleri dogrulama (validateWorkingHours) dogru calisiyor',
      () {
        final openHours = [
          {'closed': false, 'open': '09:00', 'close': '18:00'},
        ];
        final closedHours = [
          {'closed': true, 'open': '09:00', 'close': '18:00'},
        ];

        expect(
          BarberProfileCompletionInput.validateWorkingHours(openHours),
          true,
        );
        expect(
          BarberProfileCompletionInput.validateWorkingHours(closedHours),
          false,
        );
        expect(BarberProfileCompletionInput.validateWorkingHours(null), false);
        expect(BarberProfileCompletionInput.validateWorkingHours(''), false);
      },
    );

    test(
      'Ana Sayfa input factory ile Profil input factory ayni profile icin esit sonuc uretir',
      () {
        final profileMap = {
          'businessName': 'Gök Berberr',
          'category': 'Tamir',
          'description': 'Teknik servis',
          'city': 'İstanbul',
          'district': 'Beşiktaş',
          'neighborhood': null,
          'addressLine': null,
          'lat': 41.042,
          'lng': 29.008,
          'workingHours': '[{"closed":false,"open":"09:00","close":"20:00"}]',
          'hasLogo': false,
        };

        // Ana Sayfa input'u (fromRawData)
        final homeInput = BarberProfileCompletionInput.fromRawData(
          profile: profileMap,
          serviceCount: 3,
          photoCount: 3,
          hasLogo: true, // logo bytes indirildi
        );

        // Profil ekranı input'u (direkt local state alanları üzerinden)
        final profileInput = BarberProfileCompletionInput(
          businessName: profileMap['businessName'] as String?,
          category: profileMap['category'] as String?,
          description: profileMap['description'] as String?,
          city: profileMap['city'] as String?,
          district: profileMap['district'] as String?,
          neighborhood: profileMap['neighborhood'] as String?,
          addressLine: profileMap['addressLine'] as String?,
          latitude: (profileMap['lat'] as num?)?.toDouble(),
          longitude: (profileMap['lng'] as num?)?.toDouble(),
          hasLogo: true, // logo bytes indirildi
          hasGalleryOrCoverPhoto: 3 > 0,
          hasActiveService: 3 > 0,
          hasValidWorkingHours:
              BarberProfileCompletionInput.validateWorkingHours(
                profileMap['workingHours'],
              ),
        );

        expect(
          BarberProfileCompletion.calculate(homeInput),
          BarberProfileCompletion.calculate(profileInput),
        );
        expect(
          BarberProfileCompletion.calculate(homeInput),
          80,
        ); // 8 alan dolu (%80)
      },
    );

    test('bosluk veya placeholder kelimeleri tamamlanmis sayilmaz', () {
      const input = BarberProfileCompletionInput(
        businessName: '   ',
        category: 'Yok',
        description: '-',
        city: 'Belirtilmedi',
        district: 'Beşiktaş',
        neighborhood: 'Cihannüma',
        addressLine: '',
        latitude: 0,
        longitude: 0,
        hasLogo: false,
        hasGalleryOrCoverPhoto: false,
        hasActiveService: false,
        hasValidWorkingHours: false,
      );

      final result = BarberProfileCompletion.calculateDetailed(input);
      expect(result.percentage, 0);
    });

    test('eksik alan listesi duplicate icermez', () {
      const input = BarberProfileCompletionInput(
        businessName: null,
        category: null,
        description: null,
        city: null,
        district: null,
        neighborhood: null,
        addressLine: null,
        latitude: null,
        longitude: null,
        hasLogo: false,
        hasGalleryOrCoverPhoto: false,
        hasActiveService: false,
        hasValidWorkingHours: false,
      );

      final result = BarberProfileCompletion.calculateDetailed(input);
      final suggestions = result.missingItems.where(
        (x) => x == 'Konum bilgilerini tamamla',
      );
      expect(suggestions.length, 1);
    });

    test('percentage 0-100 araligindadir', () {
      const input = BarberProfileCompletionInput(
        businessName: 'A',
        category: 'B',
        description: 'C',
        city: 'D',
        district: 'E',
        neighborhood: 'F',
        addressLine: 'G',
        latitude: double.nan,
        longitude: 9999,
        hasLogo: true,
        hasGalleryOrCoverPhoto: true,
        hasActiveService: true,
        hasValidWorkingHours: true,
      );

      final score = BarberProfileCompletion.calculate(input);
      expect(score, inInclusiveRange(0, 100));
    });
  });
}
