import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../features/notifications/controllers/notification_store.dart';
import '../../features/notifications/data/notifications_repo.dart';
import '../deep_link/app_deep_link.dart';
import '../deep_link/deep_link_coordinator.dart';

enum PushPermissionState {
  notDetermined,
  authorized,
  provisional,
  denied,
  unavailable,
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Credential/config bulunmayan flavorlarda inbox ve SignalR çalışmaya devam eder.
  }
}

abstract interface class PushMessagingGateway {
  Stream<String> get tokenRefresh;
  Stream<Map<String, dynamic>> get foregroundMessages;
  Stream<Map<String, dynamic>> get notificationTaps;
  Future<bool> initialize();
  Future<String?> token();
  Future<Map<String, dynamic>?> initialMessage();
  Future<PushPermissionState> permission({bool request = false});
  Future<void> showForeground(Map<String, dynamic> data);
  Future<void> dispose();
}

class FirebasePushMessagingGateway implements PushMessagingGateway {
  final _foreground = StreamController<Map<String, dynamic>>.broadcast();
  final _taps = StreamController<Map<String, dynamic>>.broadcast();
  final _tokens = StreamController<String>.broadcast();
  final _local = FlutterLocalNotificationsPlugin();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _available = false;
  final Set<String> _shown = {};

  @override
  Stream<Map<String, dynamic>> get foregroundMessages => _foreground.stream;
  @override
  Stream<Map<String, dynamic>> get notificationTaps => _taps.stream;
  @override
  Stream<String> get tokenRefresh => _tokens.stream;

  @override
  Future<bool> initialize() async {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Android 13+ bildirim izni iste
      final messaging = FirebaseMessaging.instance;
      try {
        await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (_) {
        // İzin reddedilse de devam et
      }

      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      const channel = AndroidNotificationChannel(
        'hizmetgelsin_updates',
        'HizmetGelsin bildirimleri',
        description: 'Talep, teklif ve randevu güncellemeleri',
        importance: Importance.high,
      );
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (response) {
          final route = response.payload;
          if (route != null) _taps.add({'route': route});
        },
      );
      _subscriptions
        ..add(
          FirebaseMessaging.onMessage.listen((m) => _foreground.add(_data(m))),
        )
        ..add(
          FirebaseMessaging.onMessageOpenedApp.listen(
            (m) => _taps.add(_data(m)),
          ),
        )
        ..add(FirebaseMessaging.instance.onTokenRefresh.listen(_tokens.add));
      _available = true;
    } catch (_) {
      _available = false;
    }
    return _available;
  }

  Map<String, dynamic> _data(RemoteMessage message) => {
    ...message.data,
    if (message.notification?.title != null)
      '_title': message.notification!.title,
    if (message.notification?.body != null) '_body': message.notification!.body,
  };

  @override
  Future<Map<String, dynamic>?> initialMessage() async {
    if (!_available) return null;
    final message = await FirebaseMessaging.instance.getInitialMessage();
    return message == null ? null : _data(message);
  }

  @override
  Future<PushPermissionState> permission({bool request = false}) async {
    if (!_available) return PushPermissionState.unavailable;
    final settings = request
        ? await FirebaseMessaging.instance.requestPermission(
            alert: true,
            badge: true,
            sound: true,
          )
        : await FirebaseMessaging.instance.getNotificationSettings();
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized => PushPermissionState.authorized,
      AuthorizationStatus.provisional => PushPermissionState.provisional,
      AuthorizationStatus.denied => PushPermissionState.denied,
      AuthorizationStatus.notDetermined => PushPermissionState.notDetermined,
    };
  }

  @override
  Future<String?> token() async =>
      _available ? FirebaseMessaging.instance.getToken() : null;

  @override
  Future<void> showForeground(Map<String, dynamic> data) async {
    final id = data['notificationId']?.toString();
    if (id == null || !_shown.add(id)) return;
    final isNewRequest = data['type']?.toString() == 'NewRequest';
    await _local.show(
      id: id.hashCode,
      title: data['_title']?.toString() ?? 'Yeni bildirim',
      body: data['_body']?.toString() ?? 'Uygulamada yeni bir gelişme var.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'hizmetgelsin_updates',
          'HizmetGelsin Bildirimleri',
          channelDescription: 'Talep, teklif ve randevu güncellemeleri',
          importance: Importance.high,
          priority: Priority.high,
          color: Color(0xFF111111),
          icon: '@mipmap/ic_launcher',
          showWhen: true,
          enableVibration: isNewRequest,
          playSound: isNewRequest,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: isNewRequest,
        ),
      ),
      payload: data['route']?.toString(),
    );
  }

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _foreground.close();
    await _taps.close();
    await _tokens.close();
  }
}

