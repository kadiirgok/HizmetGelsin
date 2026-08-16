import 'package:berbergelsin/features/auth/models/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUser.fromJson', () {
    test('parses role, onboarding and rating fields', () {
      final user = AppUser.fromJson({
        'id': 'user-1',
        'phone': '5551112233',
        'role': 'Berber',
        'onboardingCompleted': true,
        'barberStatus': 'Approved',
        'avgRating': 4,
        'ratingCount': 7.0,
      });

      expect(user.isApprovedBerber, isTrue);
      expect(user.avgRating, 4.0);
      expect(user.ratingCount, 7);
    });

    test('uses safe defaults for optional rating fields', () {
      final user = AppUser.fromJson({
        'id': 'user-2',
        'phone': '5551112244',
        'role': 'Musteri',
        'onboardingCompleted': false,
      });

      expect(user.isMusteri, isTrue);
      expect(user.ratingCount, 0);
      expect(user.avgRating, isNull);
    });
  });
}
