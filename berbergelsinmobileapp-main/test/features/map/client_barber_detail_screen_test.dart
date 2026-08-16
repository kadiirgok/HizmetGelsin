import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:berbergelsin/features/map/data/barbers_repo.dart';
import 'package:berbergelsin/features/map/screens/client_barber_detail_screen.dart';
import 'package:berbergelsin/core/api/api_client.dart';
import 'package:berbergelsin/features/ratings/data/client_ratings_repo.dart';
import 'package:berbergelsin/features/favorites/data/favorites_repo.dart';

class _FakeFavoritesRepository implements FavoritesRepository {
  _FakeFavoritesRepository({this.statusError});
  bool value = false;
  final Object? statusError;
  int adds = 0, removes = 0;

  @override
  Future<FavoritePage> list({int page = 1, int pageSize = 20}) async =>
      FavoritePage(const [], page, false);

  @override
  Future<bool> status(String id) async {
    if (statusError case final error?) throw error;
    return value;
  }

  @override
  Future<void> add(String id) async {
    adds++;
    value = true;
  }

  @override
  Future<void> remove(String id) async {
    removes++;
    value = false;
  }
}

class _FakeRatingsRepository implements ClientRatingsRepository {
  int reports = 0;
  String? reportedId, reason;
  Object? error;
  @override
  Future<void> report(
    String id, {
    required String reasonCode,
    String? description,
  }) async {
    reports++;
    reportedId = id;
    reason = reasonCode;
    if (error != null) throw error!;
  }

  @override
  Future<void> delete(String id) => throw UnimplementedError();
  @override
  Future<ClientRatingsPage> list({int page = 1, int pageSize = 20}) =>
      throw UnimplementedError();
  @override
  Future<ClientRating> update(
    String id, {
    required int score,
    String? comment,
    required String version,
  }) => throw UnimplementedError();
}

class _FakeDetailRepository implements BarberDetailRepository {
  _FakeDetailRepository({this.detailError, this.reviewError = false});
  final Object? detailError;
  bool reviewError;
  final reviewPages = <int, BarberReviewsPage>{};
  final requestedPages = <int>[];

  @override
  Future<BarberDetail> detail(String id) async {
    if (detailError != null) throw detailError!;
    return BarberDetail(
      barberProfileId: id,
      businessName: 'Gök Berberr',
      category: 'Berber',
      city: 'İstanbul',
      district: 'Kadıköy',
      serviceMode: 'Both',
      workingHours: '[]',
      acceptsOffers: true,
      services: [BarberServiceItem(id: 's1', name: 'Saç Kesimi', price: 250)],
      avgRating: 4.8,
      ratingCount: 2,
      isOpenNow: true,
      serviceRadiusKm: 15,
      coverImageUrl: '/cover.jpg',
      profileImageUrl: '/logo.jpg',
    );
  }

  @override
  Future<BarberReviewsPage> reviews(
    String id, {
    int page = 1,
    int pageSize = 20,
  }) async {
    requestedPages.add(page);
    if (reviewError) throw Exception('review');
    return reviewPages[page] ??
        const BarberReviewsPage(
          items: [],
          page: 1,
          pageSize: 20,
          totalCount: 0,
          hasNextPage: false,
        );
  }

  @override
  Future<BarberAvailabilitySummary> availability(
    String id,
    DateTime date,
  ) async => BarberAvailabilitySummary(
    barberProfileId: id,
    date: date,
    timeZone: 'Europe/Istanbul',
    isWorkingDay: true,
    isOpenNow: true,
    workingIntervals: const [AvailabilityInterval('09:00', '18:00')],
    precision: 'working_hours_only',
  );

  @override
  Future<List<int>> logoBytes(String id) async => const [];
}

BarberReview _review(String comment, int minute) => BarberReview(
  score: 5,
  comment: comment,
  clientName: 'Ayşe',
  createdAt: DateTime.utc(2026, 1, 1, 12, minute),
);

