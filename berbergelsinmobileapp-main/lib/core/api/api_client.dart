import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import 'token_storage.dart';

/// Kullanıcıya gösterilebilir hata mesajı taşıyan istisna.
class ApiException implements Exception {
  ApiException(
    this.message, {
    this.statusCode,
    this.kind = ApiErrorKind.unknown,
    this.code,
  });
  final String message;
  final int? statusCode;
  final ApiErrorKind kind;
  final String? code;

  @override
  String toString() => message;
}

enum ApiErrorKind {
  network,
  timeout,
  unauthorized,
  forbidden,
  validation,
  server,
  invalidResponse,
  unknown,
}

enum SessionEndReason { expired, revoked, blocked }

enum RefreshResult { success, missingCredentials, rejected, transientFailure }

RefreshResult classifyRefreshStatus(int? statusCode) => switch (statusCode) {
  200 => RefreshResult.success,
  400 || 401 || 403 => RefreshResult.rejected,
  _ => RefreshResult.transientFailure,
};

bool canRetryAfterRefresh(RequestOptions options) {
  final method = options.method.toUpperCase();
  if (const {'GET', 'HEAD', 'OPTIONS'}.contains(method)) return true;
  return options.headers.keys.any(
    (key) => key.toLowerCase() == 'idempotency-key',
  );
}

class RefreshCoordinator {
  Completer<bool>? _active;

  Future<bool> run(Future<bool> Function() operation) {
    final current = _active;
    if (current != null) return current.future;
    final completer = _active = Completer<bool>();
    () async {
      try {
        completer.complete(await operation());
      } catch (_) {
        completer.complete(false);
      } finally {
        _active = null;
      }
    }();
    return completer.future;
  }
}