class PushService {
  PushService({
    PushMessagingGateway? gateway,
    NotificationsRepository? repository,
    FlutterSecureStorage? storage,
    Future<String> Function()? deviceIdProvider,
  }) : gateway = gateway ?? FirebasePushMessagingGateway(),
       repository = repository ?? NotificationsRepo.instance,
       _storage = storage ?? const FlutterSecureStorage(),
       _deviceIdProvider = deviceIdProvider;

  final PushMessagingGateway gateway;
  final NotificationsRepository repository;
  final FlutterSecureStorage _storage;
  final Future<String> Function()? _deviceIdProvider;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  DeepLinkCoordinator? _deepLinks;
  String? _userId;
  String? _registeredToken;
  String? _deviceId;
  bool _disposed = false;

  Future<void> initialize(DeepLinkCoordinator deepLinks) async {
    _deepLinks = deepLinks;
    if (!await gateway.initialize() || _disposed) return;
    _subscriptions
      ..add(gateway.tokenRefresh.listen((token) => _register(token)))
      ..add(
        gateway.foregroundMessages.listen((data) async {
          if (_disposed) return;
          await NotificationStore.instance.refresh();
          await gateway.showForeground(data);
        }),
      )
      ..add(gateway.notificationTaps.listen(_open));
    // Token'ı al ve kaydet (gecikmeli, Firebase yeni initialize oldu)
    if (_userId != null) {
      // Token hemen alınamayabilir — birkaç saniye içinde tekrar dene
      await _tryRegisterToken();
      Future.delayed(const Duration(seconds: 2), () => _tryRegisterToken());
      Future.delayed(const Duration(seconds: 5), () => _tryRegisterToken());
    }
    final initial = await gateway.initialMessage();
    if (initial != null) await _open(initial);
  }

  Future<void> bindUser(String userId) async {
    if (_disposed) return;
    final changedUser = _userId != null && _userId != userId;
    if (changedUser) {
      await unregister();
      _registeredToken = null;
    }
    _userId = userId;
    NotificationStore.instance.bindSession(userId);
    // Token'ı kaydet — başarısız olursa 2 ve 5 saniye sonra tekrar dene
    await _tryRegisterToken();
    if (!changedUser && _registeredToken == null) {
      // Kullanıcı değişmediyse ve token alınamadıysa gecikmeli tekrar dene
      Future.delayed(const Duration(seconds: 3), () => _tryRegisterToken());
    }
  }

  Future<void> _tryRegisterToken() async {
    if (_disposed || _userId == null) return;
    try {
      final token = await gateway.token();
      // ignore: avoid_print
      print('### FCM TOKEN: ${token != null ? token.substring(0, token.length.clamp(0, 20)) + '...' : 'NULL'}');
      if (token != null && token.isNotEmpty) {
        await _register(token);
        // ignore: avoid_print
        print('### FCM REGISTERED for userId=$_userId');
      }
    } catch (e) {
      // ignore: avoid_print
      print('### FCM REGISTER ERROR: $e');
    }
  }

  Future<void> _register(String token) async {
    if (_userId == null || token.isEmpty || token == _registeredToken) return;
    try {
      final deviceId = await _getDeviceId();
      await repository.registerDevice(
        platform: Platform.isIOS ? 'ios' : 'android',
        token: token,
        deviceId: deviceId,
      );
      _registeredToken = token;
    } catch (_) {
      // Ağ hatası vb. durumlarda sessizce devam et
    }
  }

  Future<String> _getDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    if (_deviceIdProvider != null) return _deviceId = await _deviceIdProvider();
    const key = 'push_device_id_v1';
    _deviceId = await _storage.read(key: key);
    _deviceId ??= const Uuid().v4();
    await _storage.write(key: key, value: _deviceId);
    return _deviceId!;
  }

  Future<void> unregister() async {
    try {
      if (_deviceId != null || _userId != null) {
        await repository.unregisterDevice(await _getDeviceId());
      }
    } catch (_) {
      // Local logout must never depend on network availability.
    } finally {
      _userId = null;
      _registeredToken = null;
      NotificationStore.instance.clearSession();
    }
  }

  Future<void> _open(Map<String, dynamic> data) async {
    final route = data['route']?.toString();
    if (route == null || _disposed) return;
    await _deepLinks?.open(route, source: DeepLinkSource.notification);
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await gateway.dispose();
  }
}
