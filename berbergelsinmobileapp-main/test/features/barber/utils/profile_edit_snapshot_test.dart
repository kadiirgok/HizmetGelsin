import 'package:flutter_test/flutter_test.dart';
import 'package:berbergelsin/features/barber/screens/barber_profile_screen.dart';

void main() {
  group('ProfileEditSnapshot Unit Tests', () {
    late ProfileEditSnapshot baseSnapshot;

    setUp(() {
      baseSnapshot = ProfileEditSnapshot.fromState(
        businessName: 'Berber Ahmet',
        category: 'Kuaför',
        description: 'En iyi saç kesimi',
        city: 'İstanbul',
        district: 'Beşiktaş',
        neighborhood: 'Bebek',
        addressLine: 'Bebek Mah. No:1',
        serviceMode: 'Mobile',
        sharePhone: true,
        acceptsOffers: true,
        acceptsUrgentRequests: false,
        serviceRadiusKm: 10.0,
        lat: 41.0256,
        lng: 28.9744,
      );
    });

    test('ilk yüklemede dirty false olmalı', () {
      final isDirty = baseSnapshot.isDirty(
        businessName: 'Berber Ahmet',
        category: 'Kuaför',
        description: 'En iyi saç kesimi',
        city: 'İstanbul',
        district: 'Beşiktaş',
        neighborhood: 'Bebek',
        addressLine: 'Bebek Mah. No:1',
        serviceMode: 'Mobile',
        sharePhone: true,
        acceptsOffers: true,
        acceptsUrgentRequests: false,
        serviceRadiusKm: 10.0,
        lat: 41.0256,
        lng: 28.9744,
      );
      expect(isDirty, isFalse);
    });

    test('text (işletme adı) değişince dirty true olmalı', () {
      final isDirty = baseSnapshot.isDirty(
        businessName: 'Berber Ahmet Yeni',
        category: 'Kuaför',
        description: 'En iyi saç kesimi',
        city: 'İstanbul',
        district: 'Beşiktaş',
        neighborhood: 'Bebek',
        addressLine: 'Bebek Mah. No:1',
        serviceMode: 'Mobile',
        sharePhone: true,
        acceptsOffers: true,
        acceptsUrgentRequests: false,
        serviceRadiusKm: 10.0,
        lat: 41.0256,
        lng: 28.9744,
      );
      expect(isDirty, isTrue);
    });

    test(
      'text başında/sonunda boşluk olunca normalize edilip dirty false kalmalı',
      () {
        final isDirty = baseSnapshot.isDirty(
          businessName: '  Berber Ahmet  ',
          category: 'Kuaför',
          description: 'En iyi saç kesimi',
          city: 'İstanbul',
          district: 'Beşiktaş',
          neighborhood: 'Bebek',
          addressLine: 'Bebek Mah. No:1',
          serviceMode: 'Mobile',
          sharePhone: true,
          acceptsOffers: true,
          acceptsUrgentRequests: false,
          serviceRadiusKm: 10.0,
          lat: 41.0256,
          lng: 28.9744,
        );
        expect(isDirty, isFalse);
      },
    );

    test('switch (telefon paylaşımı) değişince dirty true olmalı', () {
      final isDirty = baseSnapshot.isDirty(
        businessName: 'Berber Ahmet',
        category: 'Kuaför',
        description: 'En iyi saç kesimi',
        city: 'İstanbul',
        district: 'Beşiktaş',
        neighborhood: 'Bebek',
        addressLine: 'Bebek Mah. No:1',
        serviceMode: 'Mobile',
        sharePhone: false,
        acceptsOffers: true,
        acceptsUrgentRequests: false,
        serviceRadiusKm: 10.0,
        lat: 41.0256,
        lng: 28.9744,
      );
      expect(isDirty, isTrue);
    });

    test('slider (hizmet yarıçapı) değişince dirty true olmalı', () {
      final isDirty = baseSnapshot.isDirty(
        businessName: 'Berber Ahmet',
        category: 'Kuaför',
        description: 'En iyi saç kesimi',
        city: 'İstanbul',
        district: 'Beşiktaş',
        neighborhood: 'Bebek',
        addressLine: 'Bebek Mah. No:1',
        serviceMode: 'Mobile',
        sharePhone: true,
        acceptsOffers: true,
        acceptsUrgentRequests: false,
        serviceRadiusKm: 15.0,
        lat: 41.0256,
        lng: 28.9744,
      );
      expect(isDirty, isTrue);
    });

    test(
      'slider küçük tolerans limitleri içinde kalınca (0.1 tolerans) dirty false kalmalı',
      () {
        final isDirty = baseSnapshot.isDirty(
          businessName: 'Berber Ahmet',
          category: 'Kuaför',
          description: 'En iyi saç kesimi',
          city: 'İstanbul',
          district: 'Beşiktaş',
          neighborhood: 'Bebek',
          addressLine: 'Bebek Mah. No:1',
          serviceMode: 'Mobile',
          sharePhone: true,
          acceptsOffers: true,
          acceptsUrgentRequests: false,
          serviceRadiusKm: 10.05,
          lat: 41.0256,
          lng: 28.9744,
        );
        expect(isDirty, isFalse);
      },
    );

    test('koordinat (latitude) değişince dirty true olmalı', () {
      final isDirty = baseSnapshot.isDirty(
        businessName: 'Berber Ahmet',
        category: 'Kuaför',
        description: 'En iyi saç kesimi',
        city: 'İstanbul',
        district: 'Beşiktaş',
        neighborhood: 'Bebek',
        addressLine: 'Bebek Mah. No:1',
        serviceMode: 'Mobile',
        sharePhone: true,
        acceptsOffers: true,
        acceptsUrgentRequests: false,
        serviceRadiusKm: 10.0,
        lat: 41.0257,
        lng: 28.9744,
      );
      expect(isDirty, isTrue);
    });

    test(
      'koordinat küçük tolerans limitleri içinde kalınca (1e-6 tolerans) dirty false kalmalı',
      () {
        final isDirty = baseSnapshot.isDirty(
          businessName: 'Berber Ahmet',
          category: 'Kuaför',
          description: 'En iyi saç kesimi',
          city: 'İstanbul',
          district: 'Beşiktaş',
          neighborhood: 'Bebek',
          addressLine: 'Bebek Mah. No:1',
          serviceMode: 'Mobile',
          sharePhone: true,
          acceptsOffers: true,
          acceptsUrgentRequests: false,
          serviceRadiusKm: 10.0,
          lat: 41.0256001,
          lng: 28.9744001,
        );
        expect(isDirty, isFalse);
      },
    );

    test('değer eski haline getirilince dirty false olmalı', () {
      // 1. Değeri değiştiriyoruz -> dirty true olmalı
      var isDirty = baseSnapshot.isDirty(
        businessName: 'Berber Ahmet Değişti',
        category: 'Kuaför',
        description: 'En iyi saç kesimi',
        city: 'İstanbul',
        district: 'Beşiktaş',
        neighborhood: 'Bebek',
        addressLine: 'Bebek Mah. No:1',
        serviceMode: 'Mobile',
        sharePhone: true,
        acceptsOffers: true,
        acceptsUrgentRequests: false,
        serviceRadiusKm: 10.0,
        lat: 41.0256,
        lng: 28.9744,
      );
      expect(isDirty, isTrue);

      // 2. Değeri eski haline getiriyoruz -> dirty false olmalı
      isDirty = baseSnapshot.isDirty(
        businessName: 'Berber Ahmet',
        category: 'Kuaför',
        description: 'En iyi saç kesimi',
        city: 'İstanbul',
        district: 'Beşiktaş',
        neighborhood: 'Bebek',
        addressLine: 'Bebek Mah. No:1',
        serviceMode: 'Mobile',
        sharePhone: true,
        acceptsOffers: true,
        acceptsUrgentRequests: false,
        serviceRadiusKm: 10.0,
        lat: 41.0256,
        lng: 28.9744,
      );
      expect(isDirty, isFalse);
    });

    test('başarılı save sonrası snapshot güncellenerek dirty false olur', () {
      // 1. Kullanıcı değişiklik yaptı
      final currentBusinessName = 'Berber Ahmet Yeni';
      var isDirty = baseSnapshot.isDirty(
        businessName: currentBusinessName,
        category: 'Kuaför',
        description: 'En iyi saç kesimi',
        city: 'İstanbul',
        district: 'Beşiktaş',
        neighborhood: 'Bebek',
        addressLine: 'Bebek Mah. No:1',
        serviceMode: 'Mobile',
        sharePhone: true,
        acceptsOffers: true,
        acceptsUrgentRequests: false,
        serviceRadiusKm: 10.0,
        lat: 41.0256,
        lng: 28.9744,
      );
      expect(isDirty, isTrue);

      // 2. Başarılı save sonrası snapshot güncellendi (simüle ediliyor)
      final savedSnapshot = ProfileEditSnapshot.fromState(
        businessName: currentBusinessName,
        category: 'Kuaför',
        description: 'En iyi saç kesimi',
        city: 'İstanbul',
        district: 'Beşiktaş',
        neighborhood: 'Bebek',
        addressLine: 'Bebek Mah. No:1',
        serviceMode: 'Mobile',
        sharePhone: true,
        acceptsOffers: true,
        acceptsUrgentRequests: false,
        serviceRadiusKm: 10.0,
        lat: 41.0256,
        lng: 28.9744,
      );

      // 3. Artık dirty değil
      final isDirtyAfterSave = savedSnapshot.isDirty(
        businessName: currentBusinessName,
        category: 'Kuaför',
        description: 'En iyi saç kesimi',
        city: 'İstanbul',
        district: 'Beşiktaş',
        neighborhood: 'Bebek',
        addressLine: 'Bebek Mah. No:1',
        serviceMode: 'Mobile',
        sharePhone: true,
        acceptsOffers: true,
        acceptsUrgentRequests: false,
        serviceRadiusKm: 10.0,
        lat: 41.0256,
        lng: 28.9744,
      );
      expect(isDirtyAfterSave, isFalse);
    });

    test(
      'başarısız save sonrası snapshot güncellenmediği için dirty true kalır',
      () {
        // 1. Kullanıcı değişiklik yaptı
        final currentBusinessName = 'Berber Ahmet Yeni';
        var isDirty = baseSnapshot.isDirty(
          businessName: currentBusinessName,
          category: 'Kuaför',
          description: 'En iyi saç kesimi',
          city: 'İstanbul',
          district: 'Beşiktaş',
          neighborhood: 'Bebek',
          addressLine: 'Bebek Mah. No:1',
          serviceMode: 'Mobile',
          sharePhone: true,
          acceptsOffers: true,
          acceptsUrgentRequests: false,
          serviceRadiusKm: 10.0,
          lat: 41.0256,
          lng: 28.9744,
        );
        expect(isDirty, isTrue);

        // 2. Başarısız save sonrası snapshot güncellenmedi (baseSnapshot aynı kaldı)
        // 3. Hala dirty true olmalı
        final isDirtyAfterFailedSave = baseSnapshot.isDirty(
          businessName: currentBusinessName,
          category: 'Kuaför',
          description: 'En iyi saç kesimi',
          city: 'İstanbul',
          district: 'Beşiktaş',
          neighborhood: 'Bebek',
          addressLine: 'Bebek Mah. No:1',
          serviceMode: 'Mobile',
          sharePhone: true,
          acceptsOffers: true,
          acceptsUrgentRequests: false,
          serviceRadiusKm: 10.0,
          lat: 41.0256,
          lng: 28.9744,
        );
        expect(isDirtyAfterFailedSave, isTrue);
      },
    );
  });
}
