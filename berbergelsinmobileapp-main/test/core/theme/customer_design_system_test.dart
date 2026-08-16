import 'package:berbergelsin/core/theme/app_theme.dart';
import 'package:berbergelsin/core/widgets/customer_ui.dart';
import 'package:berbergelsin/features/map/widgets/client_bottom_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test(
    'theme exposes customer color, typography, spacing and radius tokens',
    () {
      expect(AppColors.primary, isNot(AppColors.error));
      expect(
        AppTypography.textTheme.bodyMedium?.fontSize,
        greaterThanOrEqualTo(14),
      );
      expect(AppSpacing.md, 16);
      expect(AppRadius.lg, 16);
      expect(AppTheme.light.brightness, Brightness.light);
    },
  );

  testWidgets('bottom navigation has five accessible destinations', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ClientBottomNavigation(currentIndex: 0),
        ),
      ),
    );
    for (final label in [
      'Ana Sayfa',
      'Keşfet',
      'Randevular',
      'Favoriler',
      'Profil',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets(
    'customer navigation shell uses canonical routes without duplicates',
    (tester) async {
      late final GoRouter router;
      Widget page(String name, int index) => Scaffold(
        body: Text(name),
        bottomNavigationBar: ClientBottomNavigation(currentIndex: index),
      );
      router = GoRouter(
        initialLocation: '/harita',
        routes: [
          GoRoute(path: '/harita', builder: (_, _) => page('home', 0)),
          GoRoute(path: '/kesfet', builder: (_, _) => page('discover', 1)),
          GoRoute(path: '/taleplerim', builder: (_, _) => page('requests', 2)),
          GoRoute(
            path: '/favorilerim',
            builder: (_, _) => page('favorites', 3),
          ),
          GoRoute(path: '/profil', builder: (_, _) => page('profile', 4)),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final activeSemantics = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == 'Ana Sayfa',
        ),
      );
      expect(activeSemantics.properties.selected, isTrue);

      await tester.tap(find.text('Ana Sayfa'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/harita');

      await tester.tap(find.text('Keşfet'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/kesfet');
      expect(find.text('discover'), findsOneWidget);
    },
  );

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets('core components fit ${width.toInt()} px at text scale 1.3', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 800),
              textScaler: const TextScaler.linear(1.3),
            ),
            child: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AddressSelector(
                    address:
                        'İstanbul, Küçükçekmece, uzun mahalle ve sokak adı',
                    onTap: () {},
                  ),
                  const SearchField(),
                  const BusinessCard(
                    name:
                        'Çok Uzun İşletme Adı ve Profesyonel Yerel Hizmet Merkezi',
                    category: 'Ev Bakım, Onarım ve Teknik Destek Hizmetleri',
                    rating: 4.8,
                    reviewCount: 128,
                    distanceText: '2,4 km',
                    minimumPrice: 999999,
                    isOpen: true,
                  ),
                  const AppointmentCard(
                    businessName: 'Uzun İşletme Adı',
                    dateText: '24 Temmuz Cuma, 14.30',
                    status: 'Onaylandı',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('image fallback and semantic favorite label work', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: BusinessCard(
            name: 'İşletme',
            category: 'Temizlik',
            coverUrl: '',
            favorite: false,
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
    expect(find.byTooltip('Favorilere ekle'), findsOneWidget);
  });
}
