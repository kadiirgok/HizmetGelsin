import 'dart:io';

import 'package:berbergelsin/customer_smoke/customer_smoke_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('customersmoke dependency isolation', () {
    test('repository inventory is deterministic and complete', () {
      final dependencies = CustomerSmokeDependencies.isolated();
      final repository = dependencies.repository;

      expect(repository.customer.id, startsWith('smoke-'));
      expect(repository.customer.displayName, isNotEmpty);
      expect(repository.addresses, hasLength(2));
      expect(repository.categories, hasLength(3));
      expect(repository.businesses, hasLength(2));
      expect(repository.services, hasLength(2));
      expect(repository.request.id, startsWith('smoke-'));
      expect(repository.offers, hasLength(2));
      expect(repository.appointments, hasLength(1));
      expect(repository.ratings, hasLength(1));
      expect(repository.favoriteBusinessIds, hasLength(1));
      expect(repository.notifications, hasLength(2));
    });

    test('dependency graph has no network, realtime, push or persistence', () {
      final dependencies = CustomerSmokeDependencies.isolated();

      expect(dependencies.hasHttpClient, isFalse);
      expect(dependencies.hasSignalRClient, isFalse);
      expect(dependencies.hasPushTokenProvider, isFalse);
      expect(dependencies.hasPersistentStorage, isFalse);
      expect(dependencies.repository.networkAttemptCount, 0);
      expect(dependencies.repository.signalRAttemptCount, 0);
      expect(dependencies.repository.pushRegistrationAttemptCount, 0);
    });

    test('fixture mutations remain local to each in-memory graph', () {
      final first = CustomerSmokeDependencies.isolated().repository;
      final second = CustomerSmokeDependencies.isolated().repository;

      first.selectAddress('smoke-address-work');
      first.useManualAddress('Fixture manuel adres');
      first.toggleFavorite('smoke-business-atelier');
      first.markAllNotificationsRead();

      expect(first.selectedAddressId, 'smoke-address-work');
      expect(first.manualAddress, 'Fixture manuel adres');
      expect(first.favoriteBusinessIds, isEmpty);
      expect(first.notifications.every((item) => item.isRead), isTrue);

      expect(second.selectedAddressId, 'smoke-address-home');
      expect(second.manualAddress, isNull);
      expect(second.favoriteBusinessIds, {'smoke-business-atelier'});
      expect(second.notifications.any((item) => !item.isRead), isTrue);
    });
  });

  group('build graph isolation', () {
    test('production entrypoint cannot reach customer fixture app', () {
      final productionMain = File('lib/main.dart').readAsStringSync();
      expect(productionMain, isNot(contains('customer_smoke')));
      expect(productionMain, isNot(contains('CUSTOMER_SMOKE_MODE')));
      expect(productionMain, contains('AuthCubit'));
      expect(productionMain, contains('PushService'));
      expect(productionMain, contains('buildRouter'));
    });

    test('customersmoke has a distinct guarded entrypoint and package', () {
      final smokeMain = File('lib/main_customersmoke.dart').readAsStringSync();
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();

      expect(smokeMain, contains("bool.fromEnvironment("));
      expect(smokeMain, contains("'CUSTOMER_SMOKE_MODE'"));
      expect(smokeMain, contains('defaultValue: false'));
      expect(smokeMain, contains('CustomerSmokeDependencies.isolated()'));
      expect(smokeMain, isNot(contains('AuthCubit')));
      expect(smokeMain, isNot(contains('PushService')));
      expect(smokeMain, isNot(contains('ApiClient')));

      expect(gradle, contains('create("customersmoke")'));
      expect(gradle, contains('applicationIdSuffix = ".customersmoke"'));
      expect(gradle, contains('variantBuilder.enable = false'));
      expect(gradle, contains('CUSTOMER_SMOKE_MODE=true'));
      expect(gradle, contains('main_customersmoke.dart'));
      expect(
        'com.berbergelsin.berbergelsin.customersmoke',
        isNot('com.berbergelsin.berbergelsin.releasetest'),
      );
    });

    test('combined smoke manifest removes every external capability', () {
      final manifest = File(
        'android/app/src/customersmokeDebug/AndroidManifest.xml',
      ).readAsStringSync();

      for (final permission in [
        'android.permission.INTERNET',
        'android.permission.ACCESS_COARSE_LOCATION',
        'android.permission.ACCESS_FINE_LOCATION',
        'android.permission.FOREGROUND_SERVICE',
        'android.permission.FOREGROUND_SERVICE_LOCATION',
        'android.permission.POST_NOTIFICATIONS',
      ]) {
        expect(manifest, contains(permission));
      }
      expect(manifest, contains('tools:node="remove"'));
      expect(manifest, contains('android:usesCleartextTraffic="false"'));
    });
  });
}
