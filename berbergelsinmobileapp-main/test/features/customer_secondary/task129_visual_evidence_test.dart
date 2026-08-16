import 'package:berbergelsin/features/addresses/data/client_addresses_repo.dart';
import 'package:berbergelsin/features/addresses/screens/client_addresses_screen.dart';
import 'package:berbergelsin/features/favorites/data/favorites_repo.dart';
import 'package:berbergelsin/features/favorites/screens/favorites_screen.dart';
import 'package:berbergelsin/features/notifications/controllers/notification_store.dart';
import 'package:berbergelsin/features/notifications/data/notifications_repo.dart';
import 'package:berbergelsin/features/notifications/screens/notifications_screen.dart';
import 'package:berbergelsin/features/ratings/data/client_ratings_repo.dart';
import 'package:berbergelsin/features/ratings/screens/client_ratings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/visual_test_helper.dart';

class _Addresses implements ClientAddressesRepository {
  _Addresses(this.items);
  final List<ClientAddress> items;
  @override
  Future<List<ClientAddress>> list() async => items;
  @override
  Future<ClientAddress> get(String id) async =>
      items.firstWhere((e) => e.id == id);
  @override
  Future<ClientAddress> create(ClientAddress value) async => value;
  @override
  Future<ClientAddress> update(ClientAddress value) async => value;
  @override
  Future<void> delete(String id) async {}
  @override
  Future<ClientAddress> setDefault(String id) async =>
      items.firstWhere((e) => e.id == id);
}

class _Favorites implements FavoritesRepository {
  _Favorites(this.items);
  final List<FavoriteBusiness> items;
  @override
  Future<FavoritePage> list({int page = 1, int pageSize = 20}) async =>
      FavoritePage(items, page, false);
  @override
  Future<bool> status(String id) async => true;
  @override
  Future<void> add(String id) async {}
  @override
  Future<void> remove(String id) async {}
}

class _Ratings implements ClientRatingsRepository {
  _Ratings(this.items);
  final List<ClientRating> items;
  @override
  Future<ClientRatingsPage> list({int page = 1, int pageSize = 20}) async =>
      ClientRatingsPage(items, page, pageSize, items.length, false);
  @override
  Future<ClientRating> update(
    String id, {
    required int score,
    String? comment,
    required String version,
  }) async => items.first;
  @override
  Future<void> delete(String id) async {}
  @override
  Future<void> report(
    String id, {
    required String reasonCode,
    String? description,
  }) async {}
}

class _Notifications implements NotificationsRepository {
  _Notifications(this.items);
  final List<AppNotification> items;
  @override
  Future<NotificationPage> list({
    int page = 1,
    int pageSize = 20,
    bool? isRead,
    cancelToken,
  }) async => NotificationPage(items, page, pageSize, items.length, false);
  @override
  Future<int> unreadCount({cancelToken}) async =>
      items.where((e) => !e.isRead).length;
  @override
  Future<AppNotification> markRead(String id) async =>
      items.firstWhere((e) => e.id == id).copyWith(isRead: true);
  @override
  Future<int> markAllRead() async => items.length;
  @override
  Future<void> registerDevice({
    required String platform,
    required String token,
    required String deviceId,
  }) async {}
  @override
  Future<void> unregisterDevice(String deviceId) async {}
}

ClientAddress _address() => ClientAddress(
  id: 'address-visual',
  label: 'Ev',
  addressLine: 'Sinanpaşa Mahallesi, Uzun Sokak No: 24, Daire 8, Beşiktaş',
  province: 'İstanbul',
  district: 'Beşiktaş',
  neighborhood: 'Sinanpaşa',
  latitude: 41.043,
  longitude: 29.005,
  isDefault: true,
  createdAt: DateTime(2026, 7, 1),
  updatedAt: DateTime(2026, 7, 18),
  version: 'visual-version',
);

FavoriteBusiness _favorite() => FavoriteBusiness(
  id: 'favorite-visual',
  name: 'Boğaziçi Erkek Kuaförü ve Bakım Salonu',
  category: 'Berber & Erkek Bakımı',
  city: 'İstanbul',
  district: 'Beşiktaş',
  rating: 4.9,
  reviewCount: 128,
  minimumPrice: 12500,
  isOpenNow: true,
  favoritedAt: DateTime(2026, 7, 10),
);

ClientRating _rating() => ClientRating(
  id: 'rating-visual',
  requestId: 'request-visual',
  barberId: 'business-visual',
  businessName: 'Boğaziçi Erkek Kuaförü',
  rating: 5,
  comment:
      'Randevu saatine tam zamanında geldiler. Hizmet kalitesi ve iletişimden çok memnun kaldım.',
  createdAt: DateTime(2026, 7, 18),
  updatedAt: DateTime(2026, 7, 19),
  moderationStatus: 'UnderReview',
  version: 'visual-version',
);

AppNotification _notification() => AppNotification(
  id: 'notification-visual',
  type: 'NewOffer',
  title: 'Talebiniz için yeni bir teklif aldınız',
  body:
      'Boğaziçi Erkek Kuaförü talebinize fiyat ve randevu saati içeren yeni bir teklif gönderdi.',
  entityType: 'offer',
  entityId: 'offer-visual',
  route: '/taleplerim',
  isRead: false,
  createdAt: DateTime(2026, 7, 19, 14, 30),
);

Future<void> _capture(WidgetTester tester, String name, Widget screen) async {
  final key = ValueKey('task129-$name');
  configureVisualTestViewport(tester, width: 390, height: 844);
  await tester.pumpWidget(
    buildVisualTestHarness(
      child: RepaintBoundary(key: key, child: screen),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await expectLater(find.byKey(key), matchesGoldenFile('task129/$name.png'));
}

void main() {
  setUpAll(() async {
    await loadTestFonts();
  });

  testWidgets('renders task 129 secondary screen smoke evidence', (
    tester,
  ) async {
    configureVisualTestViewport(tester, width: 390, height: 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _capture(
      tester,
      'addresses',
      ClientAddressesScreen(repository: _Addresses([_address()])),
    );
    await _capture(
      tester,
      'addresses-empty',
      ClientAddressesScreen(repository: _Addresses([])),
    );
    await _capture(
      tester,
      'favorites',
      FavoritesScreen(repository: _Favorites([_favorite()])),
    );
    await _capture(
      tester,
      'favorites-empty',
      FavoritesScreen(repository: _Favorites([])),
    );
    await _capture(
      tester,
      'ratings',
      ClientRatingsScreen(repository: _Ratings([_rating()])),
    );
    await _capture(
      tester,
      'ratings-empty',
      ClientRatingsScreen(repository: _Ratings([])),
    );

    final notifications = NotificationStore(
      repository: _Notifications([_notification()]),
    )..bindSession('visual-session');
    await _capture(
      tester,
      'notifications',
      NotificationsScreen(
        store: notifications,
        sessionUserId: 'visual-session',
      ),
    );
    await tester.pumpWidget(const SizedBox());
    notifications.dispose();

    final emptyNotifications = NotificationStore(repository: _Notifications([]))
      ..bindSession('visual-empty-session');
    await _capture(
      tester,
      'notifications-empty',
      NotificationsScreen(
        key: const ValueKey('empty-notifications'),
        store: emptyNotifications,
        sessionUserId: 'visual-empty-session',
      ),
    );
    await tester.pumpWidget(const SizedBox());
    emptyNotifications.dispose();
  });
}
