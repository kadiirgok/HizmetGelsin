import 'package:berbergelsin/core/session/customer_session_events.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSession implements CustomerSessionVersionSource {
  Object _version = Object();

  @override
  Object get currentVersion => _version;

  @override
  bool isCurrent(Object version) => identical(version, _version);

  void changeUser() => _version = Object();

  void logout() => _version = Object();
}

class _EventRegistration {
  _EventRegistration(this.callback);
  final CustomerEventCallback callback;
  bool active = true;
}

class _ReconnectRegistration {
  _ReconnectRegistration(this.callback);
  final VoidCallback callback;
  bool active = true;
}

class _FakeRealtime implements CustomerRealtimeClient {
  final events = <String, List<_EventRegistration>>{};
  final reconnects = <_ReconnectRegistration>[];

  @override
  void Function() on(String event, CustomerEventCallback callback) {
    final registration = _EventRegistration(callback);
    events.putIfAbsent(event, () => []).add(registration);
    return () => registration.active = false;
  }

  @override
  void Function() onReconnected(VoidCallback callback) {
    final registration = _ReconnectRegistration(callback);
    reconnects.add(registration);
    return () => registration.active = false;
  }

  void dispatchRegistration(String event, int index) {
    events[event]![index].callback(const [<String, Object?>{}]);
  }

  void reconnectRegistration(int index) => reconnects[index].callback();
}

void main() {
  test(
    'A callbacks are rejected after A to B while B callbacks keep working',
    () {
      final session = _FakeSession();
      final realtime = _FakeRealtime();
      var aEvents = 0;
      var bEvents = 0;
      var aReconnects = 0;

      final listenerA =
          CustomerSessionEventSubscriptions(
              session: session,
              realtime: realtime,
            )
            ..on('NewOffer', (_) => aEvents++)
            ..onReconnected(() => aReconnects++);

      realtime.dispatchRegistration('NewOffer', 0);
      expect(aEvents, 1);

      session.changeUser();
      realtime.dispatchRegistration('NewOffer', 0);
      realtime.reconnectRegistration(0);
      expect(aEvents, 1, reason: 'late Session A event must be ignored');
      expect(aReconnects, 0, reason: 'old reconnect must stay invalid');

      final listenerB = CustomerSessionEventSubscriptions(
        session: session,
        realtime: realtime,
      )..on('NewOffer', (_) => bEvents++);
      realtime.dispatchRegistration('NewOffer', 1);
      expect(bEvents, 1);

      session.logout();
      realtime.dispatchRegistration('NewOffer', 1);
      expect(bEvents, 1, reason: 'logout must invalidate Session B');

      listenerA.dispose();
      listenerB.dispose();
      realtime.dispatchRegistration('NewOffer', 0);
      realtime.dispatchRegistration('NewOffer', 1);
      expect(aEvents, 1);
      expect(bEvents, 1, reason: 'disposed callbacks must be inert');
    },
  );
}
