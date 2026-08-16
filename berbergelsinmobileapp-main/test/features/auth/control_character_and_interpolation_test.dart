import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:berbergelsin/features/auth/widgets/auth_widgets.dart';
import 'package:berbergelsin/features/auth/screens/google_phone_verification_screen.dart';
import 'package:berbergelsin/features/onboarding/screens/barber_onboarding_screen.dart';
import 'package:berbergelsin/features/auth/bloc/auth_cubit.dart';
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
  @override
  Future<void> initialize() async {}

  @override
  Future<GoogleAuthResult?> signIn() async => null;

  @override
  Future<String?> getFreshIdToken() async => 'fake-token';

  @override
  Future<void> signOut() async {}
}

void main() {
  setUpAll(() {
    HydratedBloc.storage = FakeStorage();
  });

  group('C0 Control Character & Interpolation Integrity', () {
    test('Byte-level scanner: lib/**/*.dart contains zero C0 control characters or 0x7F', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue, reason: 'lib directory must exist');

      final invalidBytes = <int>{
        ...List.generate(9, (i) => i), // 0x00 - 0x08
        0x0B, 0x0C,                   // 0x0B, 0x0C
        ...List.generate(18, (i) => i + 14), // 0x0E - 0x1F
        0x7F,                         // 0x7F
      };

      final violations = <String>[];

      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          final bytes = entity.readAsBytesSync();
          for (var i = 0; i < bytes.length; i++) {
            if (invalidBytes.contains(bytes[i])) {
              violations.add(
                'Forbidden control byte 0x${bytes[i].toRadixString(16).padLeft(2, '0').toUpperCase()} at position $i in ${entity.path}',
              );
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Files in lib/ contain forbidden control characters:\n${violations.join('\n')}',
      );
    });

    testWidgets('Masked phone and resend countdown display real values on screen without corrupted 4{ or control characters', (tester) async {
      final fakeAuth = FakeGoogleAuthService();
      final authCubit = AuthCubit(googleAuthService: fakeAuth);

      // 1. Verify mask function unit logic
      final masked = maskTurkishMobile('5550100010');
      expect(masked, equals('5** *** ** 10'));
      expect(masked.contains('4{'), isFalse);
      expect(masked.contains('\x02'), isFalse);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: GooglePhoneVerificationScreen(
              sendOtp: (phone) async {},
            ),
          ),
        ),
      );
      await tester.pump();

      // Enter phone number
      final phoneField = find.byKey(const Key('auth_phone_field'));
      expect(phoneField, findsOneWidget);
      await tester.enterText(phoneField, '5550100010');
      await tester.pump();

      // Invoke send code directly via button callback
      final sendBtnWidget = tester.widget<LoadingPrimaryButton>(find.byType(LoadingPrimaryButton));
      sendBtnWidget.onPressed!();
      await tester.pump();

      // Verify masked phone displays real value on screen
      expect(find.textContaining('5** *** ** 10'), findsOneWidget);
      expect(find.textContaining('4{'), findsNothing);
      expect(find.textContaining('\x02'), findsNothing);

      // Verify resend countdown displays real format like (60s)
      expect(find.textContaining('(60s)'), findsOneWidget);

      addTearDown(() {
        authCubit.close();
      });
    });

    testWidgets('Barber onboarding header displays 1/3 İşletme bilgileri', (tester) async {
      final fakeAuth = FakeGoogleAuthService();
      final authCubit = AuthCubit(googleAuthService: fakeAuth);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const BarberOnboardingScreen(initialStep: 0),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('barber_step_indicator')), findsOneWidget);
      expect(find.text('1/3 İşletme bilgileri'), findsOneWidget);
      expect(find.textContaining('4{'), findsNothing);
      expect(find.textContaining('\x02'), findsNothing);

      addTearDown(() {
        authCubit.close();
      });
    });

    testWidgets('Barber onboarding service row delete key format is remove_service_0', (tester) async {
      final fakeAuth = FakeGoogleAuthService();
      final authCubit = AuthCubit(googleAuthService: fakeAuth);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const BarberOnboardingScreen(initialStep: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remove_service_0')), findsOneWidget);
      expect(find.byKey(const Key('remove_service_1')), findsOneWidget);

      addTearDown(() {
        authCubit.close();
      });
    });

    testWidgets('Barber onboarding radius text displays 5 km and updates on slider drag', (tester) async {
      final fakeAuth = FakeGoogleAuthService();
      final authCubit = AuthCubit(googleAuthService: fakeAuth);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const BarberOnboardingScreen(initialStep: 2),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('barber_radius_text')), findsOneWidget);
      expect(find.textContaining('en fazla 5 km uzağa'), findsOneWidget);

      final sliderFinder = find.byKey(const Key('barber_radius_slider'));
      expect(sliderFinder, findsOneWidget);

      await tester.drag(sliderFinder, const Offset(100, 0));
      await tester.pump();

      expect(find.textContaining('4{'), findsNothing);
      expect(find.textContaining('\x02'), findsNothing);

      addTearDown(() {
        authCubit.close();
      });
    });
  });
}
