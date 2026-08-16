import 'package:berbergelsin/features/map/data/barbers_repo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'eski metin adres korunur ve update payload mevcut sözleşmeyi bozmaz',
    () {
      const legacyAddress = 'Eski serbest metin adresi, kapı yanı';
      final payload = buildBarberProfileUpdatePayload(
        city: 'İstanbul',
        district: 'Kadıköy',
        neighborhood: null,
        addressLine: legacyAddress,
        sharePhone: false,
        acceptsOffers: true,
        acceptsUrgentRequests: false,
        serviceRadiusKm: 5,
      );
      expect(payload['addressLine'], legacyAddress);
      expect(
        payload.keys,
        unorderedEquals([
          'businessName',
          'category',
          'description',
          'serviceMode',
          'city',
          'district',
          'neighborhood',
          'addressLine',
          'sharePhone',
          'acceptsOffers',
          'acceptsUrgentRequests',
          'serviceRadiusKm',
        ]),
      );
      expect(payload.containsKey('placeId'), isFalse);
      expect(payload.containsKey('formattedAddress'), isFalse);
      expect(payload.containsKey('latitude'), isFalse);
      expect(payload.containsKey('longitude'), isFalse);
    },
  );
}
