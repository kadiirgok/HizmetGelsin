import 'dart:async';

import 'package:berbergelsin/core/api/api_client.dart';
import 'package:berbergelsin/features/ratings/data/client_ratings_repo.dart';
import 'package:berbergelsin/features/ratings/screens/client_ratings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRatingsRepository implements ClientRatingsRepository {
  FakeRatingsRepository(this.items);
  final List<ClientRating> items;
  int deletes = 0, updates = 0, reports = 0, lists = 0;
  Object? listError, updateError, deleteError;
  Completer<ClientRatingsPage>? pendingList;

  @override
  Future<ClientRatingsPage> list({int page = 1, int pageSize = 20}) async {
    lists++;
    if (listError case final failure?) throw failure;
    if (pendingList case final pending?) return pending.future;
    return ClientRatingsPage(
      List.of(items),
      page,
      pageSize,
      items.length,
      false,
    );
  }

  @override
  Future<ClientRating> update(
    String id, {
    required int score,
    String? comment,
    required String version,
  }) async {
    updates++;
    if (updateError case final failure?) {
      updateError = null;
      throw failure;
    }
    final old = items.singleWhere((e) => e.id == id);
    final value = ClientRating(
      id: old.id,
      requestId: old.requestId,
      barberId: old.barberId,
      businessName: old.businessName,
      rating: score,
      comment: comment,
      createdAt: old.createdAt,
      updatedAt: DateTime.now(),
      moderationStatus: old.moderationStatus,
      version: 'v2',
    );
    items[items.indexOf(old)] = value;
    return value;
  }

  @override
  Future<void> delete(String id) async {
    deletes++;
    if (deleteError case final failure?) throw failure;
    items.removeWhere((e) => e.id == id);
  }

  @override
  Future<void> report(
    String id, {
    required String reasonCode,
    String? description,
  }) async {
    reports++;
  }
}

ClientRating sample({
  String id = 'rating-1',
  String status = 'Visible',
  String comment = 'Çok iyi hizmet',
  DateTime? createdAt,
}) => ClientRating(
  id: id,
  requestId: 'request-1',
  barberId: 'barber-1',
  businessName: 'Gök Berberr',
  rating: 5,
  comment: comment,
  createdAt: createdAt ?? DateTime.now().subtract(const Duration(days: 1)),
  moderationStatus: status,
  version: 'version-1',
);

