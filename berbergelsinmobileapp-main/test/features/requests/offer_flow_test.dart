import 'dart:ui';
import 'package:dio/dio.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:berbergelsin/core/api/api_client.dart';
import 'package:berbergelsin/features/requests/controllers/offer_submission.dart';
import 'package:berbergelsin/features/requests/data/requests_repo.dart';
import 'package:berbergelsin/features/requests/screens/my_requests_screen.dart';
import 'package:berbergelsin/core/signalr/signalr_service.dart';

PriceOfferModel offer({
  String id = 'o1',
  String status = 'Countered',
  DateTime? expires,
}) => PriceOfferModel(
  id: id,
  barberProfileId: 'b1',
  barberBusinessName: 'Çok Uzun Türkçe İşletme Adı',
  proposedPrice: 500,
  counterPrice: 650,
  status: status,
  requestedTime: DateTime.now().add(const Duration(days: 1)),
  note: 'Açıklama',
  createdAt: DateTime.now(),
  expiresAt: expires ?? DateTime.now().add(const Duration(hours: 2)),
);

class _FakeOffers implements OffersRepository {
  _FakeOffers(this.items);
  List<PriceOfferModel> items;
  int actions = 0;
  final keys = <String>[];
  Object? error;
  Completer<OfferActionResult>? pending;
  @override
  Future<List<PriceOfferModel>> mine({CancelToken? cancelToken}) async => items;
  @override
  Future<OfferActionResult> action(
    String id,
    String action, {
    double? counterPrice,
    required String idempotencyKey,
  }) async {
    actions++;
    keys.add(idempotencyKey);
    if (error case final e?) {
      throw e;
    }
    final pendingResult = pending == null ? null : await pending!.future;
    items = items.map((o) {
      if (o.id == id) {
        o.status = action == 'accept-counter'
            ? 'CounterAccepted'
            : 'CounterRejected';
      }
      return o;
    }).toList();
    return pendingResult ??
        const OfferActionResult(requestId: 'r1', status: 'CounterAccepted');
  }
}

class _ConflictOffers implements OffersRepository {
  _ConflictOffers(this.item);
  PriceOfferModel item;
  int refreshCalls = 0;
  int mutationCalls = 0;
  String? mutationOfferId;

  @override
  Future<List<PriceOfferModel>> mine({CancelToken? cancelToken}) async {
    refreshCalls++;
    return [item];
  }

  @override
  Future<OfferActionResult> action(
    String id,
    String action, {
    double? counterPrice,
    required String idempotencyKey,
  }) async {
    mutationCalls++;
    mutationOfferId = id;
    item.status = 'Rejected';
    throw ApiException(
      'raw database conflict detail',
      statusCode: 409,
      code: 'offer_concurrency_conflict',
    );
  }
}

