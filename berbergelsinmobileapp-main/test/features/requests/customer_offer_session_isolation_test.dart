import 'package:berbergelsin/core/session/customer_session_events.dart';
import 'package:berbergelsin/features/requests/data/requests_repo.dart';
import 'package:berbergelsin/features/requests/screens/my_requests_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSession implements CustomerSessionVersionSource {
  Object _version = Object();

  @override
  Object get currentVersion => _version;

  @override
  bool isCurrent(Object version) => identical(version, _version);

  void change() => _version = Object();
}

class _EventRegistration {
  _EventRegistration(this.callback);
  final CustomerEventCallback callback;
}

class _FakeSignalR implements CustomerRealtimeClient {
  final events = <String, List<_EventRegistration>>{};
  final reconnects = <VoidCallback>[];

  @override
  void Function() on(String event, CustomerEventCallback callback) {
    final registration = _EventRegistration(callback);
    events.putIfAbsent(event, () => []).add(registration);
    return () {};
  }

  @override
  void Function() onReconnected(VoidCallback callback) {
    reconnects.add(callback);
    return () {};
  }

  void dispatch(String event, int registration) =>
      events[event]![registration].callback(const [
        {'offerId': 'offer-b'},
      ]);
}

class _FakeOffers implements OffersRepository {
  final item = PriceOfferModel(
    id: 'offer-b',
    barberProfileId: 'business',
    barberBusinessName: 'Session B İşletmesi',
    proposedPrice: 400,
    status: 'Pending',
    requestedTime: DateTime(2026, 7, 21),
    createdAt: DateTime(2026, 7, 19),
    expiresAt: DateTime(2027),
  );
  int loads = 0;

  @override
  Future<List<PriceOfferModel>> mine({CancelToken? cancelToken}) async {
    loads++;
    return [item];
  }

  @override
  Future<OfferActionResult> action(
    String id,
    String action, {
    double? counterPrice,
    required String idempotencyKey,
  }) => throw UnimplementedError();
}

void main() {
  testWidgets(
    'offer screen isolates A, accepts B, ignores logout reconnect and dispose',
    (tester) async {
      final session = _FakeSession();
      final signalR = _FakeSignalR();
      final repo = _FakeOffers();
      var requestLoads = 0;

      Widget screen(Key key) => MaterialApp(
        home: MyRequestsScreen(
          key: key,
          offersRepository: repo,
          requestsLoader: () async {
            requestLoads++;
            return [];
          },
          realtimeClient: signalR,
          sessionSource: session,
        ),
      );

      await tester.pumpWidget(screen(const ValueKey('session-a')));
      await tester.pumpAndSettle();
      final afterInitialA = requestLoads;
      signalR.dispatch('NewOffer', 0);
      await tester.pumpAndSettle();
      expect(requestLoads, afterInitialA + 1);

      session.change();
      final afterChange = requestLoads;
      signalR.dispatch('NewOffer', 0);
      signalR.reconnects[0]();
      await tester.pumpAndSettle();
      expect(requestLoads, afterChange, reason: 'A callbacks are stale');

      await tester.pumpWidget(screen(const ValueKey('session-b')));
      await tester.pumpAndSettle();
      final afterInitialB = requestLoads;
      signalR.dispatch('NewOffer', 1);
      await tester.pumpAndSettle();
      expect(requestLoads, afterInitialB + 1);

      signalR.dispatch('NewOffer', 1);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tekliflerim'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Teklif ID: offer-b'), findsOneWidget);

      session.change();
      final afterLogout = requestLoads;
      signalR.dispatch('NewOffer', 1);
      signalR.reconnects[1]();
      await tester.pumpAndSettle();
      expect(requestLoads, afterLogout);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      signalR.dispatch('NewOffer', 1);
      await tester.pump();
      expect(requestLoads, afterLogout, reason: 'disposed screen stays inert');
    },
  );
}