void main() {
  test('history DTO maps moderation and concurrency version', () {
    final rating = ClientRating.fromJson({
      'id': 'r',
      'requestId': 'q',
      'barberId': 'b',
      'businessName': 'Berber',
      'rating': 4,
      'comment': 'İyi',
      'createdAt': '2026-07-15T10:00:00Z',
      'updatedAt': null,
      'moderationStatus': 'UnderReview',
      'version': 'v',
    });
    expect(rating.version, 'v');
    expect(rating.moderationStatus, 'UnderReview');
  });

  test(
    'transport contracts are exact and report does not expose internal data',
    () {
      final update = buildRatingTransport(
        'update',
        'r',
        score: 4,
        comment: 'Yeni',
        version: 'v1',
      );
      expect(update.path, '/api/ratings/r');
      expect(update.body, {'score': 4, 'comment': 'Yeni', 'version': 'v1'});
      final report = buildRatingTransport(
        'report',
        'r',
        reasonCode: 'spam',
        description: 'Açıklama',
      );
      expect(report.path, '/api/ratings/r/report');
      expect(report.body, {'reasonCode': 'spam', 'description': 'Açıklama'});
    },
  );

  test('all backend errors map to safe local messages', () {
    for (final code in [
      'rating_not_found',
      'rating_forbidden',
      'rating_request_not_completed',
      'rating_already_exists',
      'rating_invalid',
      'rating_edit_window_expired',
      'rating_locked',
      'rating_report_invalid',
      'rating_conflict',
      'rating_rate_limited',
    ]) {
      final mapped = mapRatingError(
        ApiException('raw backend text', code: code),
      );
      expect(ratingErrorMessage(mapped), isNot(contains('raw backend text')));
    }
  });

  testWidgets('history renders customer fields and moderation badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ClientRatingsScreen(
          repository: FakeRatingsRepository([sample(status: 'UnderReview')]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Gök Berberr'), findsOneWidget);
    expect(find.text('Çok iyi hizmet'), findsWidgets);
    expect(find.text('İnceleniyor'), findsOneWidget);
    expect(find.text('Düzenle'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('Gök Berberr.*5 puan.*İnceleniyor')),
      findsOneWidget,
    );
  });

  testWidgets('loading uses rating card skeleton', (tester) async {
    final pending = Completer<ClientRatingsPage>();
    final repo = FakeRatingsRepository([])..pendingList = pending;
    await tester.pumpWidget(
      MaterialApp(home: ClientRatingsScreen(repository: repo)),
    );
    await tester.pump();
    expect(find.bySemanticsLabel('İçerik yükleniyor'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    pending.complete(const ClientRatingsPage([], 1, 20, 0, false));
    await tester.pumpAndSettle();
  });

  testWidgets('rating rate limit error is safe and retryable', (tester) async {
    final repo = FakeRatingsRepository([])
      ..listError = ApiException(
        'raw throttle detail',
        statusCode: 429,
        code: 'rating_rate_limited',
      );
    await tester.pumpWidget(
      MaterialApp(home: ClientRatingsScreen(repository: repo)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bir sorun oluştu'), findsOneWidget);
    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(find.textContaining('raw throttle detail'), findsNothing);
  });

  testWidgets('hidden moderation and expired edit window are explicit', (
    tester,
  ) async {
    final hidden = sample(status: 'Hidden');
    final old = sample(
      id: 'rating-old',
      createdAt: DateTime.now().subtract(const Duration(days: 8)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ClientRatingsScreen(
          repository: FakeRatingsRepository([hidden, old]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Yayından kaldırıldı'), findsOneWidget);
    expect(find.text('Düzenleme kullanılamıyor'), findsOneWidget);
    expect(find.text('Düzenleme süresi doldu'), findsOneWidget);
    for (final button in tester.widgetList<OutlinedButton>(
      find.byType(OutlinedButton),
    )) {
      expect(button.onPressed, isNull);
    }
  });

  testWidgets('long comment expands and collapses without overflow', (
    tester,
  ) async {
    final longComment = List.filled(
      30,
      'Uzun yorum metni kontrollü biçimde gösterilir.',
    ).join(' ');
    await tester.pumpWidget(
      MaterialApp(
        home: ClientRatingsScreen(
          repository: FakeRatingsRepository([sample(comment: longComment)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Devamını göster'), findsOneWidget);
    await tester.tap(find.text('Devamını göster'));
    await tester.pumpAndSettle();
    expect(find.text('Daralt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('visible rating opens prefilled edit form and updates', (
    tester,
  ) async {
    final repo = FakeRatingsRepository([sample()]);
    await tester.pumpWidget(
      MaterialApp(home: ClientRatingsScreen(repository: repo)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Düzenle'));
    await tester.pumpAndSettle();
    expect(find.text('Yorumu düzenle'), findsOneWidget);
    expect(find.text('Çok iyi hizmet'), findsWidgets);
    await tester.tap(find.text('Gönder'));
    await tester.pumpAndSettle();
    expect(repo.updates, 1);
  });

  testWidgets('edit conflict refreshes list and hides raw message', (
    tester,
  ) async {
    final repo = FakeRatingsRepository([sample()])
      ..updateError = ApiException(
        'raw conflict detail',
        code: 'rating_conflict',
        statusCode: 409,
      );
    await tester.pumpWidget(
      MaterialApp(home: ClientRatingsScreen(repository: repo)),
    );
    await tester.pumpAndSettle();
    final before = repo.lists;
    await tester.tap(find.text('Düzenle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gönder'));
    await tester.pumpAndSettle();
    expect(repo.lists, greaterThan(before));
    expect(find.textContaining('raw conflict detail'), findsNothing);
  });

  testWidgets('delete uses confirmation and removes item', (tester) async {
    final repo = FakeRatingsRepository([sample()]);
    await tester.pumpWidget(
      MaterialApp(home: ClientRatingsScreen(repository: repo)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaldır'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Kaldır'));
    await tester.pumpAndSettle();
    expect(repo.deletes, 1);
    expect(find.text('Gök Berberr'), findsNothing);
  });

  testWidgets('empty state is safe', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ClientRatingsScreen(repository: FakeRatingsRepository([])),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Henüz yorum yapmadınız'), findsOneWidget);
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets('rating card is responsive at $width and text scale 1.3', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: const TextScaler.linear(1.3),
          ),
          child: MaterialApp(
            home: ClientRatingsScreen(
              repository: FakeRatingsRepository([sample()]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
