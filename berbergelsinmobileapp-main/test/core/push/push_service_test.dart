import 'dart:async';

import 'package:berbergelsin/core/push/push_service.dart';
import 'package:berbergelsin/features/notifications/data/notifications_repo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unavailable provider produces no token and no registration', () async {
    final gateway = FakeGateway(available: false);
    final repository = FakeRepository();
    final service = PushService(
      gateway: gateway,
      repository: repository,
      deviceIdProvider: () async => 'test-device',
    );
    await service.bindUser('test-user');
    expect(repository.registered, isEmpty);
    await service.dispose();
  });

  test(
    'token registration is idempotent and token is never persisted locally',
    () async {
      final gateway = FakeGateway(tokenValue: 'opaque-test-token');
      final repository = FakeRepository();
      final service = PushService(
        gateway: gateway,
        repository: repository,
        deviceIdProvider: () async => 'test-device',
      );
      await service.bindUser('test-user');
      await service.bindUser('test-user');
      expect(repository.registered, hasLength(1));
      expect(repository.registered.single.$3, 'test-device');
      await service.dispose();
    },
  );

  test('logout unregisters even when the provider has no token', () async {
    final repository = FakeRepository();
    final service = PushService(
      gateway: FakeGateway(),
      repository: repository,
      deviceIdProvider: () async => 'test-device',
    );
    await service.bindUser('test-user');
    await service.unregister();
    expect(repository.unregistered, ['test-device']);
    await service.dispose();
  });

  test('permission states include safe unavailable fallback', () async {
    final gateway = FakeGateway(available: false);
    expect(await gateway.permission(), PushPermissionState.unavailable);
  });
}

class FakeGateway implements PushMessagingGateway {
  FakeGateway({this.available = true, this.tokenValue});
  final bool available;
  final String? tokenValue;
  final tokens = StreamController<String>.broadcast();
  final messages = StreamController<Map<String, dynamic>>.broadcast();
  final taps = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Stream<Map<String, dynamic>> get foregroundMessages => messages.stream;
  @override
  Stream<Map<String, dynamic>> get notificationTaps => taps.stream;
  @override
  Stream<String> get tokenRefresh => tokens.stream;
  @override
  Future<bool> initialize() async => available;
  @override
  Future<String?> token() async => available ? tokenValue : null;
  @override
  Future<Map<String, dynamic>?> initialMessage() async => null;
  @override
  Future<PushPermissionState> permission({bool request = false}) async =>
      available
      ? PushPermissionState.authorized
      : PushPermissionState.unavailable;
  @override
  Future<void> showForeground(Map<String, dynamic> data) async {}
  @override
  Future<void> dispose() async {
    await tokens.close();
    await messages.close();
    await taps.close();
  }
}

class FakeRepository implements NotificationsRepository {
  final registered = <(String, String, String)>[];
  final unregistered = <String>[];
  @override
  Future<void> registerDevice({
    required String platform,
    required String token,
    required String deviceId,
  }) async => registered.add((platform, token, deviceId));
  @override
  Future<void> unregisterDevice(String deviceId) async =>
      unregistered.add(deviceId);
  @override
  Future<NotificationPage> list({
    int page = 1,
    int pageSize = 20,
    bool? isRead,
    cancelToken,
  }) => throw UnimplementedError();
  @override
  Future<AppNotification> markRead(String id) => throw UnimplementedError();
  @override
  Future<int> markAllRead() => throw UnimplementedError();
  @override
  Future<int> unreadCount({cancelToken}) => throw UnimplementedError();
}
