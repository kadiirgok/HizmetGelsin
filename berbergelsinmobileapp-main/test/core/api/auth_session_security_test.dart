import 'dart:async';
import 'dart:io';

import 'package:berbergelsin/core/api/api_client.dart';
import 'package:berbergelsin/features/auth/screens/account_blocked_screen.dart';
import 'package:berbergelsin/core/session/account_state_cleaner.dart';
import 'package:berbergelsin/features/addresses/data/client_addresses_repo.dart';
import 'package:berbergelsin/features/favorites/data/favorites_repo.dart';
import 'package:berbergelsin/features/notifications/controllers/notification_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('refresh failure policy only rejects authoritative auth failures', () {
    expect(classifyRefreshStatus(200), RefreshResult.success);
    for (final status in [400, 401, 403]) {
      expect(classifyRefreshStatus(status), RefreshResult.rejected);
    }
    for (final status in [null, 404, 408, 429, 500, 503]) {
      expect(classifyRefreshStatus(status), RefreshResult.transientFailure);
    }
  });

  test('secure storage keys are stable and diagnostics never log values', () {
    final storage = File('lib/core/api/token_storage.dart').readAsStringSync();
    final client = File('lib/core/api/api_client.dart').readAsStringSync();
    final auth = File(
      'lib/features/auth/bloc/auth_cubit.dart',
    ).readAsStringSync();
    expect(storage, contains("'access_token'"));
    expect(storage, contains("'refresh_token'"));
    expect(storage, contains("'session_role'"));
    expect(storage, isNot(contains('encryptedSharedPreferences')));
    expect('$client$auth', contains('session_diag'));
    expect(auth, contains(r'access_token_present=${access != null}'));
    expect(auth, contains(r'refresh_token_present=${refresh != null}'));
  });
  test('eşzamanlı 401 talepleri tek refresh işlemini paylaşır', () async {
    final gate = RefreshCoordinator();
    var calls = 0;
    final started = Completer<void>();
    Future<bool> operation() async {
      calls++;
      await started.future;
      return true;
    }

    final results = [
      gate.run(operation),
      gate.run(operation),
      gate.run(operation),
    ];
    expect(calls, 1);
    started.complete();
    expect(await Future.wait(results), everyElement(isTrue));
    expect(calls, 1);
  });

  test(
    'yalnız safe method veya idempotency key taşıyan mutation retry edilir',
    () {
      expect(
        canRetryAfterRefresh(RequestOptions(path: '/x', method: 'GET')),
        isTrue,
      );
      expect(
        canRetryAfterRefresh(RequestOptions(path: '/x', method: 'POST')),
        isFalse,
      );
      expect(
        canRetryAfterRefresh(
          RequestOptions(
            path: '/x',
            method: 'POST',
            headers: {'Idempotency-Key': 'same-key'},
          ),
        ),
        isTrue,
      );
    },
  );

  test('token deposu secure storage kullanır ve auth header loglamaz', () {
    final storage = File('lib/core/api/token_storage.dart').readAsStringSync();
    final client = File('lib/core/api/api_client.dart').readAsStringSync();
    expect(storage, contains('FlutterSecureStorage'));
    expect(storage, isNot(contains('SharedPreferences')));
    expect(client, isNot(contains('log(')));
    expect(client, isNot(contains('print(')));
  });

  test('hesap temizliği müşteri cachelerini sıfırlar', () {
    FavoriteStore.instance
      ..ids.add('foreign-business')
      ..loaded = true;
    NotificationStore.instance
      ..unread = 4
      ..page = 2;
    CustomerAddressSelectionStore.instance.select(
      ClientAddress(
        id: 'address-a',
        label: 'Ev',
        addressLine: 'Adres',
        latitude: 41,
        longitude: 29,
        isDefault: true,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        version: 'v1',
      ),
    );
    AccountStateCleaner.clear();
    expect(FavoriteStore.instance.ids, isEmpty);
    expect(FavoriteStore.instance.loaded, isFalse);
    expect(NotificationStore.instance.unread, 0);
    expect(NotificationStore.instance.page, 0);
    expect(CustomerAddressSelectionStore.instance.selectedAddress, isNull);
  });

  test('müşteri değişimi cacheleri temizler, aynı session temizlemez', () {
    AccountStateCleaner.endCustomerSession();
    AccountStateCleaner.bindCustomerSession('customer-a');
    FavoriteStore.instance.ids.add('kept-for-a');
    NotificationStore.instance.unread = 3;
    CustomerAddressSelectionStore.instance.select(
      ClientAddress(
        id: 'kept-address-a',
        label: 'Ev',
        addressLine: 'Adres',
        latitude: 41,
        longitude: 29,
        isDefault: true,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        version: 'v1',
      ),
    );

    AccountStateCleaner.bindCustomerSession('customer-a');
    expect(FavoriteStore.instance.ids, contains('kept-for-a'));
    expect(NotificationStore.instance.unread, 3);
    expect(
      CustomerAddressSelectionStore.instance.selectedAddressId,
      'kept-address-a',
    );

    AccountStateCleaner.bindCustomerSession('customer-b');
    expect(FavoriteStore.instance.ids, isEmpty);
    expect(NotificationStore.instance.unread, 0);
    expect(CustomerAddressSelectionStore.instance.selectedAddress, isNull);
    AccountStateCleaner.endCustomerSession();
  });

  testWidgets('blocked hesap ekranı 320px ve 1.3 ölçekte taşmaz', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: MaterialApp(home: AccountBlockedScreen()),
      ),
    );
    expect(find.text('Hesabınıza erişilemiyor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
