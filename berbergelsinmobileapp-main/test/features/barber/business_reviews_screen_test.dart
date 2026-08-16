import 'dart:async';

import 'package:berbergelsin/features/barber/data/business_reviews.dart';
import 'package:berbergelsin/features/barber/data/business_reviews_repository.dart';
import 'package:berbergelsin/features/barber/screens/barber_profile_screen.dart';
import 'package:berbergelsin/features/barber/screens/business_reviews_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeReviewsRepository implements BusinessReviewsRepository {
  FakeReviewsRepository(this.handler);

  Future<BusinessReviewsPage> Function(int page, int? rating) handler;
  final calls = <(int, int?)>[];

  @override
  Future<BusinessReviewsPage> fetch({
    required int page,
    int pageSize = 20,
    int? rating,
  }) {
    calls.add((page, rating));
    return handler(page, rating);
  }
}

BusinessReview review(
  String id, {
  int rating = 5,
  String? comment = 'Çok memnun kaldım.',
  String name = 'Ayşe',
}) => BusinessReview(
  id: id,
  rating: rating,
  comment: comment,
  createdAt: DateTime.utc(2026, 7, 14),
  customerDisplayName: name,
  serviceName: 'Ev Temizliği',
  serviceRequestId: 'request-$id',
);

BusinessReviewsPage page({
  List<BusinessReview> items = const [],
  int current = 1,
  int totalPages = 1,
  BusinessReviewsSummary summary = const BusinessReviewsSummary(
    averageRating: 4.5,
    totalCount: 2,
    ratingDistribution: {1: 0, 2: 0, 3: 0, 4: 1, 5: 1},
  ),
}) => BusinessReviewsPage(
  items: items,
  page: current,
  pageSize: 20,
  totalCount: summary.totalCount,
  totalPages: totalPages,
  summary: summary,
);

Widget app(BusinessReviewsRepository repository) => MaterialApp(
  theme: ThemeData(useMaterial3: true),
  home: BusinessReviewsScreen(repository: repository),
);

void main() {
  testWidgets('loading state is visible', (tester) async {
    final pending = Completer<BusinessReviewsPage>();
    await tester.pumpWidget(
      app(FakeReviewsRepository((_, _) => pending.future)),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('empty state and zero summary render', (tester) async {
    final repository = FakeReviewsRepository(
      (_, _) async => page(summary: BusinessReviewsSummary.empty),
    );
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    expect(find.text('Henüz yorum yok'), findsOneWidget);
    expect(find.text('0.0'), findsOneWidget);
    expect(find.text('0 yorum'), findsOneWidget);
  });

  testWidgets('error retries without exposing exception', (tester) async {
    var fails = true;
    final repository = FakeReviewsRepository((_, _) async {
      if (fails) throw StateError('secret technical error');
      return page(items: [review('1')]);
    });
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    expect(find.text('Yorumlar yüklenemedi'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    fails = false;
    await tester.tap(find.text('Tekrar Dene'));
    await tester.pumpAndSettle();
    expect(find.text('Çok memnun kaldım.'), findsOneWidget);
  });

  testWidgets('review card, summary and Turkish date render', (tester) async {
    final repository = FakeReviewsRepository(
      (_, _) async => page(items: [review('1')]),
    );
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    expect(find.text('Ayşe'), findsOneWidget);
    expect(find.text('Ev Temizliği'), findsOneWidget);
    expect(find.text('14 Temmuz 2026'), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('2 yorum'), findsOneWidget);
  });

  testWidgets('long name and comment have no overflow at 320 px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320 * 3, 700 * 3);
    tester.view.devicePixelRatio = 3;
    final longComment = List.filled(
      18,
      'Uzun yorum metni okunabilir biçimde satırlara ayrılmalıdır.',
    ).join(' ');
    final repository = FakeReviewsRepository(
      (_, _) async => page(
        items: [
          review(
            '1',
            name: 'Çok Uzun Müşteri Gösterim Adı Taşmamalıdır',
            comment: longComment,
          ),
        ],
      ),
    );
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(longComment), findsOneWidget);
  });

  testWidgets('rating filter is server-side and summary remains global', (
    tester,
  ) async {
    final globalSummary = const BusinessReviewsSummary(
      averageRating: 4.2,
      totalCount: 10,
      ratingDistribution: {1: 1, 2: 0, 3: 1, 4: 3, 5: 5},
    );
    final repository = FakeReviewsRepository(
      (_, rating) async => page(
        items: rating == 5 ? [review('5')] : [review('all', rating: 4)],
        summary: globalSummary,
      ),
    );
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '5'));
    await tester.pumpAndSettle();
    expect(repository.calls.last, (1, 5));
    expect(find.text('10 yorum'), findsOneWidget);
    expect(find.text('Çok memnun kaldım.'), findsOneWidget);
  });

  testWidgets('filter empty state differs from global empty', (tester) async {
    final repository = FakeReviewsRepository((_, rating) async {
      if (rating != null) return page(items: const []);
      return page(items: [review('1')]);
    });
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '5'));
    await tester.pumpAndSettle();
    expect(find.text('Bu puanda yorum yok'), findsOneWidget);
    expect(find.text('Henüz yorum yok'), findsNothing);
  });

  testWidgets('pull-to-refresh reloads first page without duplicates', (
    tester,
  ) async {
    final repository = FakeReviewsRepository(
      (_, _) async => page(items: [review('same')]),
    );
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();
    expect(repository.calls.where((call) => call.$1 == 1).length, 2);
    expect(find.text('Çok memnun kaldım.'), findsOneWidget);
  });

  testWidgets('pagination prevents duplicate review ids', (tester) async {
    final firstItems = List.generate(20, (i) => review('$i'));
    final repository = FakeReviewsRepository((requestedPage, _) async {
      if (requestedPage == 1) {
        return page(items: firstItems, current: 1, totalPages: 2);
      }
      return page(
        items: [
          review('19'),
          review('20', comment: 'İkinci sayfa yorumu'),
        ],
        current: 2,
        totalPages: 2,
      );
    });
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('İkinci sayfa yorumu'),
      find.byType(CustomScrollView),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(repository.calls.where((call) => call.$1 == 2).length, 1);
    expect(find.text('İkinci sayfa yorumu'), findsOneWidget);
  });

  testWidgets('back pops only the reviews route', (tester) async {
    final repository = FakeReviewsRepository(
      (_, _) async => page(summary: BusinessReviewsSummary.empty),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BusinessReviewsScreen(repository: repository),
                ),
              ),
              child: const Text('Yorumlarım'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Yorumlarım'));
    await tester.pumpAndSettle();
    expect(find.text('Tüm Yorumlar'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Yorumlarım'), findsOneWidget);
  });

  testWidgets('Yorumlarım action opens separate screen without tab callback', (
    tester,
  ) async {
    var tabChanged = false;
    final repository = FakeReviewsRepository(
      (_, _) async => page(summary: BusinessReviewsSummary.empty),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ProfileQuickActions(
              onServices: () => tabChanged = true,
              onWorkingHours: () {},
              onPhotos: () {},
              onReviews: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BusinessReviewsScreen(repository: repository),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Yorumlarım'));
    await tester.pumpAndSettle();
    expect(find.text('Tüm Yorumlar'), findsOneWidget);
    expect(tabChanged, isFalse);
  });
}
