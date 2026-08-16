import 'dart:async';

import 'package:berbergelsin/core/api/api_client.dart';
import 'package:berbergelsin/features/notifications/controllers/notification_store.dart';
import 'package:berbergelsin/features/notifications/data/notifications_repo.dart';
import 'package:berbergelsin/features/notifications/screens/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeNotificationsRepository implements NotificationsRepository {
  final pages = <int, NotificationPage>{};
  int count = 0, reads = 0, readAll = 0, registers = 0, unregisters = 0;
  Object? listError, readError, readAllError;
  Completer<NotificationPage>? pendingList;
  String? readId, registeredToken;
  @override
  Future<NotificationPage> list({
    int page = 1,
    int pageSize = 20,
    bool? isRead,
    cancelToken,
  }) async {
    if (listError != null) throw listError!;
    if (pendingList case final pending?) return pending.future;
    return pages[page] ?? const NotificationPage([], 1, 20, 0, false);
  }

  @override
  Future<int> unreadCount({cancelToken}) async => count;
  @override
  Future<AppNotification> markRead(String id) async {
    reads++;
    readId = id;
    if (readError != null) throw readError!;
    final n = pages.values.expand((e) => e.items).firstWhere((e) => e.id == id);
    return n.copyWith(isRead: true, readAt: DateTime.now());
  }

  @override
  Future<int> markAllRead() async {
    readAll++;
    if (readAllError != null) throw readAllError!;
    return count;
  }

  @override
  Future<void> registerDevice({
    required String platform,
    required String token,
    required String deviceId,
  }) async {
    registers++;
    registeredToken = token;
  }

  @override
  Future<void> unregisterDevice(String deviceId) async {
    unregisters++;
  }
}

AppNotification item(
  String id, {
  bool read = false,
  String type = 'NewRequest',
  String route = '/bildirimler',
  String? title,
  String? body,
}) => AppNotification(
  id: id,
  type: type,
  title: title ?? 'Yeni bir bildirim için oldukça uzun başlık',
  body: body ?? 'Güvenli kısa açıklama',
  entityType: 'request',
  entityId: '11111111-1111-1111-1111-111111111111',
  route: route,
  isRead: read,
  createdAt: DateTime(2026, 7, 16, 12),
);

