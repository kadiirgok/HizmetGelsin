import 'dart:async';

import 'package:berbergelsin/core/api/api_client.dart';
import 'package:berbergelsin/features/addresses/data/client_addresses_repo.dart';
import 'package:berbergelsin/features/addresses/screens/client_addresses_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ClientAddress address({
  String id = '1',
  String label = 'Ev',
  bool isDefault = true,
  String line = 'Çok uzun Türkçe açık adres satırı No: 123 Daire: 45',
}) => ClientAddress(
  id: id,
  label: label,
  addressLine: line,
  latitude: 41,
  longitude: 29,
  isDefault: isDefault,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  version: 'v',
  province: 'İstanbul',
  district: 'Kadıköy',
  neighborhood: 'Moda',
);

class FakeRepo implements ClientAddressesRepository {
  List<ClientAddress> items;
  FakeRepo(this.items);
  int creates = 0, updates = 0, deletes = 0, defaults = 0;
  int lists = 0;
  Object? error, mutationError;
  Completer<List<ClientAddress>>? pendingList;
  Future<T> run<T>(T value) async {
    if (error case final e?) throw e;
    return value;
  }

  @override
  Future<List<ClientAddress>> list() {
    lists++;
    if (pendingList case final pending?) return pending.future;
    return run(items);
  }

  @override
  Future<ClientAddress> get(String id) =>
      run(items.firstWhere((e) => e.id == id));
  @override
  Future<ClientAddress> create(ClientAddress v) async {
    creates++;
    items = [...items, address(id: 'new', label: v.label)];
    return run(items.last);
  }

  @override
  Future<ClientAddress> update(ClientAddress v) async {
    updates++;
    return run(v);
  }

  @override
  Future<void> delete(String id) async {
    deletes++;
    await run(null);
    items = items.where((e) => e.id != id).toList();
  }

  @override
  Future<ClientAddress> setDefault(String id) async {
    defaults++;
    if (mutationError case final failure?) {
      mutationError = null;
      throw failure;
    }
    items = [
      for (final a in items)
        address(
          id: a.id,
          label: a.label,
          isDefault: a.id == id,
          line: a.addressLine,
        ),
    ];
    return run(items.firstWhere((a) => a.id == id));
  }
}

