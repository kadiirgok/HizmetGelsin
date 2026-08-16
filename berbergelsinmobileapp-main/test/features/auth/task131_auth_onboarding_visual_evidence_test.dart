import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:berbergelsin/core/theme/app_theme.dart';
import 'package:berbergelsin/features/auth/screens/otp_login_screen.dart';
import 'package:berbergelsin/features/auth/screens/google_phone_verification_screen.dart';
import 'package:berbergelsin/features/auth/screens/role_select_screen.dart';
import 'package:berbergelsin/features/auth/screens/splash_screen.dart';
import 'package:berbergelsin/features/auth/screens/account_blocked_screen.dart';
import 'package:berbergelsin/features/onboarding/screens/client_onboarding_screen.dart';
import 'package:berbergelsin/features/onboarding/screens/barber_onboarding_screen.dart';
import 'package:berbergelsin/features/onboarding/screens/pending_approval_screen.dart';
import 'package:berbergelsin/features/auth/bloc/auth_cubit.dart';
import 'package:berbergelsin/features/auth/services/google_auth_service.dart';
import 'package:berbergelsin/features/auth/widgets/auth_widgets.dart';

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
  Future<String?> getFreshIdToken() async => 'fake-id-token';

  @override
  Future<void> signOut() async {}
}

void main() {
  setUpAll(() async {
    HydratedBloc.storage = FakeStorage();

    // Load Roboto font
    final robotoPaths = [
      r'.flutter-sdk-fast\flutter\bin\cache\artifacts\material_fonts\Roboto-Regular.ttf',
      r'C:\tmp\flutter-sdk\bin\cache\artifacts\material_fonts\Roboto-Regular.ttf',
    ];
    for (final path in robotoPaths) {
      final fontFile = File(path);
      if (fontFile.existsSync()) {
        final bytes = await fontFile.readAsBytes();
        final fontData = ByteData.view(Uint8List.fromList(bytes).buffer);
        await (FontLoader('Roboto')..addFont(Future.value(fontData))).load();
        await (FontLoader('Ahem')..addFont(Future.value(fontData))).load();
        break;
      }
    }

    // Load MaterialIcons font
    final iconPaths = [
      r'.flutter-sdk-fast\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
      r'C:\tmp\flutter-sdk\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
    ];
    for (final path in iconPaths) {
      final iconFile = File(path);
      if (iconFile.existsSync()) {
        final bytes = await iconFile.readAsBytes();
        await (FontLoader('MaterialIcons')..addFont(
              Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
            )).load();
        break;
      }
    }
  });

  ThemeData getVisualTestTheme() {
    final base = AppTheme.light;
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
      filledButtonTheme: FilledButtonThemeData(
        style: base.filledButtonTheme.style?.copyWith(
          textStyle: WidgetStateProperty.all(
            (base.filledButtonTheme.style?.textStyle?.resolve({}) ?? AppTypography.labelLarge)
                .copyWith(fontFamily: 'Roboto'),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: base.outlinedButtonTheme.style?.copyWith(
          textStyle: WidgetStateProperty.all(
            (base.outlinedButtonTheme.style?.textStyle?.resolve({}) ?? AppTypography.labelLarge)
                .copyWith(fontFamily: 'Roboto'),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: base.textButtonTheme.style?.copyWith(
          textStyle: WidgetStateProperty.all(
            (base.textButtonTheme.style?.textStyle?.resolve({}) ?? AppTypography.labelLarge)
                .copyWith(fontFamily: 'Roboto'),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: base.elevatedButtonTheme.style?.copyWith(
          textStyle: WidgetStateProperty.all(
            (base.elevatedButtonTheme.style?.textStyle?.resolve({}) ?? AppTypography.labelLarge)
                .copyWith(fontFamily: 'Roboto'),
          ),
        ),
      ),
    );
  }

  Future<void> capture(
    WidgetTester tester,
    String filename,
    Widget body, {
    double width = 390,
    double height = 844,
    EdgeInsets viewInsets = EdgeInsets.zero,
    double textScale = 1.0,
  }) async {
    final key = GlobalKey();
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;

    final fakeAuth = FakeGoogleAuthService();
    final authCubit = AuthCubit(googleAuthService: fakeAuth);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          devicePixelRatio: 1.0,
          viewInsets: viewInsets,
          textScaler: TextScaler.linear(textScale),
        ),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: getVisualTestTheme(),
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: RepaintBoundary(
              key: key,
              child: Scaffold(
                body: body,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byKey(key), matchesGoldenFile('task131/$filename'));

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      authCubit.close();
    });
  }

  group('Task 131 Visual Evidence Screenshots', () {
    testWidgets('captures Auth & Onboarding UI screens in all required states and dimensions', (tester) async {
      // 390x844 Standard Viewport Screenshots
      await capture(tester, '390x844_otp_login_normal.png', const OtpLoginScreen());
      await capture(
        tester,
        '390x844_otp_login_keyboard.png',
        const OtpLoginScreen(),
        viewInsets: const EdgeInsets.only(bottom: 280),
      );
      await capture(
        tester,
        '390x844_otp_login_textscale2.png',
        const OtpLoginScreen(),
        textScale: 2.0,
      );

      await capture(tester, '390x844_google_phone_verification.png', const GooglePhoneVerificationScreen());
      await capture(tester, '390x844_role_select.png', const RoleSelectScreen());
      await capture(tester, '390x844_client_onboarding.png', const ClientOnboardingScreen());
      await capture(tester, '390x844_barber_onboarding_step1.png', const BarberOnboardingScreen(initialStep: 0));
      await capture(tester, '390x844_barber_onboarding_step2.png', const BarberOnboardingScreen(initialStep: 1));
      await capture(tester, '390x844_barber_onboarding_step3.png', const BarberOnboardingScreen(initialStep: 2));
      await capture(tester, '390x844_pending_approval.png', const PendingApprovalScreen());
      await capture(tester, '390x844_account_blocked.png', const AccountBlockedScreen());
      await capture(tester, '390x844_splash.png', const SplashScreen());

      // 320x568 Small Viewport Screenshots
      await capture(tester, '320x568_otp_login.png', const OtpLoginScreen(), width: 320, height: 568);
      await capture(tester, '320x568_role_select.png', const RoleSelectScreen(), width: 320, height: 568);
      await capture(tester, '320x568_barber_onboarding_step1.png', const BarberOnboardingScreen(initialStep: 0), width: 320, height: 568);
      await capture(tester, '320x568_client_onboarding.png', const ClientOnboardingScreen(), width: 320, height: 568);

      // 360x800 Android Standard Viewport Screenshots
      await capture(tester, '360x800_otp_login.png', const OtpLoginScreen(), width: 360, height: 800);
      await capture(tester, '360x800_google_phone_verification.png', const GooglePhoneVerificationScreen(), width: 360, height: 800);
      await capture(tester, '360x800_barber_onboarding_step2.png', const BarberOnboardingScreen(initialStep: 1), width: 360, height: 800);
    });
  });

  group('Task 131 Font & Text Resolution', () {
    testWidgets('verifies LoadingPrimaryButton Kod gönder TextStyle/fontFamily resolution', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: getVisualTestTheme(),
          home: Scaffold(
            body: LoadingPrimaryButton(
              label: 'Kod gönder',
              loading: false,
              onPressed: () {},
            ),
          ),
        ),
      );
      final finder = find.text('Kod gönder');
      expect(finder, findsOneWidget);
      final textElement = tester.element(finder);
      final defaultTextStyle = DefaultTextStyle.of(textElement);
      final textWidget = tester.widget<Text>(finder);
      final effectiveStyle = defaultTextStyle.style.merge(textWidget.style);
      expect(effectiveStyle.fontFamily, equals('Roboto'));
    });

    testWidgets('verifies presence of essential button text widgets in the tree', (tester) async {
      final fakeAuth = FakeGoogleAuthService();
      final authCubit = AuthCubit(googleAuthService: fakeAuth);

      // Verify 'Kod gönder'
      await tester.pumpWidget(
        MaterialApp(
          theme: getVisualTestTheme(),
          home: Scaffold(
            body: LoadingPrimaryButton(
              label: 'Kod gönder',
              loading: false,
              onPressed: () {},
            ),
          ),
        ),
      );
      expect(find.text('Kod gönder'), findsOneWidget);

      // Verify 'Google ile devam et'
      await tester.pumpWidget(
        MaterialApp(
          theme: getVisualTestTheme(),
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const OtpLoginScreen(),
          ),
        ),
      );
      expect(find.text('Google ile devam et'), findsOneWidget);

      // Verify 'Hizmet almak istiyorum'
      await tester.pumpWidget(
        MaterialApp(
          theme: getVisualTestTheme(),
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const RoleSelectScreen(),
          ),
        ),
      );
      expect(find.text('Hizmet almak istiyorum'), findsOneWidget);
      expect(find.text('Hizmet vermek istiyorum'), findsOneWidget);

      // Verify 'Çıkış yap'
      await tester.pumpWidget(
        MaterialApp(
          theme: getVisualTestTheme(),
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const PendingApprovalScreen(),
          ),
        ),
      );
      expect(find.text('Çıkış yap'), findsOneWidget);

      authCubit.close();
    });
  });
}
