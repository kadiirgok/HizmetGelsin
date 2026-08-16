import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/token_storage.dart';
import '../../../core/signalr/signalr_service.dart';
import '../../../core/session/account_state_cleaner.dart';
import '../models/app_user.dart';
import '../services/google_auth_service.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

class LoginResponse {
  final bool phoneVerificationRequired;
  final String? error;

  const LoginResponse({
    this.phoneVerificationRequired = false,
    this.error,
  });
}

typedef GoogleLoginResponse = LoginResponse;

enum SessionStatus {
  unknown,
  authenticatedCustomer,
  authenticatedBusiness,
  authenticatedAdmin,
  expired,
  revoked,
  blocked,
  loggedOut,
}

class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.selectedRole = 'Musteri',
    this.sessionStatus = SessionStatus.unknown,
  });

  final AuthStatus status;
  final AppUser? user;

  /// Rol seçim ekranında seçilen niyet ("Musteri" | "Berber"/işletme)
  final String selectedRole;
  final SessionStatus sessionStatus;

  AuthState copyWith({
    AuthStatus? status,
    AppUser? user,
    String? selectedRole,
    bool clearUser = false,
    SessionStatus? sessionStatus,
  }) => AuthState(
    status: status ?? this.status,
    user: clearUser ? null : (user ?? this.user),
    selectedRole: selectedRole ?? this.selectedRole,
    sessionStatus: sessionStatus ?? this.sessionStatus,
  );

  @override
  List<Object?> get props => [status, user, selectedRole, sessionStatus];
}

class AuthCubit extends HydratedCubit<AuthState> {
  final IGoogleAuthService _googleAuthService;

  AuthCubit({IGoogleAuthService? googleAuthService})
      : _googleAuthService = googleAuthService ?? GoogleAuthService.instance,
        super(const AuthState()) {
    ApiClient.instance.onSessionExpired = _expireSession;
    ApiClient.instance.onTokensRefreshed = () async {
      await SignalRService.instance.disconnect();
      await SignalRService.instance.connect();
    };
  }

  Future<void> Function()? beforeLogout;

