import '../../../core/api/api_client.dart';
import 'request_submission.dart';

enum OfferUiState {
  initial,
  loading,
  success,
  empty,
  refreshing,
  actionSubmitting,
  actionSuccess,
  expired,
  invalidTransition,
  concurrencyConflict,
  rateLimited,
  networkError,
}

class OfferActionSession {
  OfferActionSession({RequestKeyFactory? keyFactory})
    : _keyFactory = keyFactory ?? newRequestUuid;
  final RequestKeyFactory _keyFactory;
  String? _key, _fingerprint;
  bool busy = false;

  String? begin(String action, {Object? payload}) {
    if (busy) return null;
    final fingerprint = '$action|${payload ?? ''}';
    if (_fingerprint != fingerprint) {
      _fingerprint = fingerprint;
      _key = _keyFactory();
    }
    busy = true;
    return _key;
  }

  void failed() => busy = false;
  void succeeded() {
    busy = false;
    _key = null;
    _fingerprint = null;
  }

  String? get activeKey => _key;
}

({OfferUiState state, String message}) mapOfferError(
  ApiException error,
) => switch (error.code) {
  'offer_expired' => (
    state: OfferUiState.expired,
    message: 'Teklifin süresi doldu.',
  ),
  'offer_invalid_transition' => (
    state: OfferUiState.invalidTransition,
    message: 'Teklif başka bir cihazda güncellendi. Liste yenileniyor.',
  ),
  'offer_concurrency_conflict' => (
    state: OfferUiState.concurrencyConflict,
    message: 'Teklif aynı anda güncellendi. Lütfen tekrar deneyin.',
  ),
  'offer_rate_limited' => (
    state: OfferUiState.rateLimited,
    message: 'Çok sık işlem yaptınız. Bir süre sonra tekrar deneyin.',
  ),
  'offer_idempotency_conflict' => (
    state: OfferUiState.invalidTransition,
    message: 'İşlem içeriği değişti. Lütfen tekrar deneyin.',
  ),
  'offer_price_invalid' => (
    state: OfferUiState.invalidTransition,
    message: 'Fiyat 1–100.000 TL arasında olmalıdır.',
  ),
  'offer_forbidden' => (
    state: OfferUiState.invalidTransition,
    message: 'Bu teklif için işlem yetkiniz yok.',
  ),
  'offer_not_found' || 'offer_request_unavailable' => (
    state: OfferUiState.invalidTransition,
    message: 'Teklif veya bağlı talep artık kullanılamıyor.',
  ),
  _ when error.statusCode == 400 => (
    state: OfferUiState.invalidTransition,
    message: 'Teklif bilgilerini kontrol edip tekrar deneyin.',
  ),
  _ when error.statusCode == 403 => (
    state: OfferUiState.invalidTransition,
    message: 'Bu teklif için işlem yetkiniz yok.',
  ),
  _ when error.statusCode == 404 => (
    state: OfferUiState.invalidTransition,
    message: 'Teklif veya bağlı talep artık bulunamıyor.',
  ),
  _ when error.statusCode == 409 => (
    state: OfferUiState.concurrencyConflict,
    message: 'Teklif güncellendi. Liste yenileniyor.',
  ),
  _ when error.statusCode == 429 => (
    state: OfferUiState.rateLimited,
    message: 'Çok sık işlem yaptınız. Bir süre sonra tekrar deneyin.',
  ),
  _ when (error.statusCode ?? 0) >= 500 => (
    state: OfferUiState.networkError,
    message: 'Hizmet geçici olarak kullanılamıyor. Lütfen tekrar deneyin.',
  ),
  _
      when error.kind == ApiErrorKind.network ||
          error.kind == ApiErrorKind.timeout =>
    (
      state: OfferUiState.networkError,
      message:
          'Bağlantı kurulamadı. Aynı işlemi güvenle tekrar deneyebilirsiniz.',
    ),
  _ => (
    state: OfferUiState.networkError,
    message: 'Teklif işlemi tamamlanamadı. Lütfen tekrar deneyin.',
  ),
};

String offerRemaining(DateTime expiresAt, DateTime now) {
  final remaining = expiresAt.difference(now);
  if (remaining <= Duration.zero) return 'Süresi doldu';
  if (remaining.inHours >= 24) {
    return '${remaining.inDays} gün ${remaining.inHours % 24} sa';
  }
  if (remaining.inHours > 0) {
    return '${remaining.inHours} sa ${remaining.inMinutes % 60} dk';
  }
  return '${remaining.inMinutes.clamp(0, 59)} dk';
}

String offerCountdownSemantics(DateTime expiresAt, DateTime now) {
  final remaining = expiresAt.difference(now);
  if (remaining <= Duration.zero) {
    return 'Teklif süresi doldu. Bu teklif için işlem yapılamaz.';
  }
  final minutes = (remaining.inSeconds + 59) ~/ 60;
  if (minutes >= 24 * 60) {
    final days = minutes ~/ (24 * 60);
    final hours = (minutes % (24 * 60)) ~/ 60;
    return hours == 0
        ? 'Teklif için $days gün kaldı.'
        : 'Teklif için $days gün $hours saat kaldı.';
  }
  if (minutes >= 60) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0
        ? 'Teklif için $hours saat kaldı.'
        : 'Teklif için $hours saat $rest dakika kaldı.';
  }
  return 'Teklif için $minutes dakika kaldı.';
}

String offerActionSemanticsLabel(String action, {required bool expired}) =>
    expired ? '$action. Teklif süresi dolduğu için kullanılamaz.' : action;
