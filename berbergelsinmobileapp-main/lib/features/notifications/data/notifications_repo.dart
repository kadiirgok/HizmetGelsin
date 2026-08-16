import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.entityType,
    required this.entityId,
    required this.route,
    required this.isRead,
    this.readAt,
    required this.createdAt,
  });
  final String id, type, title, body, entityType, entityId, route;
  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;
  AppNotification copyWith({bool? isRead, DateTime? readAt}) => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    entityType: entityType,
    entityId: entityId,
    route: route,
    isRead: isRead ?? this.isRead,
    readAt: readAt ?? this.readAt,
    createdAt: createdAt,
  );
  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        type: json['type'] as String? ?? 'Unknown',
        title: json['title'] as String? ?? 'Bildirim',
        body: json['body'] as String? ?? '',
        entityType: json['entityType'] as String? ?? 'unknown',
        entityId: json['entityId'] as String? ?? '',
        route: json['route'] as String? ?? '',
        isRead: json['isRead'] as bool? ?? false,
        readAt: json['readAt'] == null
            ? null
            : DateTime.parse(json['readAt'] as String).toLocal(),
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      );
}

class NotificationPage {
  const NotificationPage(
    this.items,
    this.page,
    this.pageSize,
    this.totalCount,
    this.hasNextPage,
  );
  final List<AppNotification> items;
  final int page, pageSize, totalCount;
  final bool hasNextPage;
}

enum NotificationError {
  notFound,
  forbidden,
  invalidQuery,
  deviceInvalid,
  deviceConflict,
  rateLimited,
  unavailable,
}

NotificationError mapNotificationError(ApiException e) => switch (e.code) {
  'notification_not_found' => NotificationError.notFound,
  'notification_forbidden' => NotificationError.forbidden,
  'notification_invalid_query' => NotificationError.invalidQuery,
  'notification_device_invalid' => NotificationError.deviceInvalid,
  'notification_device_conflict' => NotificationError.deviceConflict,
  'notification_rate_limited' => NotificationError.rateLimited,
  _ => NotificationError.unavailable,
};
String notificationErrorMessage(NotificationError e) => switch (e) {
  NotificationError.notFound => 'Bildirim artık bulunamıyor.',
  NotificationError.forbidden => 'Bu bildirim için yetkiniz yok.',
  NotificationError.invalidQuery => 'Bildirim isteği geçersiz.',
  NotificationError.deviceInvalid => 'Cihaz bildirim bilgisi geçersiz.',
  NotificationError.deviceConflict =>
    'Cihaz kaydı başka bir yerde güncellendi.',
  NotificationError.rateLimited =>
    'Çok sık yenileme yapıldı. Lütfen biraz bekleyin.',
  NotificationError.unavailable => 'Bildirimlere ulaşılamadı. Tekrar deneyin.',
};

abstract interface class NotificationsRepository {
  Future<NotificationPage> list({
    int page = 1,
    int pageSize = 20,
    bool? isRead,
    CancelToken? cancelToken,
  });
  Future<int> unreadCount({CancelToken? cancelToken});
  Future<AppNotification> markRead(String id);
  Future<int> markAllRead();
  Future<void> registerDevice({
    required String platform,
    required String token,
    required String deviceId,
  });
  Future<void> unregisterDevice(String deviceId);
}

class NotificationsRepo implements NotificationsRepository {
  NotificationsRepo._();
  static final instance = NotificationsRepo._();
  final _api = ApiClient.instance;
  @override
  Future<NotificationPage> list({
    int page = 1,
    int pageSize = 20,
    bool? isRead,
    CancelToken? cancelToken,
  }) async {
    final j = await _api.get<Map<String, dynamic>>(
      '/api/notifications',
      query: {
        'page': page,
        'pageSize': pageSize,
        if (isRead != null) 'isRead': isRead,
      },
      cancelToken: cancelToken,
    );
    final seen = <String>{};
    return NotificationPage(
      (j['items'] as List)
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .where((e) => seen.add(e.id))
          .toList(),
      j['page'] as int,
      j['pageSize'] as int,
      j['totalCount'] as int,
      j['hasNextPage'] as bool,
    );
  }

  @override
  Future<int> unreadCount({CancelToken? cancelToken}) async =>
      ((await _api.get<Map<String, dynamic>>(
                '/api/notifications/unread-count',
                cancelToken: cancelToken,
              ))['unreadCount']
              as num)
          .toInt()
          .clamp(0, 999999);
  @override
  Future<AppNotification> markRead(String id) async => AppNotification.fromJson(
    await _api.post<Map<String, dynamic>>('/api/notifications/$id/read'),
  );
  @override
  Future<int> markAllRead() async =>
      ((await _api.post<Map<String, dynamic>>(
                '/api/notifications/read-all',
              ))['updatedCount']
              as num)
          .toInt();
  @override
  Future<void> registerDevice({
    required String platform,
    required String token,
    required String deviceId,
  }) => _api.post(
    '/api/notifications/devices',
    data: {'platform': platform, 'token': token, 'deviceId': deviceId},
  );
  @override
  Future<void> unregisterDevice(String deviceId) =>
      _api.delete('/api/notifications/devices/$deviceId');
}

abstract interface class PushTokenProvider {
  Future<String?> token();
}

class NoOpPushTokenProvider implements PushTokenProvider {
  const NoOpPushTokenProvider();
  @override
  Future<String?> token() async => null;
}
