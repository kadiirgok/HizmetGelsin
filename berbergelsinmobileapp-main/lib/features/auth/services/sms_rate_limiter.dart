import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// İstemci tarafı SMS rate limiter.
///
/// Strateji:
/// 1. **Progressive cooldown** — her istekte bekleme süresi katlanır:
///    1. istek → anında, 2. → 30sn, 3. → 60sn, 4. → 120sn, 5. → 300sn
/// 2. **Local rate limiter** — 1 saatte max 5 istek, backend'e gitmeden engeller
/// 3. **Graceful degradation** — saatlik limit dolunca geri sayım + alternatif yöntem
class SmsRateLimiter {
  static final SmsRateLimiter instance = SmsRateLimiter._();
  SmsRateLimiter._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const String _key = 'sms_request_timestamps';

  /// Progressive cooldown süreleri (saniye), request count'a göre index'li.
  /// count=0 → 0sn (ilk istek anında)
  /// count=1 → 30sn
  /// count=2 → 60sn
  /// count=3 → 120sn
  /// count=4 → 300sn
  static const List<int> _cooldowns = <int>[0, 30, 60, 120, 300];

  static const int _maxPerHour = 5;
  static const Duration _hourWindow = Duration(hours: 1);

  /// SMS isteği atılabilir mi kontrol et.
  ///
  /// Dönüş:
  /// - [SmsRateLimitResult.canSend] = true → istek atılabilir
  /// - [SmsRateLimitResult.canSend] = false → [waitSeconds] kadar beklemeli,
  ///   UI'da geri sayım göster
  Future<SmsRateLimitResult> checkCanSend() async {
    final List<DateTime> timestamps = await _getTimestamps();
    final DateTime now = DateTime.now();

    // Son 1 saattekileri filtrele
    final List<DateTime> recent = timestamps
        .where((DateTime t) => now.difference(t) < _hourWindow)
        .toList()
      ..sort();

    final int count = recent.length;

    // 1. Saatlik kapasite kontrolü
    if (count >= _maxPerHour) {
      final DateTime oldest = recent.first;
      final DateTime waitUntil = oldest.add(_hourWindow);
      final int waitSeconds = waitUntil.difference(now).inSeconds;
      return SmsRateLimitResult(
        canSend: false,
        waitSeconds: waitSeconds > 0 ? waitSeconds : 0,
        reason: 'Saatlik SMS limiti doldu.',
        nextAvailable: waitUntil,
      );
    }

    // 2. Progressive cooldown (count = şu ana kadar atılmış istek sayısı)
    if (count > 0 && count < _cooldowns.length) {
      final int cooldown = _cooldowns[count];
      if (cooldown > 0) {
        final DateTime lastRequest = recent.last;
        final DateTime waitUntil = lastRequest.add(Duration(seconds: cooldown));
        if (now.isBefore(waitUntil)) {
          final int waitSeconds = waitUntil.difference(now).inSeconds;
          return SmsRateLimitResult(
            canSend: false,
            waitSeconds: waitSeconds,
            reason: 'Lütfen $cooldown saniye bekleyip tekrar deneyin.',
            nextAvailable: waitUntil,
          );
        }
      }
    }

    return const SmsRateLimitResult(
      canSend: true,
      waitSeconds: 0,
      reason: '',
      nextAvailable: null,
    );
  }

  /// SMS isteği atıldı, kaydet.
  Future<void> recordRequest() async {
    final List<DateTime> timestamps = await _getTimestamps();
    timestamps.add(DateTime.now());

    // Sadece son 2 saati tut (1 saatlik pencere + güvenlik marjı)
    final DateTime cutoff = DateTime.now().subtract(const Duration(hours: 2));
    final List<DateTime> filtered = timestamps
        .where((DateTime t) => t.isAfter(cutoff))
        .toList();

    await _storage.write(
      key: _key,
      value: jsonEncode(
        filtered.map((DateTime t) => t.toIso8601String()).toList(),
      ),
    );
  }

  /// Firebase `too-many-requests` döndüğünde çağrılır.
  /// Tüm istekleri kaydedip 1 saatlik limiti doldurur gibi davran.
  Future<void> markRateLimited() async {
    final DateTime now = DateTime.now();
    // Son 1 saat içinde 5 istek varmış gibi işaretle
    final List<DateTime> fakeTimestamps = List<DateTime>.generate(
      _maxPerHour,
      (int i) => now.subtract(Duration(minutes: (_maxPerHour - 1 - i) * 3)),
    );
    await _storage.write(
      key: _key,
      value: jsonEncode(
        fakeTimestamps.map((DateTime t) => t.toIso8601String()).toList(),
      ),
    );
  }

  /// Depolanan istekleri temizle (hata ayıklama için).
  Future<void> reset() async {
    await _storage.delete(key: _key);
  }

  Future<List<DateTime>> _getTimestamps() async {
    final String? raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return <DateTime>[];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((dynamic s) => DateTime.parse(s as String))
          .toList();
    } catch (_) {
      return <DateTime>[];
    }
  }
}

class SmsRateLimitResult {
  final bool canSend;
  final int waitSeconds;
  final String reason;

  /// null = yok, otherwise en erken tekrar istek atılabilecek zaman
  final DateTime? nextAvailable;

  const SmsRateLimitResult({
    required this.canSend,
    required this.waitSeconds,
    required this.reason,
    this.nextAvailable,
  });
}
