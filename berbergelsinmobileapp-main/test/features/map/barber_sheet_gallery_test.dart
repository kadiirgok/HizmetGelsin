import 'package:berbergelsin/features/map/data/barbers_repo.dart';
import 'package:berbergelsin/features/map/widgets/barber_sheet/barber_sheet_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BusinessPhoto photo(
    String id, {
    String? url,
    bool isCover = false,
    String? caption,
  }) => BusinessPhoto(
    id: id,
    url: url ?? 'https://example.invalid/$id.jpg',
    isCover: isCover,
    caption: caption,
  );

  Future<void> pumpGallery(
    WidgetTester tester, {
    List<BusinessPhoto> photos = const [],
    String? coverPhotoUrl,
    double width = 390,
    double textScale = 1,
    double pixelRatio = 1,
    Future<Size?> Function(String url)? imageSizeResolver,
  }) async {
    tester.view.physicalSize = Size(width * pixelRatio, 500 * pixelRatio);
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 500),
            devicePixelRatio: pixelRatio,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: BarberPhotoGallery(
                photos: photos,
                coverPhotoUrl: coverPhotoUrl,
                businessName: 'Test İşletmesi',
                absoluteUrlBuilder: (value) => value,
                imageSizeResolver:
                    imageSizeResolver ?? (_) async => const Size(1920, 1080),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('BarberPhotoGallery data and duplicate behavior', () {
    testWidgets('zero photos and cover-only data hide the section', (
      tester,
    ) async {
      await pumpGallery(tester);
      expect(find.byKey(const ValueKey('barber-photo-gallery')), findsNothing);

      const cover = 'https://example.invalid/cover.jpg';
      await pumpGallery(
        tester,
        photos: [photo('cover', url: cover, isCover: true)],
        coverPhotoUrl: cover,
      );
      expect(find.byKey(const ValueKey('barber-photo-gallery')), findsNothing);
    });

    testWidgets('cover URL and duplicate URLs are filtered in stable order', (
      tester,
    ) async {
      const cover = 'https://example.invalid/cover.jpg';
      const first = 'https://example.invalid/first.jpg';
      await pumpGallery(
        tester,
        coverPhotoUrl: cover,
        photos: [
          photo('cover', url: cover, isCover: true),
          photo('first', url: first),
          photo('duplicate', url: '$first/'),
          photo('second', url: 'https://example.invalid/second.jpg'),
        ],
      );

      expect(
        find.byKey(const ValueKey('barber-gallery-count')),
        findsOneWidget,
      );
      expect(find.text('2 fotoğraf'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('barber-gallery-photo-cover')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('barber-gallery-photo-first')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('barber-gallery-photo-duplicate')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('barber-gallery-photo-second')),
        findsOneWidget,
      );
      expect(find.text('Kapak'), findsNothing);
    });

    testWidgets('one photo has stable dimensions and decode target', (
      tester,
    ) async {
      await pumpGallery(tester, photos: [photo('one')], pixelRatio: 2);

      expect(
        tester.getSize(find.byKey(const ValueKey('barber-gallery-photo-one'))),
        const Size(220, 140),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.filterQuality, FilterQuality.low);
      expect(image.gaplessPlayback, isTrue);
      expect(image.image, isA<ResizeImage>());
      final resized = image.image as ResizeImage;
      expect(resized.width, 440);
      expect(resized.height, 280);
    });

    testWidgets('error placeholder keeps thumbnail geometry', (tester) async {
      await pumpGallery(
        tester,
        photos: [photo('broken', url: 'not-a-valid-network-url')],
        imageSizeResolver: (_) async => const Size(100, 200),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('barber-gallery-error-0')),
        findsOneWidget,
      );
      expect(
        tester.getSize(
          find.byKey(const ValueKey('barber-gallery-photo-broken')),
        ),
        const Size(120, 140),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('BarberPhotoGallery interaction and semantics', () {
    test('ratio rules select contain/cover and bounded widths', () {
      expect(barberGalleryFitForRatio(1080 / 2400), BoxFit.contain);
      expect(barberGalleryFitForRatio(1), BoxFit.contain);
      expect(barberGalleryFitForRatio(1920 / 1080), BoxFit.cover);
      expect(barberGalleryFitForRatio(5), BoxFit.contain);
      expect(barberGalleryFitForRatio(null), BoxFit.contain);
      expect(barberGalleryWidthForRatio(1080 / 2400), 120);
      expect(barberGalleryWidthForRatio(1), 140);
      expect(barberGalleryWidthForRatio(1920 / 1080), 220);
      expect(barberGalleryWidthForRatio(5), 220);
      expect(barberGalleryWidthForRatio(null), 160);
    });

    testWidgets('intrinsic ratios produce adaptive fits without transforms', (
      tester,
    ) async {
      final sizes = <String, Size>{
        'portrait': const Size(1080, 2400),
        'square': const Size(1254, 1254),
        'landscape': const Size(1920, 1080),
        'panorama': const Size(4000, 800),
      };
      await pumpGallery(
        tester,
        photos: sizes.keys.map((id) => photo(id)).toList(),
        imageSizeResolver: (url) async =>
            sizes.entries.firstWhere((entry) => url.contains(entry.key)).value,
      );
      await tester.pump();
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images.map((image) => image.fit), [
        BoxFit.contain,
        BoxFit.contain,
        BoxFit.cover,
      ]);
      for (final id in sizes.keys) {
        final cardFinder = find.byKey(ValueKey('barber-gallery-photo-$id'));
        if (tester.any(cardFinder)) {
          expect(
            find.descendant(of: cardFinder, matching: find.byType(Transform)),
            findsNothing,
          );
          expect(
            find.descendant(of: cardFinder, matching: find.byType(RotatedBox)),
            findsNothing,
          );
        }
      }
      expect(
        tester.getSize(
          find.byKey(const ValueKey('barber-gallery-photo-portrait')),
        ),
        const Size(120, 140),
      );
      expect(
        tester.getSize(
          find.byKey(const ValueKey('barber-gallery-photo-square')),
        ),
        const Size(140, 140),
      );
    });

    testWidgets('tap opens contain viewer and close button dismisses it', (
      tester,
    ) async {
      await pumpGallery(tester, photos: [photo('one'), photo('two')]);
      await tester.tap(find.byKey(const ValueKey('barber-gallery-photo-one')));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('Fotoğraf 1 / 2'), findsOneWidget);
      expect(
        tester.widgetList<Image>(find.byType(Image)).last.fit,
        BoxFit.contain,
      );
      expect(find.byTooltip('Kapat'), findsOneWidget);
      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
    });

    testWidgets('system back dismisses viewer and card is semantic button', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpGallery(tester, photos: [photo('one')]);
      expect(
        find.bySemanticsLabel(RegExp(r'1 / 1\. Büyütmek için dokunun\.')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('barber-gallery-photo-one')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
      semantics.dispose();
    });

    testWidgets('three photos expose order semantics and horizontal scroll', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpGallery(
        tester,
        width: 320,
        photos: [photo('one'), photo('two'), photo('three')],
      );

      expect(
        find.bySemanticsLabel(
          RegExp(r'^Fotoğraf galerisi, yatay kaydırılabilir, 3 fotoğraf'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'Test İşletmesi işletmesi fotoğrafı, 1 / 3'),
        ),
        findsOneWidget,
      );
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('barber-photo-gallery')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrollable.position.axis, Axis.horizontal);
      await tester.drag(
        find.byKey(const ValueKey('barber-gallery-list')),
        const Offset(-180, 0),
      );
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, greaterThan(0));
      semantics.dispose();
      expect(tester.takeException(), isNull);
    });

    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      testWidgets('${width.toInt()} px gallery is safe at 1.3 text scale', (
        tester,
      ) async {
        await pumpGallery(
          tester,
          width: width,
          textScale: 1.3,
          photos: [photo('one'), photo('two'), photo('three')],
        );
        expect(find.text('3 fotoğraf'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