void main() {
  test('inbox DTO maps safe fields and unknown type has fallback', () {
    final n = AppNotification.fromJson({
      'id': 'n',
      'type': 'FutureType',
      'title': 'T',
      'body': 'B',
      'entityType': 'x',
      'entityId': 'e',
      'route': '/bildirimler',
      'isRead': false,
      'createdAt': '2026-07-16T10:00:00Z',
      'deduplicationKey': 'ignored',
    });
    expect(n.type, 'FutureType');
    expect(notificationIcon(n.type), Icons.notifications_outlined);
  });
  test('route allowlist blocks arbitrary URLs and maps internal routes', () {
    const id = '11111111-1111-1111-1111-111111111111';
    expect(
      safeNotificationTarget('https://evil.test', isCustomer: true),
      isNull,
    );
    expect(
      safeNotificationTarget('javascript:alert(1)', isCustomer: true),
      isNull,
    );
    expect(
      safeNotificationTarget('/talepler/$id', isCustomer: true),
      '/talep/$id',
    );
    expect(safeNotificationTarget('/isletme/$id', isCustomer: false), isNull);
  });
  test('backend errors map without exposing raw messages', () {
    for (final code in [
      'notification_not_found',
      'notification_forbidden',
      'notification_invalid_query',
      'notification_device_invalid',
      'notification_device_conflict',
      'notification_rate_limited',
      'notification_unavailable',
    ]) {
      final m = notificationErrorMessage(
        mapNotificationError(ApiException('raw', code: code)),
      );
      expect(m, isNot(contains('raw')));
    }
  });
  test(
    'device repository abstraction supports register and unregister without token provider',
    () async {
      final r = FakeNotificationsRepository();
      await r.registerDevice(
        platform: 'android',
        token: 'opaque',
        deviceId: 'd',
      );
      await r.unregisterDevice('d');
      expect(r.registers, 1);
      expect(r.unregisters, 1);
      expect(await const NoOpPushTokenProvider().token(), isNull);
    },
  );
  test('store loads, paginates and deduplicates', () async {
    final r = FakeNotificationsRepository()
      ..count = 2
      ..pages[1] = NotificationPage([item('1')], 1, 1, 2, true)
      ..pages[2] = NotificationPage([item('1'), item('2')], 2, 1, 2, false);
    final s = NotificationStore(repository: r);
    s.bindSession('u');
    await Future<void>.delayed(Duration.zero);
    expect(s.unread, 2);
    await s.loadMore();
    expect(s.items.map((e) => e.id), ['1', '2']);
    s.dispose();
  });
  test('read optimistic success and rollback are safe', () async {
    final r = FakeNotificationsRepository()
      ..count = 1
      ..pages[1] = NotificationPage([item('1')], 1, 20, 1, false);
    final s = NotificationStore(repository: r);
    s.bindSession('u');
    await Future<void>.delayed(Duration.zero);
    expect(await s.read(s.items.first), isTrue);
    expect(s.unread, 0);
    r.readError = Exception();
    s.items[0] = item('1');
    s.unread = 1;
    expect(await s.read(s.items.first), isFalse);
    expect(s.items.first.isRead, isFalse);
    expect(s.unread, 1);
    s.dispose();
  });
  test('read all success and failure rollback', () async {
    final r = FakeNotificationsRepository()
      ..count = 2
      ..pages[1] = NotificationPage([item('1'), item('2')], 1, 20, 2, false);
    final s = NotificationStore(repository: r);
    s.bindSession('u');
    await Future<void>.delayed(Duration.zero);
    await s.readAll();
    expect(s.unread, 0);
    s.unread = 2;
    s.items.replaceRange(0, 2, [item('1'), item('2')]);
    r.readAllError = Exception();
    await s.readAll();
    expect(s.unread, 2);
    expect(s.items.every((e) => !e.isRead), isTrue);
    s.dispose();
  });

  testWidgets('notification center shows cards, unread style and mark all', (
    tester,
  ) async {
    final r = FakeNotificationsRepository()
      ..count = 1
      ..pages[1] = NotificationPage(
        [item('1'), item('2', read: true, type: 'Unknown')],
        1,
        20,
        2,
        false,
      );
    final s = NotificationStore(repository: r);
    s.bindSession('u');
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          store: s,
          sessionUserId: 'u',
          isCustomerOverride: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Yeni bir bildirim için oldukça uzun başlık'),
      findsNWidgets(2),
    );
    expect(find.text('Tümünü oku'), findsOneWidget);
    expect(find.text('Okunmadı'), findsOneWidget);
    expect(find.text('Okundu'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Yeni talep bildirimi.*Okunmadı')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Genel bildirim.*Okundu')),
      findsOneWidget,
    );
    await tester.tap(find.text('Tümünü oku'));
    await tester.pump();
    expect(r.readAll, 1);
    s.dispose();
  });
  testWidgets('loading uses notification card skeleton', (tester) async {
    final pending = Completer<NotificationPage>();
    final r = FakeNotificationsRepository()..pendingList = pending;
    final s = NotificationStore(repository: r)..bindSession('u');
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(store: s, sessionUserId: 'u'),
      ),
    );
    await tester.pump();
    expect(find.bySemanticsLabel('İçerik yükleniyor'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    pending.complete(const NotificationPage([], 1, 20, 0, false));
    await tester.pumpAndSettle();
    s.dispose();
  });
  testWidgets('empty inbox and no-route notification behavior are safe', (
    tester,
  ) async {
    final emptyRepo = FakeNotificationsRepository();
    final emptyStore = NotificationStore(repository: emptyRepo)
      ..bindSession('empty');
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(store: emptyStore, sessionUserId: 'empty'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Yeni bildiriminiz yok'), findsOneWidget);
    emptyStore.dispose();

    final repo = FakeNotificationsRepository()
      ..count = 1
      ..pages[1] = NotificationPage(
        [item('no-route', route: '')],
        1,
        20,
        1,
        false,
      );
    final store = NotificationStore(repository: repo)..bindSession('u');
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          key: const ValueKey('no-route-screen'),
          store: store,
          sessionUserId: 'u',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notification-no-route')));
    await tester.pumpAndSettle();
    expect(repo.reads, 1);
    expect(find.text('Okundu'), findsOneWidget);
    store.dispose();
  });
  testWidgets('empty and safe error retry render', (tester) async {
    final r = FakeNotificationsRepository()
      ..listError = ApiException('raw', code: 'notification_rate_limited');
    final s = NotificationStore(repository: r);
    s.bindSession('u');
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          store: s,
          sessionUserId: 'u',
          isCustomerOverride: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Çok sık'), findsOneWidget);
    expect(find.text('Tekrar dene'), findsOneWidget);
    s.dispose();
  });
  testWidgets('notification offline and server errors stay distinct', (
    tester,
  ) async {
    final r = FakeNotificationsRepository()
      ..listError = ApiException(
        'raw socket detail',
        kind: ApiErrorKind.network,
      );
    final s = NotificationStore(repository: r)..bindSession('offline-user');
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          store: s,
          sessionUserId: 'offline-user',
          isCustomerOverride: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(s.offline, isTrue);
    expect(find.text('İnternet bağlantısı yok'), findsOneWidget);

    r.listError = ApiException(
      'raw server detail',
      statusCode: 500,
      kind: ApiErrorKind.server,
    );
    await s.refresh();
    await tester.pumpAndSettle();
    expect(s.offline, isFalse);
    expect(find.text('Bir sorun oluştu'), findsOneWidget);
    expect(find.textContaining('raw server detail'), findsNothing);
    s.dispose();
  });
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets('responsive $width text 1.3', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final r = FakeNotificationsRepository()
        ..count = 1
        ..pages[1] = NotificationPage([item('1')], 1, 20, 1, false);
      final s = NotificationStore(repository: r);
      s.bindSession('u');
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: const TextScaler.linear(1.3),
          ),
          child: MaterialApp(
            home: NotificationsScreen(
              store: s,
              sessionUserId: 'u',
              isCustomerOverride: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      s.dispose();
    });
  }
}