/// Dio istemcisi: Bearer ekler, 401'de tek uçuşlu refresh yapar ve isteği yineler.
class ApiClient {
  ApiClient._() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36'
        },
        validateStatus: (s) => s != null && s < 500,
      ),
    );

    // Otomatik retry: bağlantı hatalarında 1 kez tekrar dene
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) async {
          final retryable = error.type == DioExceptionType.connectionError ||
              error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.sendTimeout;
          if (retryable && error.requestOptions.extra['_retryCount'] == null) {
            error.requestOptions.extra['_retryCount'] = 1;
            await Future.delayed(const Duration(seconds: 1));
            try {
              final response = await _dio.fetch(error.requestOptions);
              return handler.resolve(response);
            } catch (_) {}
          }
          handler.next(error);
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          options.path = options.path.trim();
          final cleanUrl = '${options.baseUrl}${options.path}';
          
          if (kDebugMode) {
            debugPrint('GİDEN İSTEK URL: $cleanUrl');
          }
          final token = await TokenStorage.instance.accessToken;
          if (token != null && options.extra['noAuth'] != true) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onResponse: (response, handler) async {
          if (response.statusCode == 401 &&
              response.requestOptions.extra['retried'] != true &&
              response.requestOptions.extra['noAuth'] != true) {
            final refreshResult = await _refreshTokens();
            if (refreshResult == RefreshResult.success) {
              if (canRetryAfterRefresh(response.requestOptions)) {
                final opts = response.requestOptions;
                opts.extra['retried'] = true;
                final token = await TokenStorage.instance.accessToken;
                opts.headers['Authorization'] = 'Bearer $token';
                try {
                  final retryResponse = await _dio.fetch(opts);
                  return handler.resolve(retryResponse);
                } catch (retryError) {
                  if (kDebugMode) {
                    debugPrint(
                      'Token yenilendikten sonra istek tekrarı başarısız: $retryError',
                    );
                  }
                }
              }
            } else if (refreshResult == RefreshResult.rejected ||
                refreshResult == RefreshResult.missingCredentials) {
              if (!_sessionExpiryNotified) {
                _sessionExpiryNotified = true;
                final code = response.data is Map
                    ? response.data['code']
                    : null;
                onSessionExpired?.call(switch (code) {
                  'auth_session_revoked' ||
                  'auth_refresh_reused' => SessionEndReason.revoked,
                  'auth_account_inactive' ||
                  'auth_account_deleted' => SessionEndReason.blocked,
                  _ => SessionEndReason.expired,
                });
              }
            } else {
              return handler.reject(
                DioException(
                  requestOptions: response.requestOptions,
                  response: response,
                  type: DioExceptionType.connectionError,
                  error: 'refresh_transient_failure',
                ),
              );
            }
          }
          handler.next(response);
        },
      ),
    );
  }

  static final ApiClient instance = ApiClient._();

  late final Dio _dio;

  /// Refresh de başarısız olursa çağrılır — AuthBloc oturumu kapatır.
  void Function(SessionEndReason reason)? onSessionExpired;
  void Function()? onTokensRefreshed;

  Completer<RefreshResult>? _refreshCompleter;
  bool _sessionExpiryNotified = false;

  Future<RefreshResult> _refreshTokens() async {
    // Tek uçuş: eşzamanlı 401'ler tek refresh isteğini bekler
    if (_refreshCompleter != null) return _refreshCompleter!.future;
    final completer = _refreshCompleter = Completer<RefreshResult>();
    if (kDebugMode) {
      debugPrint('session_diag refresh_attempted=true');
    }
    try {
      final refresh = await TokenStorage.instance.refreshToken;
      if (refresh == null) {
        if (kDebugMode) {
          debugPrint('session_diag refresh_result=not_attempted');
        }
        completer.complete(RefreshResult.missingCredentials);
        return completer.future;
      }
      final sessionRole = await TokenStorage.instance.sessionRole;
      final response = await _dio.post(
        '/api/auth/refresh',
        data: {'refreshToken': refresh},
        options: Options(extra: {'noAuth': true}),
      );
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is! Map ||
            data['accessToken'] is! String ||
            data['refreshToken'] is! String) {
          completer.complete(RefreshResult.transientFailure);
          if (kDebugMode) {
            debugPrint('session_diag refresh_result=network_error');
          }
          return completer.future;
        }
        await TokenStorage.instance.save(
          access: data['accessToken'] as String,
          refresh: data['refreshToken'] as String,
          sessionRole: sessionRole,
        );
        _sessionExpiryNotified = false;
        onTokensRefreshed?.call();
        completer.complete(RefreshResult.success);
        if (kDebugMode) {
          debugPrint('session_diag refresh_result=success');
        }
      } else {
        final result = classifyRefreshStatus(response.statusCode);
        if (result == RefreshResult.rejected) {
          await TokenStorage.instance.clear();
        }
        completer.complete(result);
        if (kDebugMode) {
          debugPrint(
            'session_diag refresh_result=${result == RefreshResult.rejected ? 'unauthorized' : 'network_error'}',
          );
        }
      }
    } catch (_) {
      completer.complete(RefreshResult.transientFailure);
      if (kDebugMode) {
        debugPrint('session_diag refresh_result=network_error');
      }
    } finally {
      _refreshCompleter = null;
    }
    return completer.future;
  }

  /// Yanıtı doğrular; 2xx dışıysa sunucunun Türkçe mesajıyla ApiException fırlatır.
  T _unwrap<T>(Response response) {
    final code = response.statusCode ?? 0;
    if (code >= 200 && code < 300) return response.data as T;
    final serverMessage = response.data is Map
        ? response.data['message']
        : null;
    final serverCode = response.data is Map
        ? response.data['code'] as String?
        : null;
    final kind = switch (code) {
      401 => ApiErrorKind.unauthorized,
      403 => ApiErrorKind.forbidden,
      400 || 409 || 422 => ApiErrorKind.validation,
      >= 500 => ApiErrorKind.server,
      _ => ApiErrorKind.unknown,
    };
    final fallback = switch (kind) {
      ApiErrorKind.unauthorized =>
        'Oturumunuz sona erdi. Lütfen yeniden giriş yapın.',
      ApiErrorKind.forbidden => 'Bu işlem için yetkiniz bulunmuyor.',
      ApiErrorKind.validation => 'Bilgileri kontrol edip tekrar deneyin.',
      ApiErrorKind.server =>
        'Sunucuda bir sorun oluştu. Lütfen daha sonra tekrar deneyin.',
      _ => 'Bir hata oluştu. Lütfen tekrar deneyin.',
    };
    
    var finalMessage = serverMessage is String && serverMessage.trim().isNotEmpty
        ? serverMessage
        : fallback;
        
    if (serverCode == 'auth_role_mismatch') {
      finalMessage = 'Bu telefon numarası farklı bir hesap türüne (Müşteri/İşletme) aittir. Lütfen doğru rolü seçerek tekrar deneyin.';
    }

    throw ApiException(
      finalMessage,
      statusCode: code,
      kind: kind,
      code: serverCode,
    );
  }

  ApiException _fromDio(DioException error, {bool upload = false}) {
    if (kDebugMode) {
      debugPrint(
        'net_diag type=${error.type.name} '
        'url=${error.requestOptions.uri} '
        'err=${error.error} '
        'msg=${error.message}',
      );
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return ApiException(
        'İşlem zaman aşımına uğradı. Lütfen tekrar deneyin.',
        kind: ApiErrorKind.timeout,
      );
    }
    return ApiException(
      upload
          ? 'Dosya yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'
          : 'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.',
      kind: ApiErrorKind.network,
    );
  }

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    try {
      return _unwrap<T>(
        await _dio.get(path, queryParameters: query, cancelToken: cancelToken),
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw _fromDio(e);
    }
  }

  Future<T> post<T>(
    String path, {
    Object? data,
    bool noAuth = false,
    Map<String, String>? headers,
  }) async {
    try {
      return _unwrap<T>(
        await _dio.post(
          path,
          data: data,
          options: Options(extra: {'noAuth': noAuth}, headers: headers),
        ),
      );
    } on DioException catch (e) {
      throw _fromDio(e);
    }
  }

  Future<T> put<T>(String path, {Object? data}) async {
    try {
      return _unwrap<T>(await _dio.put(path, data: data));
    } on DioException catch (e) {
      throw _fromDio(e);
    }
  }

  Future<T> delete<T>(String path) async {
    try {
      return _unwrap<T>(await _dio.delete(path));
    } on DioException catch (e) {
      throw _fromDio(e);
    }
  }

  Future<T> postMultipart<T>(String path, FormData formData) async {
    try {
      return _unwrap<T>(await _dio.post(path, data: formData));
    } on DioException catch (e) {
      throw _fromDio(e, upload: true);
    }
  }

  Future<List<int>> getBytes(String path) async {
    try {
      final response = await _dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      if ((response.statusCode ?? 0) >= 300) {
        throw ApiException('Dosya alınamadı.', statusCode: response.statusCode);
      }
      final data = response.data;
      if (data == null) {
        throw ApiException('Dosya alınamadı.', statusCode: response.statusCode);
      }
      return data;
    } on DioException {
      throw ApiException('Dosya alınamadı.');
    }
  }
}
