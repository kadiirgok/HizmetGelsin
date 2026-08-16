import 'dart:async';

import 'package:berbergelsin/features/map/data/barbers_repo.dart';
import 'package:berbergelsin/features/map/widgets/barber_sheet/barber_sheet_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  HeroImageCandidate candidate(
    String url,
    int width,
    int height, {
    bool cover = false,
    int order = 0,
    bool blackBars = false,
  }) => HeroImageCandidate(
    url: url,
    width: width,
    height: height,
    isCover: cover,
    order: order,
    hasBlackBarRisk: blackBars,
  );

  group('Hero image candidate selection', () {
    test('valid cover wins', () {
      final selected = selectHeroImageCandidate([
        candidate('cover', 1600, 900, cover: true),
        candidate('gallery', 1800, 1000),
      ]);
      expect(selected?.url, 'cover');
    });

    test('explicit portrait, square and wide covers are accepted', () {
      expect(
        selectHeroImageCandidate([
          candidate('wide', 4000, 900, cover: true),
        ])?.url,
        'wide',
      );
      expect(
        selectHeroImageCandidate([
          candidate('portrait', 900, 1600, cover: true),
        ])?.url,
        'portrait',
      );
      expect(
        selectHeroImageCandidate([
          candidate('square-cover', 1000, 1000, cover: true),
        ])?.url,
        'square-cover',
      );
    });

    test('explicit cover wins independently of gallery suitability', () {
      final selected = selectHeroImageCandidate([
        candidate('cover', 900, 1600, cover: true),
        candidate('four-three', 1200, 900, order: 0),
        candidate('sixteen-nine', 1600, 900, order: 1),
      ]);
      expect(selected?.url, 'cover');
    });

    test('invalid dimensions, square, 9:16 and 4:1 stay safe', () {
      expect(
        selectHeroImageCandidate([
          candidate('zero-width', 0, 900),
          candidate('zero-height', 900, 0),
          candidate('square', 1000, 1000),
          candidate('portrait', 900, 1600),
          candidate('four-one', 4000, 1000),
        ]),
        isNull,
      );
    });

    test('4:3 and 16:9 are accepted', () {
      expect(
        selectHeroImageCandidate([candidate('four-three', 1200, 900)])?.url,
        'four-three',
      );
      expect(
        selectHeroImageCandidate([candidate('sixteen-nine', 1600, 900)])?.url,
        'sixteen-nine',
      );
    });

    test('source with horizontal black bar risk is rejected for hero', () {
      expect(
        selectHeroImageCandidate([
          candidate('letterboxed', 1600, 900, cover: true, blackBars: true),
        ]),
        isNull,
      );
    });
  });

  BarberDetail detail() => BarberDetail(
    barberProfileId: 'profile',
    businessName: 'Test İşletmesi',
    category: 'Teknik Servis',
    city: 'İstanbul',
    district: 'Beşiktaş',
    workingHours: '[]',
    acceptsOffers: false,
    services: const [],
  );

  Future<void> pumpHero(
    WidgetTester tester, {
    String? coverUrl,
    List<String> galleryUrls = const [],
    required Future<Size?> Function(String) resolver,
    double width = 390,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 600),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: BarberSheetHero(
              detail: detail(),
              logoBytes: null,
              coverUrl: coverUrl,
              galleryUrls: galleryUrls,
              onCall: null,
              imageSizeResolver: resolver,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  group('BarberSheetHero safe loading', () {
    testWidgets('gradient is immediate and valid cover fades into fixed hero', (
      tester,
    ) async {
      await pumpHero(
        tester,
        coverUrl: 'https://example.invalid/cover.jpg',
        resolver: (_) async => const Size(1600, 900),
      );
      expect(find.byType(BarberSheetHero), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.cover);
      expect(image.alignment, Alignment.center);
      expect((image.image as ResizeImage).height, isNull);
      expect(
        tester.getSize(find.byKey(const ValueKey('barber-hero-cover'))).height,
        140,
      );
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('barber-hero-cover-image')),
          matching: find.byKey(const ValueKey('barber-hero-cover-clip')),
        ),
        findsOneWidget,
      );
      expect(find.text('Test İşletmesi'), findsOneWidget);
      expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('failed cover metadata chooses closest safe gallery photo', (
      tester,
    ) async {
      await pumpHero(
        tester,
        coverUrl: 'https://example.invalid/cover.jpg',
        galleryUrls: const [
          'https://example.invalid/four-three.jpg',
          'https://example.invalid/sixteen-nine.jpg',
        ],
        resolver: (url) async => switch (url) {
          String value when value.endsWith('cover.jpg') => null,
          String value when value.endsWith('four-three.jpg') => const Size(
            1200,
            900,
          ),
          _ => const Size(1600, 900),
        },
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as ResizeImage).imageProvider, isA<NetworkImage>());
      final network =
          (image.image as ResizeImage).imageProvider as NetworkImage;
      expect(network.url, endsWith('sixteen-nine.jpg'));
    });

    testWidgets('metadata failure and no safe image keep gradient fallback', (
      tester,
    ) async {
      await pumpHero(
        tester,
        coverUrl: 'https://example.invalid/broken.jpg',
        galleryUrls: const ['https://example.invalid/square.jpg'],
        resolver: (url) async =>
            url.endsWith('broken.jpg') ? null : const Size(1000, 1000),
      );
      expect(find.byType(Image), findsNothing);
      expect(
        find.byKey(const ValueKey('barber-hero-fallback')),
        findsOneWidget,
      );
      expect(find.text('Test İşletmesi'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('duplicate and empty URLs are resolved once', (tester) async {
      var calls = 0;
      await pumpHero(
        tester,
        coverUrl: 'https://example.invalid/photo.jpg',
        galleryUrls: const [
          'https://example.invalid/photo.jpg',
          '',
          'https://example.invalid/photo.jpg',
        ],
        resolver: (_) async {
          calls++;
          return const Size(1600, 900);
        },
      );
      expect(calls, 1);
    });

    testWidgets('dispose before metadata completes has no exception', (
      tester,
    ) async {
      final completer = Completer<Size?>();
      await pumpHero(
        tester,
        coverUrl: 'https://example.invalid/slow.jpg',
        resolver: (_) => completer.future,
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      completer.complete(const Size(1600, 900));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      testWidgets(
        '${width.toInt()} px portrait cover is stable at text scale 1.3',
        (tester) async {
          await pumpHero(
            tester,
            width: width,
            textScale: 1.3,
            coverUrl: 'https://example.invalid/portrait.jpg',
            resolver: (_) async => const Size(900, 1600),
          );
          final image = tester.widget<Image>(find.byType(Image));
          expect(image.fit, BoxFit.cover);
          expect(image.alignment, Alignment.center);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
