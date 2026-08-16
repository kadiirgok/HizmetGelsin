import 'dart:math';

import '../../../core/api/api_client.dart';
import '../../barber/data/business_working_hours.dart';

enum RequestSubmissionState {
  initial,
  editing,
  submitting,
  success,
  validationError,
  timeConflict,
  outsideServiceArea,
  businessUnavailable,
  serviceUnavailable,
  rateLimited,
  networkError,
}

typedef RequestKeyFactory = String Function();

String newRequestUuid() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String part(int start, int end) => bytes
      .sublist(start, end)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${part(0, 4)}-${part(4, 6)}-${part(6, 8)}-${part(8, 10)}-${part(10, 16)}';
}

class RequestSubmissionSession {
  RequestSubmissionSession({RequestKeyFactory? keyFactory})
    : _keyFactory = keyFactory ?? newRequestUuid;
  final RequestKeyFactory _keyFactory;
  String? _key;
  RequestSubmissionState state = RequestSubmissionState.initial;

  String? get activeKey => _key;
  bool get isSubmitting => state == RequestSubmissionState.submitting;

  void formChanged() {
    if (isSubmitting) return;
    _key = null;
    state = RequestSubmissionState.editing;
  }

  String begin() {
    if (isSubmitting) return _key!;
    _key ??= _keyFactory();
    state = RequestSubmissionState.submitting;
    return _key!;
  }

  void failed(RequestSubmissionState failure) => state = failure;

  void succeeded() {
    state = RequestSubmissionState.success;
    _key = null;
  }
}

({RequestSubmissionState state, String message}) mapRequestError(
  ApiException error,
) {
  return switch (error.code) {
    'request_time_conflict' => (
      state: RequestSubmissionState.timeConflict,
      message: 'Bu saat kısa süre önce doldu. Lütfen başka bir zaman seçin.',
    ),
    'request_outside_service_area' => (
      state: RequestSubmissionState.outsideServiceArea,
      message: 'Seçtiğiniz adres işletmenin servis alanı dışında.',
    ),
    'request_business_unavailable' => (
      state: RequestSubmissionState.businessUnavailable,
      message: 'Bu işletme şu anda talep kabul edemiyor.',
    ),
    'request_forbidden' => (
      state: RequestSubmissionState.businessUnavailable,
      message: 'Kendi işletmenize talep gönderemezsiniz.',
    ),
    'request_service_unavailable' => (
      state: RequestSubmissionState.serviceUnavailable,
      message: 'Seçtiğiniz hizmet artık kullanılamıyor. Hizmetleri yenileyin.',
    ),
    'request_rate_limited' => (
      state: RequestSubmissionState.rateLimited,
      message: 'Çok sık talep gönderdiniz. Bir süre sonra tekrar deneyin.',
    ),
    'request_idempotency_conflict' => (
      state: RequestSubmissionState.validationError,
      message: 'Form değiştiği için gönderim yenilendi. Lütfen tekrar deneyin.',
    ),
    'request_outside_working_hours' => (
      state: RequestSubmissionState.validationError,
      message: 'Seçtiğiniz zaman işletmenin çalışma saatleri dışında.',
    ),
    'request_price_invalid' => (
      state: RequestSubmissionState.validationError,
      message: 'Teklif edilen fiyat ±%10 aralığında olmalıdır.',
    ),
    'request_invalid' => (
      state: RequestSubmissionState.validationError,
      message: 'Talep bilgilerini kontrol edip tekrar deneyin.',
    ),
    _ when error.statusCode == 400 => (
      state: RequestSubmissionState.validationError,
      message: 'Talep bilgilerini kontrol edip tekrar deneyin.',
    ),
    _ when error.statusCode == 403 => (
      state: RequestSubmissionState.businessUnavailable,
      message: 'Bu işlem için yetkiniz bulunmuyor.',
    ),
    _ when error.statusCode == 404 => (
      state: RequestSubmissionState.serviceUnavailable,
      message: 'Talep veya seçilen içerik artık bulunamıyor.',
    ),
    _ when error.statusCode == 409 => (
      state: RequestSubmissionState.timeConflict,
      message:
          'Talep güncellendi. Bilgiler yenilendikten sonra tekrar deneyin.',
    ),
    _ when error.statusCode == 429 => (
      state: RequestSubmissionState.rateLimited,
      message: 'Çok sık talep gönderdiniz. Bir süre sonra tekrar deneyin.',
    ),
    _ when (error.statusCode ?? 0) >= 500 => (
      state: RequestSubmissionState.networkError,
      message: 'Hizmet geçici olarak kullanılamıyor. Lütfen tekrar deneyin.',
    ),
    _
        when error.kind == ApiErrorKind.network ||
            error.kind == ApiErrorKind.timeout =>
      (
        state: RequestSubmissionState.networkError,
        message:
            'Bağlantı kurulamadı. Aynı talebi güvenle tekrar deneyebilirsiniz.',
      ),
    _ => (
      state: RequestSubmissionState.networkError,
      message: 'Talep gönderilemedi. Lütfen tekrar deneyin.',
    ),
  };
}

bool requestTimeInsideWorkingHours(
  DateTime requested,
  Iterable<BusinessWorkingDay> days, {
  Duration duration = Duration.zero,
}) {
  final now = DateTime.now();
  if (requested.isBefore(now) ||
      requested.isAfter(now.add(const Duration(days: 90)))) {
    return false;
  }
  final day = days
      .where((d) => d.day == requested.weekday && !d.closed)
      .firstOrNull;
  if (day == null) return false;
  final minutes = requested.hour * 60 + requested.minute;
  final end = requested.add(duration);
  if (end.year != requested.year ||
      end.month != requested.month ||
      end.day != requested.day) {
    return false;
  }
  final endMinutes = end.hour * 60 + end.minute;
  final open = day.openTimeOfDay.hour * 60 + day.openTimeOfDay.minute;
  final close = day.closeTimeOfDay.hour * 60 + day.closeTimeOfDay.minute;
  return minutes >= open && endMinutes <= close;
}