  /// Açılışta: kalıcı state'te kullanıcı varsa /me ile tazele,
  /// yoksa (veya oturum düşmüşse) girişe yönlendir.
  Future<void> bootstrap() async {
    String? refresh;
    try {
      final access = await TokenStorage.instance.accessToken;
      refresh = await TokenStorage.instance.refreshToken;
      final role = await TokenStorage.instance.sessionRole;
      if (kDebugMode) {
        debugPrint(
          'session_diag secure_storage_accessible=true '
          'access_token_present=${access != null} '
          'refresh_token_present=${refresh != null} '
          'session_metadata_present=${state.user != null || role != null} '
          'legacy_keys_detected=false',
        );
      }
    } catch (_) {
      if (kDebugMode) {
        debugPrint(
          'session_diag secure_storage_accessible=false '
          'session_restore_result=storage_error',
        );
      }
      if (state.user != null) {
        emit(state.copyWith(status: AuthStatus.authenticated));
      }
      return;
    }
    if (refresh == null) {
      AccountStateCleaner.endCustomerSession();
      if (kDebugMode) {
        debugPrint(
          'session_diag refresh_attempted=false '
          'session_restore_result=missing_credentials',
        );
      }
      emit(
        state.copyWith(
          status: AuthStatus.unauthenticated,
          clearUser: true,
          sessionStatus: SessionStatus.loggedOut,
        ),
      );
      return;
    }
    try {
      final data = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/auth/me',
      );
      await _setAuthenticated(AppUser.fromJson(data));
      if (kDebugMode) {
        debugPrint('session_diag session_restore_result=authenticated');
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        AccountStateCleaner.endCustomerSession();
        await TokenStorage.instance.clear();
        emit(
          state.copyWith(
            status: AuthStatus.unauthenticated,
            clearUser: true,
            sessionStatus: SessionStatus.expired,
          ),
        );
        if (kDebugMode) {
          debugPrint('session_diag session_restore_result=expired');
        }
      } else if (state.user != null) {
        // Ağ hatası: elde kalıcı kullanıcı varsa çevrimdışı devam et
        AccountStateCleaner.bindCustomerSession(
          state.user!.isMusteri ? state.user!.id : null,
        );
        emit(state.copyWith(status: AuthStatus.authenticated));
        await SignalRService.instance.connect();
        if (kDebugMode) {
          debugPrint('session_diag session_restore_result=authenticated');
        }
      } else {
        AccountStateCleaner.endCustomerSession();
        emit(
          state.copyWith(
            status: AuthStatus.unauthenticated,
            sessionStatus: SessionStatus.loggedOut,
          ),
        );
        if (kDebugMode) {
          debugPrint('session_diag session_restore_result=missing_credentials');
        }
      }
    }
  }

  void selectRole(String role) => emit(state.copyWith(selectedRole: role));



  Future<GoogleLoginResponse> loginWithGoogle([String? providedToken]) async {
    try {
      final token = providedToken ?? await _googleAuthService.getFreshIdToken();
      if (token == null || token.isEmpty) {
        await _googleAuthService.signOut();
        return const GoogleLoginResponse(error: 'Google kimlik bilgisi alınamadı.');
      }

      final data = await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/auth/google',
        data: {'firebaseIdToken': token, 'role': state.selectedRole},
        noAuth: true,
      );
      await TokenStorage.instance.save(
        access: data['accessToken'] as String,
        refresh: data['refreshToken'] as String,
        sessionRole: state.selectedRole,
      );
      await _setAuthenticated(
        AppUser.fromJson(data['user'] as Map<String, dynamic>),
      );
      return const GoogleLoginResponse();
    } on ApiException catch (e) {
      if (e.statusCode == 409 && e.code == 'auth_google_phone_verification_required') {
        return const GoogleLoginResponse(
          phoneVerificationRequired: true,
        );
      }
      await _googleAuthService.signOut();
      return GoogleLoginResponse(error: e.message);
    } catch (e) {
      await _googleAuthService.signOut();
      return const GoogleLoginResponse(error: 'Giriş işlemi başarısız oldu.');
    }
  }

  Future<void> loginWithPhone(String firebaseIdToken, String phoneNumber) async {
    final data = await ApiClient.instance.post<Map<String, dynamic>>(
      '/api/auth/phone',
      data: {
        'firebaseIdToken': firebaseIdToken,
        'role': state.selectedRole,
      },
      noAuth: true,
    );
    await TokenStorage.instance.save(
      access: data['accessToken'] as String,
      refresh: data['refreshToken'] as String,
      sessionRole: state.selectedRole,
    );
    await _setAuthenticated(
      AppUser.fromJson(data['user'] as Map<String, dynamic>),
    );
  }

  /// Telefon numarasına SMS OTP gönderir (NacSMS).
  Future<void> sendPhoneOtp(String phone) async {
    await ApiClient.instance.post(
      '/api/auth/phone/send',
      data: {'phone': phone, 'role': state.selectedRole},
      noAuth: true,
    );
  }

  /// Telefon OTP kodunu doğrular ve giriş yapar (NacSMS).
  Future<LoginResponse> verifyPhoneOtp(String phone, String code) async {
    try {
      final data = await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/auth/phone/verify',
        data: { 'phone': phone, 'code': code, 'role': state.selectedRole },
        noAuth: true,
      );
      await TokenStorage.instance.save(
        access: data['accessToken'] as String,
        refresh: data['refreshToken'] as String,
        sessionRole: state.selectedRole,
      );
      await _setAuthenticated(
        AppUser.fromJson(data['user'] as Map<String, dynamic>),
      );
      return const LoginResponse();
    } on ApiException catch (e) {
      return LoginResponse(error: e.message);
    } catch (e) {
      return const LoginResponse(error: 'Doğrulama işlemi başarısız oldu.');
    }
  }

  Future<void> sendEmailOtp(String email) async {
    await ApiClient.instance.post(
      '/api/auth/email/send',
      data: {'email': email, 'role': state.selectedRole},
      noAuth: true,
    );
  }

  Future<LoginResponse> verifyEmailOtp(String email, String code, [String? phone]) async {
    try {
      final data = await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/auth/email/verify',
        data: {
          'email': email,
          'code': code,
          if (phone != null) 'phone': phone,
          'role': state.selectedRole
        },
        noAuth: true,
      );
      await TokenStorage.instance.save(
        access: data['accessToken'] as String,
        refresh: data['refreshToken'] as String,
        sessionRole: state.selectedRole,
      );
      await _setAuthenticated(
        AppUser.fromJson(data['user'] as Map<String, dynamic>),
      );
      return const LoginResponse();
    } on ApiException catch (e) {
      if (e.statusCode == 409 && e.code == 'auth_phone_verification_required') {
        return const LoginResponse(phoneVerificationRequired: true);
      }
      return LoginResponse(error: e.message);
    } catch (e) {
      return const LoginResponse(error: 'Doğrulama işlemi başarısız oldu.');
    }
  }

  /// Email + telefon + şifre + rol ile kayıt.
  Future<LoginResponse> register({
    required String email,
    required String phone,
    required String password,
    required String role,
  }) async {
    try {
      final data = await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/auth/register',
        data: {
          'email': email,
          'phone': phone,
          'password': password,
          'role': role,
        },
        noAuth: true,
      );
      await TokenStorage.instance.save(
        access: data['accessToken'] as String,
        refresh: data['refreshToken'] as String,
        sessionRole: role,
      );
      await _setAuthenticated(
        AppUser.fromJson(data['user'] as Map<String, dynamic>),
      );
      return const LoginResponse();
    } on ApiException catch (e) {
      return LoginResponse(error: e.message);
    } catch (e) {
      return const LoginResponse(error: 'Kayıt işlemi başarısız oldu.');
    }
  }

  /// Email veya telefon + şifre ile giriş.
  Future<LoginResponse> login({
    required String credential,
    required String password,
  }) async {
    try {
      final data = await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/auth/login',
        data: {
          'credential': credential,
          'password': password,
          'role': state.selectedRole,
        },
        noAuth: true,
      );
      await TokenStorage.instance.save(
        access: data['accessToken'] as String,
        refresh: data['refreshToken'] as String,
        sessionRole: state.selectedRole,
      );
      await _setAuthenticated(
        AppUser.fromJson(data['user'] as Map<String, dynamic>),
      );
      return const LoginResponse();
    } on ApiException catch (e) {
      return LoginResponse(error: e.message);
    } catch (e) {
      return const LoginResponse(error: 'Giriş işlemi başarısız oldu.');
    }
  }

  /// Şifre sıfırlama kodu gönder.
  Future<void> sendForgotPassword(String credential) async {
    await ApiClient.instance.post(
      '/api/auth/forgot-password',
      data: {'credential': credential, 'role': state.selectedRole},
      noAuth: true,
    );
  }

  /// Şifre sıfırlama.
  Future<void> resetPassword(String credential, String code, String newPassword) async {
    await ApiClient.instance.post(
      '/api/auth/reset-password',
      data: {
        'credential': credential,
        'code': code,
        'newPassword': newPassword,
        'role': state.selectedRole,
      },
      noAuth: true,
    );
  }

  /// Email doğrulama kodu gönder (ayarlardan).
  Future<void> sendEmailVerification() async {
    await ApiClient.instance.post(
      '/api/auth/verify/email/send',
      data: {},
    );
  }

  /// Email doğrulama kodunu onayla.
  Future<String?> verifyEmail(String code) async {
    try {
      final data = await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/auth/verify/email',
        data: {'code': code},
      );
      final user = AppUser.fromJson(data as Map<String, dynamic>);
      emit(state.copyWith(user: user));
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Doğrulama başarısız oldu.';
    }
  }

  /// Telefon doğrulama kodu gönder (ayarlardan).
  Future<void> sendPhoneVerification() async {
    await ApiClient.instance.post(
      '/api/auth/verify/phone/send',
      data: {},
    );
  }

  /// Telefon doğrulama kodunu onayla (NacSMS).
  Future<String?> verifyPhoneFromSettings(String code) async {
    try {
      final data = await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/auth/verify/phone',
        data: {'code': code},
      );
      final user = AppUser.fromJson(data as Map<String, dynamic>);
      emit(state.copyWith(user: user));
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Doğrulama başarısız oldu.';
    }
  }

  /// Firebase Phone Auth ile telefon doğrulama (ayarlardan).
  /// Firebase tarafında SMS gönderilip kod doğrulandıktan sonra
  /// elde edilen [firebaseIdToken] ile backend'i çağırır.
  Future<String?> verifyPhoneWithFirebase(String firebaseIdToken) async {
    try {
      final data = await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/auth/verify/phone/firebase',
        data: {'firebaseIdToken': firebaseIdToken},
      );
      final user = AppUser.fromJson(data as Map<String, dynamic>);
      emit(state.copyWith(user: user));
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Telefon doğrulaması başarısız oldu.';
    }
  }

  Future<void> saveGooglePhone({
    required String phone,
  }) async {
    final token = await _googleAuthService.getFreshIdToken();
    if (token == null || token.isEmpty) {
      throw ApiException('Google kimlik oturumu süresi doldu.', statusCode: 401, code: 'auth_google_invalid_token');
    }
    final data = await ApiClient.instance.post<Map<String, dynamic>>(
      '/api/auth/google/phone/save',
      data: {
        'firebaseIdToken': token,
        'phone': phone,
        'role': state.selectedRole,
      },
      noAuth: true,
    );
    final access = data['accessToken'];
    final refresh = data['refreshToken'];
    final userJson = data['user'];
    if (access is! String || refresh is! String || userJson is! Map<String, dynamic>) {
      throw ApiException('Geçersiz sunucu yanıtı.', statusCode: 500);
    }
    await TokenStorage.instance.save(
      access: access,
      refresh: refresh,
      sessionRole: state.selectedRole,
    );
    await _setAuthenticated(AppUser.fromJson(userJson));
  }

  /// Onboarding/onay sonrası kullanıcı bilgisini sunucudan tazeler.
  Future<void> refreshUser() async {
    try {
      final data = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/auth/me',
      );
      emit(
        state.copyWith(
          status: AuthStatus.authenticated,
          user: AppUser.fromJson(data),
        ),
      );
    } on ApiException {
      // sessiz geç
    }
  }

  /// SignalR gibi kaynaklardan gelen işletme durum değişikliğini uygular.
  void applyBarberStatus(String status, String? rejectionReason) {
    final user = state.user;
    if (user == null) return;
    emit(
      state.copyWith(
        user: AppUser(
          id: user.id,
          phone: user.phone,
          role: user.role,
          firstName: user.firstName,
          lastName: user.lastName,
          email: user.email,
          onboardingCompleted: user.onboardingCompleted,
          barberStatus: status,
          rejectionReason: rejectionReason,
          avgRating: user.avgRating,
          ratingCount: user.ratingCount,
          emailVerified: user.emailVerified,
          isPhoneVerified: user.isPhoneVerified,
        ),
      ),
    );
  }

  Future<void> _setAuthenticated(AppUser user) async {
    AccountStateCleaner.bindCustomerSession(user.isMusteri ? user.id : null);
    emit(
      state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        sessionStatus: user.isAdmin
            ? SessionStatus.authenticatedAdmin
            : user.isMusteri
            ? SessionStatus.authenticatedCustomer
            : SessionStatus.authenticatedBusiness,
      ),
    );
    await SignalRService.instance.connect();
  }

  /// Hesap silme isteği gönder (soft delete).
  Future<void> deleteAccount() async {
    await ApiClient.instance.delete('/api/auth/account');
    await logout();
  }

  /// Bildirim tercihlerini getir.
  Future<Map<String, bool>> getNotificationPreferences() async {
    final data = await ApiClient.instance.get<Map<String, dynamic>>(
      '/api/auth/notification-preferences',
    );
    return data.map((k, v) => MapEntry(k, v as bool));
  }

  /// Bildirim tercihlerini kaydet.
  Future<void> updateNotificationPreferences(Map<String, bool> prefs) async {
    await ApiClient.instance.put(
      '/api/auth/notification-preferences',
      data: prefs,
    );
  }

  Future<void> logout() async {
    AccountStateCleaner.endCustomerSession();

    // Network-side cleanup — each call is time-boxed so a stalled
    // connection on an emulator (BlueStacks, etc.) never blocks
    // the local logout and the user always reaches the login screen.
    try {
      await (beforeLogout?.call() ?? Future.value())
          .timeout(const Duration(seconds: 5));
    } catch (_) {}

    final refresh = await TokenStorage.instance.refreshToken;
    if (refresh != null) {
      try {
        await ApiClient.instance
            .post('/api/auth/logout', data: {'refreshToken': refresh})
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
    }

    try {
      await FirebaseAuth.instance
          .signOut()
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      await GoogleSignIn.instance
          .signOut()
          .timeout(const Duration(seconds: 5));
    } catch (_) {}

    try {
      await SignalRService.instance
          .disconnect()
          .timeout(const Duration(seconds: 5));
    } catch (_) {}

    // Local cleanup — MUST always execute regardless of network state
    await TokenStorage.instance.clear();
    AccountStateCleaner.clear();
    emit(
      state.copyWith(
        status: AuthStatus.unauthenticated,
        clearUser: true,
        sessionStatus: SessionStatus.loggedOut,
      ),
    );
  }

  Future<void> _expireSession(SessionEndReason reason) async {
    AccountStateCleaner.endCustomerSession();
    await beforeLogout?.call();
    await SignalRService.instance.disconnect();
    await TokenStorage.instance.clear();
    AccountStateCleaner.clear();
    emit(
      state.copyWith(
        status: AuthStatus.unauthenticated,
        clearUser: true,
        sessionStatus: switch (reason) {
          SessionEndReason.expired => SessionStatus.expired,
          SessionEndReason.revoked => SessionStatus.revoked,
          SessionEndReason.blocked => SessionStatus.blocked,
        },
      ),
    );
  }

  @override
  AuthState? fromJson(Map<String, dynamic> json) {
    try {
      return AuthState(
        status: AuthStatus.unknown, // gerçek durum bootstrap ile belirlenir
        user: json['user'] == null
            ? null
            : AppUser.fromJson(json['user'] as Map<String, dynamic>),
        selectedRole: json['selectedRole'] as String? ?? 'Musteri',
        sessionStatus: SessionStatus.unknown,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Map<String, dynamic>? toJson(AuthState state) => {
    'user': state.user?.toJson(),
    'selectedRole': state.selectedRole,
  };
}
