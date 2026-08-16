import 'dart:async';
import 'package:flutter/services.dart';

/// Android foreground service ile kalıcı "çevrimiçi" bildirimini yönetir.
/// Premium tasarım: koyu tema, yeşil durum noktası, dinamik talep sayısı, aksiyon butonları.
class OnlineForegroundService {
  static const _channel = MethodChannel('com.berbergelsin/online_service');

  /// Bildirimdeki toggle'a basılınca tetiklenir.
  static final toggleStream = StreamController<bool>.broadcast();

  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onOnlineToggle') {
        final online = call.arguments as bool? ?? false;
        toggleStream.add(online);
      }
    });
  }

  /// Çevrimiçi olduğunda kalıcı bildirimi başlat.
  static Future<bool> start({
    int pendingCount = 0,
    double todayEarning = 0,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('startForeground', {
        'pendingCount': pendingCount,
        'todayEarning': todayEarning,
      }) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Çevrimdışı olduğunda kalıcı bildirimi kaldır.
  static Future<bool> stop() async {
    try {
      return await _channel.invokeMethod<bool>('stopForeground') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Bildirim içeriğini güncelle (örn. yeni talep gelince).
  static Future<bool> update({
    int pendingCount = 0,
    double todayEarning = 0,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('updateForeground', {
        'pendingCount': pendingCount,
        'todayEarning': todayEarning,
      }) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Servis şu an aktif mi?
  static Future<bool> isActive() async {
    try {
      return await _channel.invokeMethod<bool>('isForegroundActive') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Bekleyen toggle event'i varsa döndür.
  static Future<bool?> consumeToggle() async {
    try {
      final result = await _channel.invokeMethod('consumeToggle');
      if (result == null) return null;
      return result as bool?;
    } catch (_) {
      return null;
    }
  }
}