void main() {
  setUp(CustomerAddressSelectionStore.instance.clearSession);

  test('active address stays synchronized across customer surfaces', () {
    final home = address(id: 'home', isDefault: true);
    final work = address(id: 'work', label: 'İş', isDefault: false);
    final store = CustomerAddressSelectionStore.instance;

    expect(store.resolve([home, work])?.id, 'home');
    store.select(work);
    expect(store.resolve([home, work])?.id, 'work', reason: 'map selection');
    expect(
      store.resolve([home, work])?.id,
      'work',
      reason: 'request form selection',
    );

    store.clearSession();
    expect(store.selectedAddress, isNull);
  });

  test('address maps safe DTO and payload carries version', () {
    final a = ClientAddress.fromJson({
      'id': '1',
      'label': 'Ev',
      'placeId': null,
      'addressLine': 'x',
      'latitude': 41,
      'longitude': 29,
      'isDefault': true,
      'createdAt': '2026-01-01T00:00:00Z',
      'updatedAt': '2026-01-01T00:00:00Z',
      'version': 'token',
    });
    expect(a.placeId, isNull);
    expect(a.toPayload()['version'], 'token');
    expect(a.toPayload().containsKey('userId'), false);
  });
  test('all address error codes map without raw backend text', () {
    for (final code in [
      'client_address_not_found',
      'client_address_invalid',
      'client_address_limit_reached',
      'client_address_forbidden',
      'client_address_conflict',
      'client_address_default_conflict',
    ]) {
      final e = mapClientAddressError(ApiException('raw sql', code: code));
      expect(clientAddressErrorMessage(e), isNot(contains('raw sql')));
    }
  });
  testWidgets('list card shows fields and default badge', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: ClientAddressesScreen(repository: FakeRepo([address()])),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Ev'), findsOneWidget);
    expect(find.text('Varsayılan adres'), findsOneWidget);
    expect(find.textContaining('Moda • Kadıköy'), findsOneWidget);
    expect(find.text('Harita konumu doğrulandı'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Ev.*varsayılan adres.*konum doğrulandı')),
      findsOneWidget,
    );
  });
  testWidgets('loading uses address card skeleton', (t) async {
    final pending = Completer<List<ClientAddress>>();
    final repo = FakeRepo([])..pendingList = pending;
    await t.pumpWidget(
      MaterialApp(home: ClientAddressesScreen(repository: repo)),
    );
    await t.pump();
    expect(find.bySemanticsLabel('İçerik yükleniyor'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    pending.complete([]);
    await t.pumpAndSettle();
  });
  testWidgets('offline address error is safe and retryable', (t) async {
    final repo = FakeRepo([])
      ..error = ApiException('raw socket detail', kind: ApiErrorKind.network);
    await t.pumpWidget(
      MaterialApp(home: ClientAddressesScreen(repository: repo)),
    );
    await t.pumpAndSettle();
    expect(find.text('İnternet bağlantısı yok'), findsOneWidget);
    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(find.textContaining('raw socket detail'), findsNothing);
  });
  testWidgets('empty state and create form validation', (t) async {
    final r = FakeRepo([]);
    await t.pumpWidget(MaterialApp(home: ClientAddressesScreen(repository: r)));
    await t.pumpAndSettle();
    expect(find.text('Henüz kayıtlı adresiniz yok'), findsOneWidget);
    await t.tap(find.text('Adres Ekle').first);
    await t.pumpAndSettle();
    expect(find.text('Harita konumu (dokunarak doğrulayın)'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Kaydet'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Kaydet'));
    await t.pump();
    expect(find.text('Etiket ve açık adres zorunludur.'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Manuel adres hatası: Etiket ve açık adres zorunludur.',
      ),
      findsOneWidget,
    );
  });
  testWidgets('delete confirmation removes item', (t) async {
    final r = FakeRepo([address()]);
    await t.pumpWidget(MaterialApp(home: ClientAddressesScreen(repository: r)));
    await t.pumpAndSettle();
    await t.tap(find.text('Sil'));
    await t.pumpAndSettle();
    expect(find.textContaining('Geçmiş talepler etkilenmez'), findsOneWidget);
    await t.tap(find.text('Kaldır'));
    await t.pumpAndSettle();
    expect(r.deletes, 1);
    expect(find.text('Henüz kayıtlı adresiniz yok'), findsOneWidget);
  });
  testWidgets('set default only locks selected card', (t) async {
    final r = FakeRepo([
      address(isDefault: false),
      address(id: '2', label: 'İş'),
    ]);
    await t.pumpWidget(MaterialApp(home: ClientAddressesScreen(repository: r)));
    await t.pumpAndSettle();
    await t.tap(find.text('Varsayılan Yap').first);
    await t.pumpAndSettle();
    expect(r.defaults, 1);
  });
  testWidgets('default conflict refreshes the address list', (t) async {
    final r = FakeRepo([address(isDefault: false)])
      ..mutationError = ApiException(
        'raw conflict',
        code: 'client_address_conflict',
        statusCode: 409,
      );
    await t.pumpWidget(MaterialApp(home: ClientAddressesScreen(repository: r)));
    await t.pumpAndSettle();
    final initialLists = r.lists;
    await t.tap(find.text('Varsayılan Yap'));
    await t.pumpAndSettle();
    expect(r.defaults, 1);
    expect(r.lists, greaterThan(initialLists));
    expect(find.textContaining('raw conflict'), findsNothing);
  });
  for (final w in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets('responsive ${w.toInt()} text 1.3', (t) async {
      t.view.physicalSize = Size(w, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: Size(w, 800),
            textScaler: const TextScaler.linear(1.3),
          ),
          child: MaterialApp(
            home: ClientAddressesScreen(repository: FakeRepo([address()])),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