Future<void> _pump(
  WidgetTester tester,
  _FakeDetailRepository repo, {
  _FakeRatingsRepository? ratings,
  _FakeFavoritesRepository? favorites,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ClientBarberDetailScreen(
        barberProfileId: 'b1',
        repository: repo,
        ratingsRepository: ratings,
        favoritesRepository: favorites ?? _FakeFavoritesRepository(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(FavoriteStore.instance.clearSession);

  test('public review maps opaque id and ownership', () {
    final value = BarberReview.fromJson({
      'id': 'rating-guid',
      'score': 5,
      'comment': 'İyi',
      'createdAt': '2026-07-16T10:00:00Z',
      'customerDisplayName': 'A***',
      'isOwn': false,
    });
    expect(value.id, 'rating-guid');
    expect(value.clientName, 'A***');
    expect(value.isOwn, isFalse);
  });

  test('detail model maps task 101 image and state fields', () {
    final value = BarberDetail.fromJson({
      'barberProfileId': 'b1',
      'workingHours': '[]',
      'acceptsOffers': false,
      'services': [],
      'coverImageUrl': '/cover',
      'profileImageUrl': '/logo',
      'isOpenNow': true,
      'serviceRadiusKm': 12,
    });
    expect(value.coverImageUrl, '/cover');
    expect(value.profileImageUrl, '/logo');
    expect(value.isOpenNow, isTrue);
    expect(value.serviceRadiusKm, 12);
  });

  testWidgets('loads detail services open state and availability', (
    tester,
  ) async {
    await _pump(tester, _FakeDetailRepository());
    expect(find.text('Gök Berberr'), findsOneWidget);
    expect(find.text('Saç Kesimi'), findsOneWidget);
    expect(find.textContaining('250'), findsOneWidget);
    expect(find.text('Açık'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Müsaitlik Özeti'), 400);
    expect(find.text('09:00–18:00'), findsOneWidget);
    expect(find.byKey(const Key('create-service-request')), findsOneWidget);
  });

  testWidgets('loading uses detail skeleton instead of a spinner', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ClientBarberDetailScreen(
          barberProfileId: 'b1',
          repository: _PendingDetailRepository(),
          favoritesRepository: _FakeFavoritesRepository(),
        ),
      ),
    );
    await tester.pump();
    expect(find.bySemanticsLabel('İçerik yükleniyor'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('favorite state syncs with other customer surfaces', (
    tester,
  ) async {
    final favorites = _FakeFavoritesRepository();
    await _pump(tester, _FakeDetailRepository(), favorites: favorites);
    expect(find.byTooltip('Favorilere ekle'), findsOneWidget);

    FavoriteStore.instance.sync('b1', true);
    await tester.pump();
    expect(find.byTooltip('Favorilerden çıkar'), findsOneWidget);

    await tester.tap(find.byTooltip('Favorilerden çıkar'));
    await tester.pumpAndSettle();
    expect(favorites.removes, 1);
    expect(FavoriteStore.instance.ids, isNot(contains('b1')));
  });

  testWidgets('unavailable favorite status is disabled with an explanation', (
    tester,
  ) async {
    final favorites = _FakeFavoritesRepository(statusError: Exception('raw'));
    await _pump(tester, _FakeDetailRepository(), favorites: favorites);
    expect(find.byTooltip('Favori durumu yüklenemedi'), findsOneWidget);
    final button = tester.widget<IconButton>(find.byType(IconButton).first);
    expect(button.onPressed, isNull);
  });

  testWidgets('404 is shown safely and can retry', (tester) async {
    await _pump(
      tester,
      _FakeDetailRepository(detailError: ApiException('raw', statusCode: 404)),
    );
    expect(find.text('Bu işletme artık görüntülenemiyor.'), findsOneWidget);
    expect(find.text('raw'), findsNothing);
    expect(find.text('Tekrar dene'), findsOneWidget);
  });

  testWidgets('reviews paginate and duplicate entries are ignored', (
    tester,
  ) async {
    final duplicate = _review('Harika', 1);
    final repo = _FakeDetailRepository()
      ..reviewPages[1] = BarberReviewsPage(
        items: [duplicate],
        page: 1,
        pageSize: 1,
        totalCount: 2,
        hasNextPage: true,
      )
      ..reviewPages[2] = BarberReviewsPage(
        items: [duplicate, _review('Temiz', 2)],
        page: 2,
        pageSize: 1,
        totalCount: 2,
        hasNextPage: false,
      );
    await _pump(tester, repo);
    await tester.scrollUntilVisible(
      find.byKey(const Key('reviews-load-more')),
      500,
    );
    await tester.tap(find.byKey(const Key('reviews-load-more')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Harika'), findsOneWidget);
    expect(find.text('Temiz'), findsOneWidget);
    expect(repo.requestedPages, [1, 2]);
  });

  testWidgets('review error exposes retry without losing detail', (
    tester,
  ) async {
    final repo = _FakeDetailRepository(reviewError: true);
    await _pump(tester, repo);
    await tester.scrollUntilVisible(find.text('Yorumlar yüklenemedi.'), 500);
    expect(find.byKey(const Key('create-service-request')), findsOneWidget);
    repo.reviewError = false;
    await tester.tap(find.text('Tekrar dene').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Henüz yorum yok.'), findsOneWidget);
  });

  testWidgets('report action requires a real id and is hidden for own review', (
    tester,
  ) async {
    final repo = _FakeDetailRepository()
      ..reviewPages[1] = BarberReviewsPage(
        items: [
          BarberReview(
            score: 5,
            comment: 'Kimliksiz',
            createdAt: DateTime.now(),
          ),
          BarberReview(
            id: 'own-id',
            score: 4,
            comment: 'Benim',
            createdAt: DateTime.now(),
            isOwn: true,
          ),
        ],
        page: 1,
        pageSize: 20,
        totalCount: 2,
        hasNextPage: false,
      );
    await _pump(tester, repo);
    expect(find.byTooltip('Yorumu raporla'), findsNothing);
  });

  testWidgets('report sheet validates reason and sends exact rating id once', (
    tester,
  ) async {
    final ratings = _FakeRatingsRepository();
    final repo = _FakeDetailRepository()
      ..reviewPages[1] = BarberReviewsPage(
        items: [
          BarberReview(
            id: 'real-rating-id',
            score: 5,
            comment: 'Public yorum',
            clientName: 'A***',
            createdAt: DateTime.now(),
          ),
        ],
        page: 1,
        pageSize: 20,
        totalCount: 1,
        hasNextPage: false,
      );
    await _pump(tester, repo, ratings: ratings);
    await tester.scrollUntilVisible(find.byTooltip('Yorumu raporla'), 500);
    await tester.tap(find.byTooltip('Yorumu raporla'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rating-report-submit')));
    await tester.pump();
    expect(find.text('Bir neden seçin.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rating-report-reason')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spam').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rating-report-submit')));
    await tester.pumpAndSettle();
    expect(ratings.reports, 1);
    expect(ratings.reportedId, 'real-rating-id');
    expect(find.text('Yorum inceleme için bildirildi.'), findsOneWidget);
    expect(find.text('Public yorum'), findsOneWidget);
  });

  testWidgets('duplicate report shows safe conflict and keeps review', (
    tester,
  ) async {
    final ratings = _FakeRatingsRepository()
      ..error = ApiException('raw', code: 'rating_conflict');
    final repo = _FakeDetailRepository()
      ..reviewPages[1] = BarberReviewsPage(
        items: [
          BarberReview(
            id: 'r1',
            score: 5,
            comment: 'Kalır',
            createdAt: DateTime.now(),
          ),
        ],
        page: 1,
        pageSize: 20,
        totalCount: 1,
        hasNextPage: false,
      );
    await _pump(tester, repo, ratings: ratings);
    await tester.scrollUntilVisible(find.byTooltip('Yorumu raporla'), 500);
    await tester.tap(find.byTooltip('Yorumu raporla'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rating-report-reason')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spam').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rating-report-submit')));
    await tester.pumpAndSettle();
    expect(
      find.text('Yorum başka bir yerde güncellendi. Liste yenilendi.'),
      findsOneWidget,
    );
    expect(find.text('Kalır'), findsOneWidget);
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets(
      'detail is overflow safe at ${width.toInt()}px and 1.3 text scale',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              size: Size(width, 800),
              textScaler: const TextScaler.linear(1.3),
            ),
            child: MaterialApp(
              home: ClientBarberDetailScreen(
                barberProfileId: 'b1',
                repository: _FakeDetailRepository(),
                favoritesRepository: _FakeFavoritesRepository(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('detail remains usable in compact landscape', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: MaterialApp(
          home: ClientBarberDetailScreen(
            barberProfileId: 'b1',
            repository: _FakeDetailRepository(),
            favoritesRepository: _FakeFavoritesRepository(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });
}

class _PendingDetailRepository implements BarberDetailRepository {
  final pending = Completer<BarberDetail>();

  @override
  Future<BarberDetail> detail(String id) => pending.future;

  @override
  Future<BarberReviewsPage> reviews(
    String id, {
    int page = 1,
    int pageSize = 20,
  }) => throw UnimplementedError();

  @override
  Future<BarberAvailabilitySummary> availability(String id, DateTime date) =>
      throw UnimplementedError();

  @override
  Future<List<int>> logoBytes(String id) => throw UnimplementedError();
}