void main() {
  test('offer DTO maps server expiration and accepted price', () {
    final o = PriceOfferModel.fromJson({
      'id': 'o',
      'barberProfileId': 'b',
      'proposedPrice': 10,
      'counterPrice': 12,
      'acceptedPrice': 12,
      'status': 'CounterAccepted',
      'requestedTime': '2026-07-17T10:00:00Z',
      'createdAt': '2026-07-16T10:00:00Z',
      'expiresAt': '2026-07-17T10:00:00Z',
    });
    expect(o.acceptedPrice, 12);
    expect(o.expiresAt.isAfter(o.createdAt), isTrue);
  });
  test(
    'all action transports include idempotency header and counter payload',
    () {
      for (final action in [
        'accept',
        'reject',
        'accept-counter',
        'reject-counter',
      ]) {
        final t = buildOfferActionTransport(
          'o',
          action,
          idempotencyKey: 'uuid',
        );
        expect(t.path, '/api/offers/o/$action');
        expect(t.headers['Idempotency-Key'], 'uuid');
      }
      final counter = buildOfferActionTransport(
        'o',
        'counter',
        counterPrice: 25,
        idempotencyKey: 'uuid',
      );
      expect(counter.body, {'counterPrice': 25});
    },
  );
  test(
    'action retry keeps key, payload change rotates and double begin is blocked',
    () {
      var n = 0;
      final s = OfferActionSession(keyFactory: () => 'k${++n}');
      final one = s.begin('counter', payload: 10);
      expect(s.begin('counter', payload: 10), isNull);
      s.failed();
      expect(s.begin('counter', payload: 10), one);
      s.failed();
      expect(s.begin('counter', payload: 11), isNot(one));
      s.succeeded();
      expect(s.activeKey, isNull);
    },
  );
  test('safe error mapping hides backend text', () {
    for (final code in [
      'offer_expired',
      'offer_invalid_transition',
      'offer_concurrency_conflict',
      'offer_rate_limited',
      'offer_idempotency_conflict',
    ]) {
      final mapped = mapOfferError(ApiException('raw sql', code: code));
      expect(mapped.message, isNot(contains('raw sql')));
    }
    expect(
      mapOfferError(ApiException('raw', kind: ApiErrorKind.network)).state,
      OfferUiState.networkError,
    );
  });
  test('countdown uses server expiry and reaches expired', () {
    final now = DateTime(2026, 1, 1, 10);
    expect(offerRemaining(now.add(const Duration(minutes: 5)), now), '5 dk');
    expect(
      offerRemaining(now.subtract(const Duration(seconds: 1)), now),
      'Süresi doldu',
    );
  });
  test('HTTP and connectivity failures have safe customer messages', () {
    for (final status in [400, 403, 404, 409, 429, 500, 503]) {
      final mapped = mapOfferError(
        ApiException('raw backend sql', statusCode: status),
      );
      expect(mapped.message, isNot(contains('raw backend sql')));
      expect(mapped.message, isNotEmpty);
    }
    for (final kind in [ApiErrorKind.network, ApiErrorKind.timeout]) {
      final mapped = mapOfferError(ApiException('socket raw', kind: kind));
      expect(mapped.state, OfferUiState.networkError);
      expect(mapped.message, isNot(contains('socket raw')));
    }
  });

  testWidgets('customer offer card shows real fields and allowed actions', (
    tester,
  ) async {
    final repo = _FakeOffers([offer()])
      ..pending = Completer<OfferActionResult>();
    await tester.pumpWidget(
      MaterialApp(
        home: MyRequestsScreen(
          offersRepository: repo,
          requestsLoader: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tekliflerim'));
    await tester.pumpAndSettle();
    expect(find.text('Çok Uzun Türkçe İşletme Adı'), findsOneWidget);
    expect(find.textContaining('Karşı teklif: 650'), findsOneWidget);
    expect(find.text('Kabul Et'), findsOneWidget);
    expect(find.text('Reddet'), findsOneWidget);
    expect(find.textContaining('Teklif ID: o1'), findsOneWidget);
  });
  testWidgets(
    'expired offer keeps disabled actions with an accessible reason',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final repo = _FakeOffers([
        offer(
          status: 'Pending',
          expires: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: MyRequestsScreen(
            offersRepository: repo,
            requestsLoader: () async => [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tekliflerim'));
      await tester.pumpAndSettle();
      expect(find.text('Kabul Et'), findsOneWidget);
      expect(find.text('Reddet'), findsOneWidget);
      expect(find.text('Karşı Teklif'), findsOneWidget);
      expect(find.text('Süresi doldu'), findsWidgets);
      for (final label in [
        'Teklifi kabul et. Teklif süresi dolduğu için kullanılamaz.',
        'Teklifi reddet. Teklif süresi dolduğu için kullanılamaz.',
        'Karşı teklif ver. Teklif süresi dolduğu için kullanılamaz.',
      ]) {
        final action = find.bySemanticsLabel(label);
        expect(action, findsOneWidget);
        expect(
          tester.getSemantics(action).flagsCollection.isEnabled,
          Tristate.isFalse,
        );
        expect(
          tester.getSemantics(action).flagsCollection.isButton,
          isTrue,
        );
      }
      expect(
        find.bySemanticsLabel(
          'Teklif süresi doldu. Bu teklif için işlem yapılamaz.',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets('active actions and minute countdown have explicit semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final now = DateTime(2026, 7, 19, 12);
    await tester.pumpWidget(
      MaterialApp(
        home: MyRequestsScreen(
          offersRepository: _FakeOffers([
            offer(
              status: 'Pending',
              expires: now.add(const Duration(minutes: 5)),
            ),
          ]),
          requestsLoader: () async => [],
          now: () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tekliflerim'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Teklif için 5 dakika kaldı.'),
      findsOneWidget,
    );
    for (final label in [
      'Teklifi kabul et',
      'Teklifi reddet',
      'Karşı teklif ver',
    ]) {
      final action = find.bySemanticsLabel(label);
      expect(action, findsOneWidget);
      expect(
        tester.getSemantics(action).flagsCollection.isEnabled,
        Tristate.isTrue,
      );
    }
    semantics.dispose();
  });

  testWidgets('countdown semantics switches to expired when timer elapses', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var now = DateTime(2026, 7, 19, 12);
    final item = offer(
      status: 'Pending',
      expires: now.add(const Duration(minutes: 1)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MyRequestsScreen(
          offersRepository: _FakeOffers([item]),
          requestsLoader: () async => [],
          now: () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tekliflerim'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Teklif için 1 dakika kaldı.'),
      findsOneWidget,
    );

    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(item.status, 'Expired');
    expect(
      find.bySemanticsLabel(
        'Teklif süresi doldu. Bu teklif için işlem yapılamaz.',
      ),
      findsWidgets,
    );
    final accept = find.bySemanticsLabel(
      'Teklifi kabul et. Teklif süresi dolduğu için kullanılamaz.',
    );
    expect(
      tester.getSemantics(accept).flagsCollection.isEnabled,
      Tristate.isFalse,
    );
    semantics.dispose();
  });
  testWidgets('offer detail uses existing business route and preserves sheet', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => MyRequestsScreen(
            offersRepository: _FakeOffers([offer()]),
            requestsLoader: () async => [],
          ),
        ),
        GoRoute(
          path: '/isletme/:id',
          builder: (_, state) =>
              Scaffold(body: Text('business:${state.pathParameters['id']}')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tekliflerim'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Teklif Detayı'));
    await tester.pumpAndSettle();
    final action = find.text('İşletmeyi Görüntüle');
    expect(action, findsOneWidget);
    await tester.tap(action);
    await tester.tap(action, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('business:b1'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('İşletmeyi Görüntüle'), findsOneWidget);
    router.dispose();
  });

  testWidgets('missing business id hides navigation action', (tester) async {
    final item = offer();
    final missing = PriceOfferModel(
      id: item.id,
      barberProfileId: '',
      barberBusinessName: item.barberBusinessName,
      proposedPrice: item.proposedPrice,
      counterPrice: item.counterPrice,
      status: item.status,
      requestedTime: item.requestedTime,
      note: item.note,
      createdAt: item.createdAt,
      expiresAt: item.expiresAt,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MyRequestsScreen(
          offersRepository: _FakeOffers([missing]),
          requestsLoader: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tekliflerim'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Teklif Detayı'));
    await tester.pumpAndSettle();
    expect(find.text('İşletmeyi Görüntüle'), findsNothing);
  });
  testWidgets('SignalR adds, deduplicates, updates and reconnect refreshes', (
    tester,
  ) async {
    final repo = _FakeOffers([]);
    var requestLoads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MyRequestsScreen(
          offersRepository: repo,
          requestsLoader: () async {
            requestLoads++;
            return [];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final baseline = requestLoads;
    repo.items = [offer(status: 'Pending')];
    SignalRService.instance.debugDispatch('NewOffer', [
      {'offerId': 'o1'},
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tekliflerim'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Teklif ID: o1'), findsOneWidget);
    SignalRService.instance.debugDispatch('NewOffer', [
      {'offerId': 'o1'},
    ]);
    await tester.pumpAndSettle();
    expect(find.textContaining('Teklif ID: o1'), findsOneWidget);
    repo.items.first.status = 'Rejected';
    SignalRService.instance.debugDispatch('OfferUpdated', [
      {'offerId': 'o1', 'status': 'Rejected'},
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Reddedildi'), findsOneWidget);
    SignalRService.instance.debugDispatch('RequestUpdated', [
      {'requestId': 'r1'},
    ]);
    SignalRService.instance.debugReconnect();
    await tester.pumpAndSettle();
    expect(requestLoads, greaterThanOrEqualTo(baseline + 5));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    final disposedLoads = requestLoads;
    SignalRService.instance.debugDispatch('NewOffer');
    SignalRService.instance.debugReconnect();
    await tester.pump();
    expect(requestLoads, disposedLoads);
  });
  testWidgets(
    '409 conflict unlocks card and directly refreshes current offer',
    (tester) async {
      final repo = _ConflictOffers(offer(status: 'Pending'));
      await tester.pumpWidget(
        MaterialApp(
          home: MyRequestsScreen(
            offersRepository: repo,
            requestsLoader: () async => [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.refreshCalls, 1);
      await tester.tap(find.text('Tekliflerim'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kabul Et'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kabulü Onayla'));
      await tester.pumpAndSettle();
      expect(repo.mutationCalls, 1);
      expect(repo.mutationOfferId, 'o1');
      expect(repo.refreshCalls, 2);
      expect(
        find.text('Teklif aynı anda güncellendi. Lütfen tekrar deneyin.'),
        findsOneWidget,
      );
      expect(find.textContaining('raw database'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Reddedildi'), findsOneWidget);
      expect(find.text('Kabul Et'), findsNothing);
    },
  );
  testWidgets('double action tap creates one call and updates card', (
    tester,
  ) async {
    final repo = _FakeOffers([offer()])
      ..pending = Completer<OfferActionResult>();
    await tester.pumpWidget(
      MaterialApp(
        home: MyRequestsScreen(
          offersRepository: repo,
          requestsLoader: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tekliflerim'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kabul Et'));
    await tester.pumpAndSettle();
    expect(find.text('Teklifi kabul et'), findsOneWidget);
    await tester.tap(find.text('Kabulü Onayla'));
    await tester.tap(find.text('Kabulü Onayla'), warnIfMissed: false);
    await tester.pump();
    expect(repo.actions, 1);
    repo.pending!.complete(
      const OfferActionResult(requestId: 'r1', status: 'CounterAccepted'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Anlaşıldı'), findsOneWidget);
  });
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets('offer list safe at ${width.toInt()}px and 1.3 text scale', (
      tester,
    ) async {
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
            home: MyRequestsScreen(
              offersRepository: _FakeOffers([offer()]),
              requestsLoader: () async => [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tekliflerim'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Teklif ID:'), findsOneWidget);
    });
  }
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets(
      'offer detail confirmations and counter are safe at ${width.toInt()}px, 1.3 scale and keyboard',
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
              home: MyRequestsScreen(
                offersRepository: _FakeOffers([offer(status: 'Pending')]),
                requestsLoader: () async => [],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tekliflerim'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Çok Uzun Türkçe İşletme Adı'));
        await tester.pumpAndSettle();
        expect(find.text('Hizmet bilgisi bulunamadı'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tapAt(const Offset(8, 8));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView).last, const Offset(0, -220));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kabul Et'));
        await tester.pumpAndSettle();
        expect(find.text('Kabulü Onayla'), findsOneWidget);
        await tester.tapAt(const Offset(8, 8));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reddet'));
        await tester.pumpAndSettle();
        expect(find.text('Reddetmeyi Onayla'), findsOneWidget);
        await tester.tapAt(const Offset(8, 8));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Karşı Teklif'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('counter-price-field')),
          '99999',
        );
        await tester.showKeyboard(find.byKey(const Key('counter-price-field')));
        await tester.pump();
        expect(
          find.text(
            'Bu aşamada yalnız fiyat için karşı teklif verebilirsiniz.',
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('submit-counter-offer')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
