import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/signalr/signalr_service.dart';
import '../data/notifications_repo.dart';

enum NotificationLoadState {
  initial,
  loading,
  success,
  empty,
  refreshing,
  loadingMore,
  markingRead,
  markingAllRead,
  rateLimited,
  networkError,
}

class NotificationStore extends ChangeNotifier {
  NotificationStore({NotificationsRepository? repository})
    : repository = repository ?? NotificationsRepo.instance;
  static final instance = NotificationStore();
  final NotificationsRepository repository;
  final items = <AppNotification>[];
  final busyIds = <String>{};
  NotificationLoadState state = NotificationLoadState.initial;
  int unread = 0, page = 0;
  bool hasMore = true;
  bool offline = false;
  String? error;
  NotificationError? lastError;
  String? _sessionId;
  CancelToken? _cancel;
  bool _allBusy = false;
  final _unsubscribers = <void Function()>[];

  void clearSession() {
    _cancel?.cancel();
    _sessionId = null;
    items.clear();
    busyIds.clear();
    unread = 0;
    page = 0;
    hasMore = true;
    state = NotificationLoadState.initial;
    error = null;
    lastError = null;
    offline = false;
    for (final unsubscribe in _unsubscribers) {
      unsubscribe();
    }
    _unsubscribers.clear();
    notifyListeners();
  }

  void bindSession(String userId) {
    if (_sessionId == userId) return;
    _cancel?.cancel();
    items.clear();
    unread = 0;
    page = 0;
    hasMore = true;
    error = null;
    lastError = null;
    offline = false;
    _sessionId = userId;
    for (final u in _unsubscribers) {
      u();
    }
    _unsubscribers.clear();
    _unsubscribers.add(
      SignalRService.instance.on('NotificationCreated', (_) => refresh()),
    );
    _unsubscribers.add(
      SignalRService.instance.on('NotificationUnreadCountChanged', (args) {
        final raw = args?.isNotEmpty == true && args!.first is Map
            ? (args.first as Map)['unreadCount']
            : null;
        if (raw is num) {
          unread = raw.toInt().clamp(0, 999999);
          notifyListeners();
        }
      }),
    );
    _unsubscribers.add(SignalRService.instance.onReconnected(refresh));
    refresh();
  }

  Future<void> refresh() async {
    if (_sessionId == null) return;
    _cancel?.cancel();
    final token = _cancel = CancelToken();
    state = items.isEmpty
        ? NotificationLoadState.loading
        : NotificationLoadState.refreshing;
    notifyListeners();
    try {
      final results = await Future.wait([
        repository.list(cancelToken: token),
        repository.unreadCount(cancelToken: token),
      ]);
      if (token.isCancelled || _cancel != token) return;
      final p = results[0] as NotificationPage;
      items
        ..clear()
        ..addAll(p.items);
      page = p.page;
      hasMore = p.hasNextPage;
      unread = (results[1] as int).clamp(0, 999999);
      error = null;
      lastError = null;
      offline = false;
      state = items.isEmpty
          ? NotificationLoadState.empty
          : NotificationLoadState.success;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      _fail(e);
    } catch (e) {
      _fail(e);
    }
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (!hasMore ||
        state == NotificationLoadState.loading ||
        state == NotificationLoadState.refreshing ||
        state == NotificationLoadState.loadingMore) {
      return;
    }
    state = NotificationLoadState.loadingMore;
    notifyListeners();
    try {
      final p = await repository.list(page: page + 1);
      final ids = items.map((e) => e.id).toSet();
      items.addAll(p.items.where((e) => ids.add(e.id)));
      page = p.page;
      hasMore = p.hasNextPage;
      error = null;
      lastError = null;
      offline = false;
      state = NotificationLoadState.success;
    } catch (e) {
      _fail(e);
    }
    notifyListeners();
  }

  Future<bool> read(AppNotification item) async {
    if (item.isRead) return true;
    if (!busyIds.add(item.id)) return false;
    final i = items.indexWhere((e) => e.id == item.id);
    final old = items[i];
    items[i] = old.copyWith(isRead: true, readAt: DateTime.now());
    unread = (unread - 1).clamp(0, 999999);
    notifyListeners();
    try {
      items[i] = await repository.markRead(item.id);
      error = null;
      lastError = null;
      offline = false;
      return true;
    } catch (e) {
      items[i] = old;
      unread++;
      _fail(e);
      return false;
    } finally {
      busyIds.remove(item.id);
      notifyListeners();
    }
  }

  Future<void> readAll() async {
    if (_allBusy || unread == 0) return;
    _allBusy = true;
    final old = List<AppNotification>.of(items);
    final oldUnread = unread;
    items.replaceRange(
      0,
      items.length,
      items.map((e) => e.copyWith(isRead: true, readAt: DateTime.now())),
    );
    unread = 0;
    state = NotificationLoadState.markingAllRead;
    notifyListeners();
    try {
      await repository.markAllRead();
      error = null;
      lastError = null;
      offline = false;
      state = items.isEmpty
          ? NotificationLoadState.empty
          : NotificationLoadState.success;
    } catch (e) {
      items
        ..clear()
        ..addAll(old);
      unread = oldUnread;
      _fail(e);
    } finally {
      _allBusy = false;
      notifyListeners();
    }
  }

  void _fail(Object e) {
    final mapped = e is ApiException
        ? mapNotificationError(e)
        : NotificationError.unavailable;
    lastError = mapped;
    offline =
        e is ApiException &&
        (e.kind == ApiErrorKind.network || e.kind == ApiErrorKind.timeout);
    error = notificationErrorMessage(mapped);
    state = mapped == NotificationError.rateLimited
        ? NotificationLoadState.rateLimited
        : NotificationLoadState.networkError;
  }

  @override
  void dispose() {
    _cancel?.cancel();
    for (final u in _unsubscribers) {
      u();
    }
    super.dispose();
  }
}
