import 'dart:async';

import 'package:berbergelsin/core/api/api_client.dart';
import 'package:berbergelsin/features/requests/data/requests_repo.dart';
import 'package:berbergelsin/features/requests/screens/request_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ServiceRequestModel request({String status = 'Accepted'}) =>
    ServiceRequestModel(
      id: 'r1',
      barberProfileId: 'b1',
      barberBusinessName: 'Çok Uzun Türkçe İşletme Adı',
      status: status,
      requestedTime: DateTime.now().add(const Duration(days: 2)),
      lat: 41,
      lng: 29,
      totalPrice: 250,
      items: [(serviceName: 'Saç Kesimi', price: 250)],
      createdAt: DateTime.now(),
      canRate: false,
    );

RequestTimelineEntry timelineEntry({
  String id = 'h1',
  String from = 'Pending',
  String to = 'Accepted',
  String role = 'Berber',
  DateTime? at,
}) => RequestTimelineEntry(
  id: id,
  fromStatus: from,
  toStatus: to,
  changedByRole: role,
  reasonText: 'Müşterinin uzun açıklaması',
  createdAt: at ?? DateTime.now(),
  reasonCode: 'reason',
);

class FakeTracking implements RequestTrackingRepository {
  FakeTracking(this.item, {List<RequestTimelineEntry>? history})
    : history = history ?? [timelineEntry()];
  ServiceRequestModel item;
  List<RequestTimelineEntry> history;
  int cancelCalls = 0, rescheduleCalls = 0, resolveCalls = 0;
  String? key;
  Completer<void>? pending;
  Object? error;
  @override
  Future<ServiceRequestModel> detail(String id) async => item;
  @override
  Future<List<ServiceRequestModel>> mine() async => [item];
  @override
  Future<List<RequestTimelineEntry>> timeline(String id) async => history;
  Future<void> _perform(String k) async {
    key = k;
    if (error case final e?) throw e;
    await pending?.future;
  }

  @override
  Future<void> cancelRequest(
    String id, {
    required String reasonCode,
    String? reasonText,
    required String idempotencyKey,
  }) async {
    cancelCalls++;
    await _perform(idempotencyKey);
    item.status = 'Cancelled';
  }

  @override
  Future<void> reschedule(
    String id,
    DateTime requestedStartAt, {
    String? reason,
    required String idempotencyKey,
  }) async {
    rescheduleCalls++;
    await _perform(idempotencyKey);
    item.status = 'ReschedulePending';
  }

  @override
  Future<void> resolveReschedule(
    String id,
    bool accept, {
    required String idempotencyKey,
  }) async {
    resolveCalls++;
    await _perform(idempotencyKey);
    item.status = 'Accepted';
  }
}

void main() {
  test('timeline mapping removes duplicates and sorts deterministically', () {
    final rows = mapRequestTimeline([
      {
        'id': 'b',
        'fromStatus': 'Accepted',
        'toStatus': 'OnTheWay',
        'changedByRole': 'Berber',
        'createdAt': '2026-07-16T11:00:00Z',
      },
      {
        'id': 'a',
        'fromStatus': 'Pending',
        'toStatus': 'Accepted',
        'changedByRole': 'Berber',
        'createdAt': '2026-07-16T10:00:00Z',
      },
      {
        'id': 'a',
        'fromStatus': 'Pending',
        'toStatus': 'Accepted',
        'changedByRole': 'Berber',
        'createdAt': '2026-07-16T10:00:00Z',
      },
    ]);
    expect(rows.map((e) => e.id), ['a', 'b']);
  });
  test('cancel transport carries body and idempotency header', () {
    final t = buildRequestLifecycleTransport(
      'r',
      'cancel',
      reasonCode: 'plans_changed',
      reasonText: 'x',
      idempotencyKey: 'uuid',
    );
    expect(t.path, '/api/requests/r/cancel');
    expect(t.headers['Idempotency-Key'], 'uuid');
    expect(t.body?['reasonCode'], 'plans_changed');
  });
  test('reschedule and resolve routes are exact', () {
    final d = DateTime.utc(2026, 8, 1, 10);
    expect(
      buildRequestLifecycleTransport(
        'r',
        'reschedule',
        requestedStartAt: d,
        idempotencyKey: 'k',
      ).body?['requestedStartAt'],
      '2026-08-01T10:00:00.000Z',
    );
    expect(
      buildRequestLifecycleTransport(
        'r',
        'reschedule/accept',
        idempotencyKey: 'k',
      ).path,
      '/api/requests/r/reschedule/accept',
    );
    expect(
      buildRequestLifecycleTransport(
        'r',
        'reschedule/reject',
        idempotencyKey: 'k',
      ).path,
      '/api/requests/r/reschedule/reject',
    );
  });
  test('safe lifecycle error mapping hides backend message', () {
    final mapped = mapRequestLifecycleError(
      ApiException('raw sql', code: 'request_concurrency_conflict'),
    );
    expect(mapped.state, RequestDetailState.concurrencyConflict);
    expect(mapped.message, isNot(contains('raw sql')));
  });
  testWidgets('detail and chronological timeline render', (tester) async {
    final repo = FakeTracking(
      request(),
      history: [
        timelineEntry(id: '1'),
        timelineEntry(
          id: '2',
          from: 'Accepted',
          to: 'OnTheWay',
          at: DateTime.now().add(const Duration(minutes: 1)),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RequestDetailScreen(requestId: 'r1', repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Çok Uzun Türkçe İşletme Adı'), findsOneWidget);
    expect(find.textContaining('Bekliyor → Onaylandı'), findsOneWidget);
    expect(find.textContaining('Onaylandı → Yolda'), findsOneWidget);
  });
  testWidgets('completed request hides lifecycle actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RequestDetailScreen(
          requestId: 'r1',
          repository: FakeTracking(request(status: 'Completed')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('İptal Et'), findsNothing);
    expect(find.text('Yeniden Planla'), findsNothing);
  });
  testWidgets('cancel reason is mandatory and double submit is locked', (
    tester,
  ) async {
    final repo = FakeTracking(request())..pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: RequestDetailScreen(requestId: 'r1', repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('İptal Et'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'İptal Et'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('İptal nedeni *'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Planım değişti').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'İptal Et'));
    await tester.pump();
    expect(repo.cancelCalls, 1);
    repo.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('İptal Edildi'), findsWidgets);
  });
  testWidgets('business reschedule proposal exposes customer accept reject', (
    tester,
  ) async {
    final repo = FakeTracking(
      request(status: 'ReschedulePending'),
      history: [timelineEntry(to: 'ReschedulePending', role: 'Berber')],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RequestDetailScreen(requestId: 'r1', repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Öneriyi Kabul Et'), findsOneWidget);
    expect(find.text('Öneriyi Reddet'), findsOneWidget);
  });
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets('detail responsive ${width.toInt()} and text 1.3', (
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
            home: RequestDetailScreen(
              requestId: 'r1',
              repository: FakeTracking(request()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
