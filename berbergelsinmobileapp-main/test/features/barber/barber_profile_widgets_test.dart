import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:berbergelsin/features/barber/screens/barber_profile_screen.dart';

void main() {
  group('Barber Profile Responsive Widget Tests', () {
    testWidgets('320 px profile overview grid no overflow', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320 * 3, 480 * 3);
      tester.view.devicePixelRatio = 3.0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: ProfileOverviewGrid(
                score: 85,
                serviceCount: 5,
                photoCount: 3,
                radiusKm: 10,
              ),
            ),
          ),
        ),
      );

      expect(find.text('%85'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('10 km'), findsOneWidget);
    });

    testWidgets('320 px quick actions grid no overflow', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320 * 3, 480 * 3);
      tester.view.devicePixelRatio = 3.0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileQuickActions(
                onServices: () {},
                onWorkingHours: () {},
                workingHoursSubtitle: 'Bugün 09:00-20:00',
                onPhotos: () {},
                onReviews: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Hizmetlerim'), findsOneWidget);
      expect(find.text('Çalışma Saatleri'), findsOneWidget);
      expect(find.text('Fotoğraflarım'), findsOneWidget);
      expect(find.text('Yorumlarım'), findsOneWidget);
    });

    testWidgets('text scale 1.3 no overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320 * 3, 480 * 3);
      tester.view.devicePixelRatio = 3.0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: SingleChildScrollView(
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
                child: Column(
                  children: [
                    const ProfileOverviewGrid(
                      score: 95,
                      serviceCount: 12,
                      photoCount: 15,
                      radiusKm: 25,
                    ),
                    const SizedBox(height: 10),
                    ProfileQuickActions(
                      onServices: () {},
                      onWorkingHours: () {},
                      workingHoursSubtitle: 'Kapalı',
                      onPhotos: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('%95'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('25 km'), findsOneWidget);
    });

    testWidgets('long business name and storefront health pill no overflow', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320 * 3, 480 * 3);
      tester.view.devicePixelRatio = 3.0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
                child: Column(
                  children: [
                    StorefrontHealthPill(
                      'Çok Uzun Kategori veya İşletme Adı Testi',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(StorefrontHealthPill), findsOneWidget);
    });
  });
}
