import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tokenlar yalnızca cihazın güvenli deposunda tutulur (Keystore/Keychain).
class TokenStorage {
  TokenStorage._();
  static final TokenStorage instance = TokenStorage._();

  static const _storage = FlutterSecureStorage();

  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kSessionRole = 'session_role';

  String? _accessCache;

  Future<String?> get accessToken async =>
      _accessCache ??= await _storage.read(key: _kAccess);

  Future<String?> get refreshToken => _storage.read(key: _kRefresh);

  Future<String?> get sessionRole => _storage.read(key: _kSessionRole);

  Future<void> save({
    required String access,
    required String refresh,
    String? sessionRole,
  }) async {
    _accessCache = access;
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
    if (sessionRole != null) {
      await _storage.write(key: _kSessionRole, value: sessionRole);
    }
  }

  Future<void> clear() async {
    _accessCache = null;
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kSessionRole);
  }
}
