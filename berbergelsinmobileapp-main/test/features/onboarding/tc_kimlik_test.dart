import 'package:berbergelsin/features/onboarding/screens/barber_onboarding_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isValidTcKimlik', () {
    test('rejects malformed values', () {
      expect(isValidTcKimlik(''), isFalse);
      expect(isValidTcKimlik('123'), isFalse);
      expect(isValidTcKimlik('abcdefghijk'), isFalse);
      expect(isValidTcKimlik('01234567890'), isFalse);
    });

    test('rejects a value with an invalid checksum', () {
      expect(isValidTcKimlik('10000000147'), isFalse);
    });
  });
}
