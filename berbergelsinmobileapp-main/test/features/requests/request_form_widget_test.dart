import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:berbergelsin/core/api/api_client.dart';
import 'package:berbergelsin/features/map/data/barbers_repo.dart';
import 'package:berbergelsin/features/map/widgets/barber_sheet.dart';
import 'package:berbergelsin/features/requests/data/requests_repo.dart';

class _FakeCreator implements ServiceRequestCreator {
  int calls = 0;
  final keys = <String>[];
  Completer<ServiceRequestModel>? pending;
  Object? nextError;
  @override
  Future<ServiceRequestModel> create({
    required String barberProfileId,
    required List<String> serviceIds,
    required DateTime requestedTime,
    double? lat,
    double? lng,
    String? addressNote,
    String? addressId,
    String? serviceLocationType,
    required String idempotencyKey,
  }) async {
    calls++;
    keys.add(idempotencyKey);
    if (nextError case final error?) {
      nextError = null;
      throw error;
    }
    if (pending case final value?) return value.future;
    return _model(barberProfileId, requestedTime, lat, lng);
  }
}

ServiceRequestModel _model(
  String barberId,
  DateTime time,
  double? lat,
  double? lng,
) => ServiceRequestModel(
  id: '12345678-1234-4234-8234-123456789012',
  barberProfileId: barberId,
  status: 'Pending',
  requestedTime: time,
  lat: lat,
  lng: lng,
  totalPrice: 100,
  items: const [],
  createdAt: DateTime.now(),
  canRate: false,
);

BarberDetail _detail() => BarberDetail(
  barberProfileId: 'b1',
  businessName: 'Test İşletme',
  serviceMode: 'Shop',
  workingHours:
      '[${List.generate(7, (i) => '{"day":${i + 1},"open":"00:00","close":"23:59","closed":false}').join(',')}]',
  acceptsOffers: false,
  services: [BarberServiceItem(id: 's1', name: 'Saç Kesimi', price: 100)],
);

Future<void> _open(WidgetTester tester, _FakeCreator creator) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => showBarberSheet(
              context,
              'b1',
              41,
              29,
              initialDetail: _detail(),
              requestCreator: creator,
            ),
            child: const Text('Aç'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Aç'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('barber-service-control-s1')));
  await tester.pump();
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await tester.pumpAndSettle();
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('double tap submits once, locks form and shows success', (
    tester,
  ) async {
    final creator = _FakeCreator()..pending = Completer<ServiceRequestModel>();
    await _open(tester, creator);
    final button = find.text('Hizmet Talebi Oluştur');
    await tester.tap(button);
    await tester.tap(button);
    await tester.pump();
    expect(creator.calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    creator.pending!.complete(_model('b1', DateTime.now(), 41, 29));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('request-success-state')), findsOneWidget);
    expect(find.byKey(const Key('go-to-my-requests')), findsOneWidget);
  });

  testWidgets('network retry reuses the same key and succeeds', (tester) async {
    final creator = _FakeCreator()
      ..nextError = ApiException('raw network', kind: ApiErrorKind.network);
    await _open(tester, creator);
    await tester.tap(find.text('Hizmet Talebi Oluştur'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aynı talebi güvenle'), findsOneWidget);
    await tester.tap(find.text('Hizmet Talebi Oluştur'));
    await tester.pumpAndSettle();
    expect(creator.calls, 2);
    expect(creator.keys[0], creator.keys[1]);
    expect(find.byKey(const Key('request-success-state')), findsOneWidget);
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets(
      'request form is safe at ${width.toInt()}px and text scale 1.3',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              size: Size(width, 800),
              textScaler: const TextScaler.linear(1.3),
            ),
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: FilledButton(
                    onPressed: () => showBarberSheet(
                      context,
                      'b1',
                      41,
                      29,
                      initialDetail: _detail(),
                      requestCreator: _FakeCreator(),
                    ),
                    child: const Text('Aç'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Aç'));
        await tester.pumpAndSettle();
        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
        await tester.pumpAndSettle();
        scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(find.text('Hizmet Talebi Oluştur'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
