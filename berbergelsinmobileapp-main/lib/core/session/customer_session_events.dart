import 'package:flutter/foundation.dart';

import '../signalr/signalr_service.dart';

typedef CustomerEventCallback = void Function(List<Object?>? args);

abstract interface class CustomerSessionVersionSource {
  Object get currentVersion;

  bool isCurrent(Object version);
}

/// Keeps a non-sensitive, in-memory generation for the active customer
/// session. The actual session key is never exposed or logged.
class CustomerSessionScope implements CustomerSessionVersionSource {
  CustomerSessionScope();

  static final CustomerSessionScope instance = CustomerSessionScope();

  Object _version = Object();
  String? _boundSessionKey;

  @override
  Object get currentVersion => _version;

  @override
  bool isCurrent(Object version) => identical(_version, version);

  /// Returns true when existing customer subscriptions were invalidated.
  bool bind(String? sessionKey) {
    if (_boundSessionKey == sessionKey) return false;
    _boundSessionKey = sessionKey;
    _version = Object();
    return true;
  }

  /// Invalidates subscriptions immediately, including while logout I/O runs.
  void clear() {
    _boundSessionKey = null;
    _version = Object();
  }
}

abstract interface class CustomerRealtimeClient {
  void Function() on(String event, CustomerEventCallback callback);

  void Function() onReconnected(VoidCallback callback);
}

class SignalRCustomerRealtimeClient implements CustomerRealtimeClient {
  const SignalRCustomerRealtimeClient();

  static const instance = SignalRCustomerRealtimeClient();

  @override
  void Function() on(String event, CustomerEventCallback callback) =>
      SignalRService.instance.on(event, callback);

  @override
  void Function() onReconnected(VoidCallback callback) =>
      SignalRService.instance.onReconnected(callback);
}

/// Owns customer-only SignalR listeners and guards every callback with the
/// session generation captured when the screen was created.
class CustomerSessionEventSubscriptions {
  CustomerSessionEventSubscriptions({
    required CustomerSessionVersionSource session,
    required CustomerRealtimeClient realtime,
  }) : _session = session,
       _realtime = realtime,
       _boundVersion = session.currentVersion;

  final CustomerSessionVersionSource _session;
  final CustomerRealtimeClient _realtime;
  final Object _boundVersion;
  final List<void Function()> _unsubscribers = [];
  bool _disposed = false;

  bool get isCurrent => !_disposed && _session.isCurrent(_boundVersion);

  void on(String event, CustomerEventCallback callback) {
    final unsubscribe = _realtime.on(event, (args) {
      if (!isCurrent) return;
      callback(args);
    });
    _unsubscribers.add(unsubscribe);
  }

  void onReconnected(VoidCallback callback) {
    final unsubscribe = _realtime.onReconnected(() {
      if (!isCurrent) return;
      callback();
    });
    _unsubscribers.add(unsubscribe);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final unsubscribe in _unsubscribers) {
      unsubscribe();
    }
    _unsubscribers.clear();
  }
}
