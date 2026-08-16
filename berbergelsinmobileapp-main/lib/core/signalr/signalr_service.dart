import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:signalr_netcore/signalr_client.dart';

import '../api/token_storage.dart';
import '../config.dart';

/// Tek hub bağlantısı: /hubs/app. Auth çözüldüğünde bağlanır,
/// kopmalarda otomatik yeniden bağlanır.
class SignalRService {
  SignalRService._();
  static final SignalRService instance = SignalRService._();

  HubConnection? _connection;
  final _listeners = <String, List<void Function(List<Object?>?)>>{};
  final _reconnectedListeners = <VoidCallback>[];

  bool get isConnected => _connection?.state == HubConnectionState.Connected;

  Future<void> connect() async {
    // Yalnızca Connected ise atla; Disconnected ve Reconnecting durumlarında yeniden bağlan
    if (_connection?.state == HubConnectionState.Connected) return;

    // Mevcut bağlantıyı temizle
    if (_connection != null) {
      try { await _connection!.stop(); } catch (_) {}
      _connection = null;
    }
    final connection = HubConnectionBuilder()
        .withUrl(
          AppConfig.hubUrl,
          options: HttpConnectionOptions(
            accessTokenFactory: () async =>
                (await TokenStorage.instance.accessToken) ?? '',
          ),
        )
        .withAutomaticReconnect()
        .build();
    connection.onreconnected(({connectionId}) {
      for (final callback in List<VoidCallback>.of(_reconnectedListeners)) {
        callback();
      }
    });

    // Kayıtlı dinleyicileri yeni bağlantıya uygula
    _listeners.forEach((event, callbacks) {
      for (final cb in callbacks) {
        connection.on(event, cb);
      }
    });

    _connection = connection;
    try {
      await connection.start();
    } catch (_) {
      // Bağlanamazsa sessiz geç; ekranlar REST üzerinden çalışmaya devam eder
    }
  }

  Future<void> disconnect() async {
    final conn = _connection;
    _connection = null;
    if (conn != null) {
      try {
        await conn.stop();
      } catch (_) {}
    }
  }

  /// Olay dinleyici ekler; unsubscribe fonksiyonu döndürür.
  void Function() on(
    String event,
    void Function(List<Object?>? args) callback,
  ) {
    _listeners.putIfAbsent(event, () => []).add(callback);
    _connection?.on(event, callback);
    return () {
      _listeners[event]?.remove(callback);
      _connection?.off(event, method: callback);
    };
  }

  Future<void> invoke(String method, {List<Object>? args}) async {
    final conn = _connection;
    if (conn == null || conn.state != HubConnectionState.Connected) return;
    try {
      await conn.invoke(method, args: args);
    } catch (_) {}
  }

  void Function() onReconnected(VoidCallback callback) {
    _reconnectedListeners.add(callback);
    return () => _reconnectedListeners.remove(callback);
  }

  @visibleForTesting
  void debugDispatch(String event, [List<Object?>? args]) {
    for (final callback in List<void Function(List<Object?>?)>.of(
      _listeners[event] ?? const [],
    )) {
      callback(args);
    }
  }

  @visibleForTesting
  void debugReconnect() {
    for (final callback in List<VoidCallback>.of(_reconnectedListeners)) {
      callback();
    }
  }
}
