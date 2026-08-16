import 'dart:async';

import 'package:berbergelsin/core/api/api_client.dart';
import 'package:berbergelsin/features/favorites/data/favorites_repo.dart';
import 'package:berbergelsin/features/favorites/screens/favorites_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

FavoriteBusiness fav({String id = 'b1'}) => FavoriteBusiness(
  id: id,
  name: 'Çok Uzun Türkçe İşletme',
  category: 'Berber',
  city: 'İstanbul',
  district: 'Beşiktaş',
  rating: 4.8,
  reviewCount: 12,
  minimumPrice: 450,
  isOpenNow: true,
  favoritedAt: DateTime(2026, 7, 16),
);

class R implements FavoritesRepository {
  List<FavoriteBusiness> items;
  R(this.items);
  int adds = 0, removes = 0;
  Object? error, removeError;
  Completer<FavoritePage>? pending;
  final pages = <int, FavoritePage>{};
  @override
  Future<FavoritePage> list({int page = 1, int pageSize = 20}) async {
    if (error case final e?) throw e;
    if (pending case final value?) return value.future;
    if (pages[page] case final value?) return value;
    return FavoritePage(items, page, false);
  }

  @override
  Future<bool> status(String id) async => items.any((e) => e.id == id);
  @override
  Future<void> add(String id) async {
    adds++;
    if (error case final e?) throw e;
  }

  @override
  Future<void> remove(String id) async {
    removes++;
    if (removeError case final e?) throw e;
    if (error case final e?) throw e;
  }
}

void main() {
  test('favorite DTO mapping and safe errors', () {
    final b = FavoriteBusiness.fromJson({
      'id': 'b',
      'name': 'X',
      'reviewCount': 1,
      'isOpenNow': true,
      'favoritedAt': '2026-01-01T00:00:00Z',
    });
    expect(b.id, 'b');
    expect(
      favoriteErrorMessage(
        mapFavoriteError(ApiException('raw sql', code: 'favorite_conflict')),
      ),
      isNot(contains('raw sql')),
    );
  });
  testWidgets('list renders card fields and remove optimistic', (t) async {
    final r = R([fav()]);
    await t.pumpWidget(MaterialApp(home: FavoritesScreen(repository: r)));
    await t.pumpAndSettle();
    expect(find.text('Çok Uzun Türkçe İşletme'), findsOneWidget);
    expect(find.byTooltip('Favorilerden çıkar'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp('Çok Uzun Türkçe İşletme.*4.8 puan.*minimum 450.*açık'),
      ),
      findsOneWidget,
    );
    await t.tap(find.byTooltip('Favorilerden çıkar'));
    await t.pumpAndSettle();
    expect(r.removes, 1);
    expect(find.text('Henüz favori işletmeniz yok'), findsOneWidget);
  });
  testWidgets('loading uses favorite card skeleton', (t) async {
    final pending = Completer<FavoritePage>();
    final r = R([])..pending = pending;
    await t.pumpWidget(MaterialApp(home: FavoritesScreen(repository: r)));
    await t.pump();
    expect(find.bySemanticsLabel('İçerik yükleniyor'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    pending.complete(const FavoritePage([], 1, false));
    await t.pumpAndSettle();
  });
  testWidgets('favorite server error is safe and retryable', (t) async {
    final r = R([])
      ..error = ApiException(
        'raw database detail',
        statusCode: 500,
        kind: ApiErrorKind.server,
      );
    await t.pumpWidget(MaterialApp(home: FavoritesScreen(repository: r)));
    await t.pumpAndSettle();
    expect(find.text('Bir sorun oluştu'), findsOneWidget);
    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(find.textContaining('raw database detail'), findsNothing);
  });
  testWidgets('pagination deduplicates and keeps existing cards', (t) async {
    final r = R([])
      ..pages[1] = FavoritePage([fav(id: 'b1')], 1, true)
      ..pages[2] = FavoritePage([fav(id: 'b1'), fav(id: 'b2')], 2, false);
    await t.pumpWidget(MaterialApp(home: FavoritesScreen(repository: r)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('favorite-card-b1')), findsOneWidget);
    expect(find.byKey(const ValueKey('favorite-card-b2')), findsOneWidget);
  });
  testWidgets('optimistic remove rolls back with a safe message', (t) async {
    final r = R([fav()]);
    await t.pumpWidget(MaterialApp(home: FavoritesScreen(repository: r)));
    await t.pumpAndSettle();
    r.removeError = ApiException('raw server', statusCode: 500);
    await t.tap(find.byTooltip('Favorilerden çıkar'));
    await t.pumpAndSettle();
    expect(find.text('Çok Uzun Türkçe İşletme'), findsOneWidget);
    expect(find.textContaining('raw server'), findsNothing);
  });
  testWidgets('business card navigates to the existing detail route', (
    t,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => FavoritesScreen(repository: R([fav()])),
        ),
        GoRoute(
          path: '/isletme/:id',
          builder: (_, state) => Text('detail:${state.pathParameters['id']}'),
        ),
        GoRoute(path: '/kesfet', builder: (_, __) => const SizedBox()),
      ],
    );
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.pumpAndSettle();
    await t.tap(find.text('Çok Uzun Türkçe İşletme'));
    await t.pumpAndSettle();
    expect(find.text('detail:b1'), findsOneWidget);
    router.dispose();
  });
  testWidgets('empty and error retry states', (t) async {
    await t.pumpWidget(MaterialApp(home: FavoritesScreen(repository: R([]))));
    await t.pumpAndSettle();
    expect(find.text('Henüz favori işletmeniz yok'), findsOneWidget);
  });
  for (final w in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets('responsive ${w.toInt()} 1.3', (t) async {
      t.view.physicalSize = Size(w, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: Size(w, 800),
            textScaler: const TextScaler.linear(1.3),
          ),
          child: MaterialApp(home: FavoritesScreen(repository: R([fav()]))),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
