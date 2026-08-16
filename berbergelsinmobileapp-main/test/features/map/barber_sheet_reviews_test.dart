import 'package:berbergelsin/features/map/data/barbers_repo.dart';
import 'package:berbergelsin/features/map/widgets/barber_sheet/barber_sheet_reviews.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BarberReview review(
    String name,
    String comment, {
    int score = 5,
    int day = 12,
  }) => BarberReview(
    score: score,
    clientName: name,
    comment: comment,
    createdAt: DateTime(2026, 7, day, 12),
  );

  Future<void> pumpReviews(
    WidgetTester tester, {
    List<BarberReview> reviews = const [],
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
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: BarberReviewsSection(reviews: reviews),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('BarberReviewsSection compact public summary', () {
    testWidgets('zero reviews shows one compact empty state', (tester) async {
      await pumpReviews(tester);

      expect(find.text('Değerlendirmeler'), findsOneWidget);
      expect(find.text('Henüz yorum yok'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('barber-reviews-empty')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.rate_review_outlined), findsOneWidget);
      expect(find.byKey(const ValueKey('barber-review-0')), findsNothing);
      expect(find.textContaining('Tüm yorum'), findsNothing);
    });

    testWidgets('one review renders name comment and rating semantics', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpReviews(
        tester,
        reviews: [review('Ayşe K.', 'Çok memnun kaldım.')],
      );

      expect(find.text('Ayşe K.'), findsOneWidget);
      expect(find.text('Çok memnun kaldım.'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'Ayşe K\., 5 üzerinden 5 yıldız')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(5));
      semantics.dispose();
    });

    testWidgets('three or more reviews render only the first two', (
      tester,
    ) async {
      await pumpReviews(
        tester,
        reviews: [
          review('Birinci', 'İlk yorum'),
          review('İkinci', 'İkinci yorum', score: 4),
          review('Üçüncü', 'Gösterilmemeli', score: 3),
        ],
      );

      expect(find.byKey(const ValueKey('barber-review-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('barber-review-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('barber-review-2')), findsNothing);
      expect(find.text('Birinci'), findsOneWidget);
      expect(find.text('İkinci'), findsOneWidget);
      expect(find.text('Üçüncü'), findsNothing);
      expect(find.text('Gösterilmemeli'), findsNothing);
    });

    testWidgets('long name and comment are ellipsized without overflow', (
      tester,
    ) async {
      const longComment =
          'Bu çok uzun yorum metni küçük ekranlarda kartın gereksiz şekilde büyümesini engellemek için kontrollü olarak sınırlandırılmalıdır. Aynı zamanda içerik kullanıcı için anlamlı kalmalıdır.';
      await pumpReviews(
        tester,
        width: 320,
        textScale: 1.3,
        reviews: [
          review('Çok Uzun İsimli Müşteri Gösterim Adı Soyadı', longComment),
        ],
      );

      final comment = tester.widget<Text>(find.text(longComment));
      expect(comment.maxLines, 3);
      expect(comment.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });

    testWidgets('missing customer name and comment remain safe', (
      tester,
    ) async {
      await pumpReviews(
        tester,
        reviews: [BarberReview(score: 0, createdAt: DateTime(2026, 7, 12))],
      );

      expect(find.text('Müşteri'), findsOneWidget);
      expect(find.byKey(const ValueKey('barber-review-0')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('BarberReviewsSection responsive', () {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      testWidgets(
        '${width.toInt()} px review summary is safe at 1.3 text scale',
        (tester) async {
          await pumpReviews(
            tester,
            width: width,
            textScale: 1.3,
            reviews: [
              review(
                'Uzun Müşteri Gösterim Adı',
                'Okunabilir fakat kontrollü uzunluktaki müşteri yorumu.',
              ),
              review('İkinci Müşteri', 'İkinci kısa yorum.', score: 4),
            ],
          );
          expect(find.byKey(const ValueKey('barber-review-1')), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
