import 'package:berbergelsin/core/signalr/signalr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'duplicate events are observable and unsubscribe prevents stale update',
    () {
      var calls = 0;
      final unsubscribe = SignalRService.instance.on(
        'E2ETestEvent',
        (_) => calls++,
      );
      SignalRService.instance
        ..debugDispatch('E2ETestEvent')
        ..debugDispatch('E2ETestEvent');
      expect(calls, 2);
      unsubscribe();
      SignalRService.instance.debugDispatch('E2ETestEvent');
      expect(calls, 2);
    },
  );

  test('reconnect refresh listener runs once and can be disposed', () {
    var refreshes = 0;
    final unsubscribe = SignalRService.instance.onReconnected(
      () => refreshes++,
    );
    SignalRService.instance.debugReconnect();
    expect(refreshes, 1);
    unsubscribe();
    SignalRService.instance.debugReconnect();
    expect(refreshes, 1);
  });
}
