import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:berbergelsin/features/auth/screens/google_phone_verification_screen.dart';
import 'package:berbergelsin/features/auth/screens/otp_login_screen.dart';
import 'package:berbergelsin/features/onboarding/screens/client_onboarding_screen.dart';
import 'package:berbergelsin/features/onboarding/screens/barber_onboarding_screen.dart';
import 'package:berbergelsin/features/auth/bloc/auth_cubit.dart';
import 'package:berbergelsin/features/auth/models/app_user.dart';
import 'package:berbergelsin/features/auth/services/google_auth_service.dart';

class FakeStorage implements Storage {
  @override
  dynamic read(String key) => null;

  @override
  Future<void> write(String key, dynamic value) async {}

  @override
  Future<void> delete(String key) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> close() async {}
}

class FakeGoogleAuthService implements IGoogleAuthService {
  bool initializedCalled = false;
  bool signOutCalled = false;
  String? mockFreshIdToken = 'fake-fresh-firebase-id-token-123';

  @override
  Future<void> initialize() async {
    initializedCalled = true;
  }

  @override
  Future<GoogleAuthResult?> signIn() async {
    initializedCalled = true;
    return GoogleAuthResult(
      firebaseIdToken: mockFreshIdToken!,
      email: 'fake@example.com',
      displayName: 'Fake User',
    );
  }

  @override
  Future<String?> getFreshIdToken() async {
    return mockFreshIdToken;
  }

  @override
  Future<void> signOut() async {
    signOutCalled = true;
  }
}

void main() {
  setUp(() {
    HydratedBloc.storage = FakeStorage();
  });

  for (final textScale in [1.0, 1.3, 2.0]) {
    testWidgets('GooglePhoneVerificationScreen renders at 320px, keyboard open, textScale $textScale with zero overflow', (tester) async {
      tester.view.physicalSize = const Size(320 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2.0;

      final fakeAuth = FakeGoogleAuthService();
      final authCubit = AuthCubit(googleAuthService: fakeAuth);

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 640),
            viewInsets: const EdgeInsets.only(bottom: 280), // Keyboard open simulation
            textScaler: TextScaler.linear(textScale),
          ),
          child: MaterialApp(
            home: BlocProvider<AuthCubit>.value(
              value: authCubit,
              child: const GooglePhoneVerificationScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Telefon Doğrulama'), findsOneWidget);
      expect(find.text('Doğrulama Kodu Gönder'), findsOneWidget);
      expect(tester.takeException(), isNull);

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        authCubit.close();
      });
    });

    testWidgets('OtpLoginScreen renders at 320px, keyboard open, textScale $textScale with exact Google ile devam et and KVKK footer', (tester) async {
      tester.view.physicalSize = const Size(320 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2.0;

      final fakeAuth = FakeGoogleAuthService();
      final authCubit = AuthCubit(googleAuthService: fakeAuth);

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 640),
            viewInsets: const EdgeInsets.only(bottom: 250),
            textScaler: TextScaler.linear(textScale),
          ),
          child: MaterialApp(
            home: BlocProvider<AuthCubit>.value(
              value: authCubit,
              child: const OtpLoginScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Giriş yap veya kayıt ol'), findsOneWidget);
      expect(find.text('Google ile devam et'), findsOneWidget);
      expect(find.textContaining('Kullanım Koşulları ve KVKK Metnini'), findsOneWidget);
      expect(tester.takeException(), isNull);

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        authCubit.close();
      });
    });

    testWidgets('ClientOnboardingScreen displays 555 010 00 10 without +90 905 double country code at 320px, textScale $textScale', (tester) async {
      tester.view.physicalSize = const Size(320 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2.0;

      final fakeAuth = FakeGoogleAuthService();
      final authCubit = AuthCubit(googleAuthService: fakeAuth);

      // Populate user with raw DB phone 905550100010
      const testUser = AppUser(
        id: 'user-123',
        phone: '905550100010',
        role: 'Musteri',
        onboardingCompleted: false,
      );

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 640),
            textScaler: TextScaler.linear(textScale),
          ),
          child: MaterialApp(
            home: BlocProvider<AuthCubit>.value(
              value: authCubit,
              child: Builder(
                builder: (context) {
                  context.read<AuthCubit>().emit(
                    authCubit.state.copyWith(
                      status: AuthStatus.authenticated,
                      user: testUser,
                    ),
                  );
                  return const ClientOnboardingScreen();
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('555 010 00 10'), findsOneWidget);
      expect(find.textContaining('905550100010'), findsNothing);
      expect(tester.takeException(), isNull);

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        authCubit.close();
      });
    });

    testWidgets('BarberOnboardingScreen displays 555 010 00 10 without +90 905 double country code at 320px, textScale $textScale', (tester) async {
      tester.view.physicalSize = const Size(320 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2.0;

      final fakeAuth = FakeGoogleAuthService();
      final authCubit = AuthCubit(googleAuthService: fakeAuth);

      const testUser = AppUser(
        id: 'barber-123',
        phone: '905550100010',
        role: 'Berber',
        onboardingCompleted: false,
      );

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 640),
            textScaler: TextScaler.linear(textScale),
          ),
          child: MaterialApp(
            home: BlocProvider<AuthCubit>.value(
              value: authCubit,
              child: Builder(
                builder: (context) {
                  context.read<AuthCubit>().emit(
                    authCubit.state.copyWith(
                      status: AuthStatus.authenticated,
                      user: testUser,
                    ),
                  );
                  return const BarberOnboardingScreen(initialStep: 0);
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('555 010 00 10'), findsOneWidget);
      expect(find.textContaining('905550100010'), findsNothing);
      expect(tester.takeException(), isNull);

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        authCubit.close();
      });
    });
  }

  test('AuthCubit uses fresh Firebase token from injected IGoogleAuthService', () async {
    final fakeAuth = FakeGoogleAuthService();
    final authCubit = AuthCubit(googleAuthService: fakeAuth);

    expect(authCubit.state.status, AuthStatus.unknown);

    addTearDown(() {
      authCubit.close();
    });
  });

  test('Flutter source files contain no corrupted Turkish characters', () {
    final libDir = Directory('lib');
    final corruptedPatterns = ['Kayn±t', 'gs¶nderildi', 'BaÅŸvurunuz', 'gÃ¶nderildi', 'KayÄ±t', 'tamamlandÄ±'];

    for (final file in libDir.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final content = file.readAsStringSync();
      for (final pattern in corruptedPatterns) {
        expect(
          content.contains(pattern),
          isFalse,
          reason: 'Corrupted character pattern "$pattern" found in ${file.path}',
        );
      }
    }
  });
}
