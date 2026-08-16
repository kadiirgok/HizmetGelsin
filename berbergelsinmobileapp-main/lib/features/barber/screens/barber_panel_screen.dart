import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/services/online_foreground_service.dart';
import '../../../core/signalr/signalr_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_bottom_navigation.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../auth/models/app_user.dart';
import '../data/barber_customer_model.dart';
import '../../map/data/barbers_repo.dart';
import '../../requests/data/requests_repo.dart';
import '../../requests/controllers/request_submission.dart';
import '../../requests/screens/my_requests_screen.dart'
    show requestStatusLabel, requestStatusColor, formatDateTime;
import '../../requests/widgets/rating_dialog.dart';
import '../domain/barber_profile_completion_input.dart';
import '../utils/barber_profile_completion.dart';
import 'barber_profile_screen.dart';
import 'business_reviews_screen.dart';
import '../../map/screens/client_barber_detail_screen.dart';
import '../data/business_working_hours.dart';
import '../widgets/profile/working_hours_editor.dart';
import '../../notifications/widgets/notification_button.dart';
part '../widgets/home/business_home_content.dart';
part '../widgets/home/business_home_compact_request_tile.dart';
part '../widgets/home/business_home_focus.dart';
part '../widgets/home/business_home_header.dart';
part '../widgets/home/business_home_hero.dart';
part '../widgets/home/business_home_metric_grid.dart';
part '../widgets/home/business_home_performance.dart';
part '../widgets/home/business_home_quick_actions.dart';
part '../widgets/home/business_home_reviews.dart';
part '../widgets/home/business_home_section.dart';
part '../widgets/home/business_home_states.dart';
part '../widgets/home/business_home_tip.dart';
part '../widgets/home/business_home_today_summary.dart';
part '../widgets/home/business_home_upcoming.dart';

/// İşletme paneli: çevrimiçi durumu + canlı konum yayını + randevu yaşam döngüsü.
class BarberPanelScreen extends StatefulWidget {
  const BarberPanelScreen({super.key});

  @override
  State<BarberPanelScreen> createState() => _BarberPanelScreenState();
}

class _BarberPanelScreenState extends State<BarberPanelScreen>
    with WidgetsBindingObserver {
  bool _isOnline = false;
  bool _busy = false;
  BusinessDashboard? _dashboard;
  Map<String, dynamic>? _profile;
  Uint8List? _logoBytes;
  bool _loadingLogo = false;
  List<ServiceRequestModel>? _requests;
  List<BarberCustomerModel>? _customers;
  List<BarberReview> _reviews = const [];
  String? _loadError;
  bool _isInitialLoading = true;
  bool _isRefreshing = false;
  String? _profileError;
  String? _dashboardError;
  String? _requestsError;
  String? _customersError;
  String? _reviewsError;
  Timer? _signalRRefreshDebounce;
  bool _loadInProgress = false;
  bool _reloadRequestedWhileBusy = false;
  StreamSubscription<Position>? _positionSub;
  DateTime _lastPublish = DateTime.fromMillisecondsSinceEpoch(0);
  final _unsubscribers = <void Function()>[];
  int _selectedTab = 0;
  String _appointmentSearch = '';
  String _appointmentFilter = 'all';
  String _appointmentView = 'day';
  String _customerSearch = '';
  String _customerFilter = 'all';
  DateTime? _appointmentDate;
  final _profileController = BarberProfileController();
  final ScrollController _homeScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    for (final event in [
      'NewRequest',
      'RequestUpdated',
      'RatingReceived',
    ]) {
      _unsubscribers.add(
        SignalRService.instance.on(event, (args) {
          if (event == 'NewRequest' && mounted) {
            final payload = args?.firstOrNull;
            if (payload is Map) {
              final requestId = payload['requestId']?.toString();
              if (requestId != null) _showNewRequestSheet(requestId);
            }
          }
          _scheduleSignalRRefresh();
        }),
      );
    }

    // Foreground service: bildirim toggle'ını dinle
    OnlineForegroundService.initialize();
    final toggleSub = OnlineForegroundService.toggleStream.stream.listen((online) {
      if (mounted && !online) {
        // Kullanıcı bildirimden "Çevrimdışı Yap" butonuna bastı
        _toggleOnline(false);
      }
    });
    _unsubscribers.add(() => toggleSub.cancel());

    // Uygulama açıldığında bekleyen toggle var mı kontrol et
    OnlineForegroundService.consumeToggle().then((toggle) {
      if (toggle == false && mounted) {
        _toggleOnline(false);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _homeScrollController.dispose();
    for (final unsub in _unsubscribers) {
      unsub();
    }
    _signalRRefreshDebounce?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }

  bool get _hasActiveTrip =>
      _requests?.any((r) => r.status == 'OnTheWay' || r.status == 'Started') ??
      false;

  Future<void> _load() async {
    if (_loadInProgress) {
      _reloadRequestedWhileBusy = true;
      return;
    }
    _loadInProgress = true;
    final initialLoad =
        _profile == null &&
        _dashboard == null &&
        _requests == null &&
        _customers == null;
    if (mounted) {
      setState(() {
        _isInitialLoading = initialLoad;
        _isRefreshing = true;
        _loadError = null;
      });
    }
    try {
      // 4 bağımsız çağrı paralel — ~200ms yerine ~800ms+ beklemeyi önlüyor
      await Future.wait([
        BarbersRepo.instance.myProfile().then((p) {
          final online = p['isOnline'] as bool? ?? false;
          if (mounted) setState(() { _profile = p; _isOnline = online; _profileError = null; });
          // Çevrimiçi ise kalıcı bildirimi başlat (ilk yükleme / resume)
          if (online) {
            final pending = _requests?.where((r) => r.status == 'Pending').length ?? 0;
            final todayEarning = _dashboard?.todayRevenue ?? 0;
            OnlineForegroundService.start(pendingCount: pending, todayEarning: todayEarning);
          }
        }).catchError((_) {
          if (mounted) setState(() => _profileError = 'İşletme bilgileri yüklenemedi');
        }),
        BarbersRepo.instance.myDashboard().then((d) {
          if (mounted) setState(() { _dashboard = d; _dashboardError = null; });
        }).catchError((_) {
          if (mounted) setState(() => _dashboardError = 'Performans verileri yüklenemedi');
        }),
        RequestsRepo.instance.mine().then((p) {
          if (mounted) setState(() { _requests = p.items; _requestsError = null; });
        }).catchError((_) {
          if (mounted) setState(() => _requestsError = 'İşlemler yüklenemedi');
        }),
        BarbersRepo.instance.myCustomers().then((page) {
          if (mounted) setState(() { _customers = page.items; _customersError = null; });
        }).catchError((_) {
          if (mounted) setState(() => _customersError = 'Müşteriler yüklenemedi');
        }),
      ]);

      final profileId = _profile?['barberProfileId'] as String?;
      if (profileId != null && profileId.isNotEmpty) {
        if (!_loadingLogo) {
          _loadLogo(profileId);
        }
      }
      // Reviews via dedicated endpoint (detail/{id} bu rolde yok)
      try {
        final reviewsPage = await BarbersRepo.instance.myReviews();
        if (mounted) {
          setState(() {
            _reviews = mergeReviewsByCustomer(reviewsPage.items);
            _reviewsError = null;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _reviewsError = 'Yorumlar yüklenemedi');
      }
      // Çevrimiçi veya aktif yol varsa konum akışı çalışmalı
      if ((_isOnline || _hasActiveTrip) && _positionSub == null) {
        _startLocationStream();
      }
    } catch (_) {
      if (mounted) setState(() => _loadError = 'Bilgiler alınamadı');
    } finally {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
          _isRefreshing = false;
        });
      }
      _loadInProgress = false;
      if (_reloadRequestedWhileBusy && mounted) {
        _reloadRequestedWhileBusy = false;
        _scheduleSignalRRefresh();
      }
    }
  }

  Future<void> _loadRequests() async {
    try {
      final page = await RequestsRepo.instance.mine();
      if (mounted) {
        setState(() {
          _requests = page.items;
          _requestsError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _requestsError = 'İşlemler yüklenemedi');
      }
    }
  }

  Future<void> _loadCustomers() async {
    try {
      final page = await BarbersRepo.instance.myCustomers();
      if (mounted) {
        setState(() {
          _customers = page.items;
          _customersError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _customersError = 'Müşteriler yüklenemedi');
      }
    }
  }

  Future<void> _showNewRequestSheet(String requestId) async {
    try {
      final r = await RequestsRepo.instance.detail(requestId);
      if (!mounted || r == null) return;
      showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
                child: const Icon(Icons.person, size: 36, color: AppColors.primary),
              ),
              const SizedBox(height: 12),
              Text(r.clientName ?? 'Müşteri', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
              const SizedBox(height: 4),
              Text(r.items.map((i) => i.serviceName).join(', '), style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${r.totalPrice.toStringAsFixed(0)} TL', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 28)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _act(() => RequestsRepo.instance.reject(r.id, idempotencyKey: newRequestUuid()));
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade200),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Reddet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _act(() => RequestsRepo.instance.accept(r.id, idempotencyKey: newRequestUuid()));
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: AppColors.success,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Kabul Et', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> _loadLogo(String profileId) async {
    _loadingLogo = true;
    try {
      final bytes = await BarbersRepo.instance.logoBytes(profileId);
      if (mounted) {
        setState(() {
          _logoBytes = Uint8List.fromList(bytes);
        });
      }
    } catch (_) {
      // logo yok
    } finally {
      _loadingLogo = false;
    }
  }

  void _scheduleSignalRRefresh() {
    _signalRRefreshDebounce?.cancel();
    _signalRRefreshDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      if (_loadInProgress) {
        _reloadRequestedWhileBusy = true;
        return;
      }
      // SignalR event'inde sadece istekleri yenile — profil/dashboard değişmez
      try {
        final page = await RequestsRepo.instance.mine();
        if (mounted) {
          setState(() { _requests = page.items; _requestsError = null; });
          // Kalıcı bildirimi güncelle (yeni talep sayısı)
          if (_isOnline) {
            final pending = _requests?.where((r) => r.status == 'Pending').length ?? 0;
            final todayEarning = _dashboard?.todayRevenue ?? 0;
            OnlineForegroundService.update(pendingCount: pending, todayEarning: todayEarning);
          }
        }
      } catch (_) {}
    });
  }

  Future<bool> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (!mounted) return false;
      _showLocationSettingsDialog(
        title: 'Konum servisi kapalı',
        message: 'Çevrimiçi olmak için cihazınızın konum servisini açın.',
        openSettings: Geolocator.openLocationSettings,
      );
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return false;
      if (permission == LocationPermission.deniedForever) {
        _showLocationSettingsDialog(
          title: 'Konum izni gerekli',
          message:
              'Konum izni kalıcı olarak reddedilmiş. İzni uygulama ayarlarından açın.',
          openSettings: Geolocator.openAppSettings,
        );
      } else {
        _snack('Bu işlem için konum izni gerekli.', error: true);
      }
      return false;
    }
    return true;
  }

  Future<void> _showLocationSettingsDialog({
    required String title,
    required String message,
    required Future<bool> Function() openSettings,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              openSettings();
            },
            child: const Text('Ayarları Aç'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleOnline(bool value) async {
    final previousValue = _isOnline;
    setState(() => _busy = true);
    try {
      if (value) {
        if (!await _ensureLocationPermission()) return;
        final pos = await Geolocator.getCurrentPosition();
        await BarbersRepo.instance.updateLocation(pos.latitude, pos.longitude);
        await BarbersRepo.instance.setOnline(true);
        if (mounted) setState(() => _isOnline = true);
        _startLocationStream();
        // Kalıcı bildirim: çevrimiçi durum foreground service (talep + kazanç bilgisiyle)
        final pending = _requests?.where((r) => r.status == 'Pending').length ?? 0;
        final todayEarning = _dashboard?.todayRevenue ?? 0;
        OnlineForegroundService.start(pendingCount: pending, todayEarning: todayEarning);
        // SignalR bildirimi — başarısız olsa da API'ye kaydedildi
        try { await SignalRService.instance.invoke('SetOnline', args: [true]); } catch (_) {}
      } else {
        if (!_hasActiveTrip) {
          _positionSub?.cancel();
          _positionSub = null;
        }
        await BarbersRepo.instance.setOnline(false);
        if (mounted) setState(() => _isOnline = false);
        // Kalıcı bildirimi kaldır
        OnlineForegroundService.stop();
        try { await SignalRService.instance.invoke('SetOnline', args: [false]); } catch (_) {}
      }
    } catch (_) {
      if (mounted) setState(() => _isOnline = previousValue);
      if (previousValue && _positionSub == null) _startLocationStream();
      _snack('Çevrimiçi durum güncellenemedi. Tekrar deneyin.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Konum akışı: Android'de foreground service bildirimiyle çalışır,
  /// uygulama arka plana alınsa da takip sürer (yoldayken kurye gibi).
  void _startLocationStream() {
    _positionSub?.cancel();

    late final LocationSettings settings;
    if (!kIsWeb && Platform.isAndroid) {
      // foregroundNotificationConfig KALDIRILDI — OnlineForegroundService
      // zaten kalıcı foreground notification gösteriyor. İkinci bildirim
      // çakışmasını önlemek için geolocator'ın kendi servisini kullanmıyoruz.
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
      );
    } else if (!kIsWeb && Platform.isIOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
      );
    }

    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) {
          final now = DateTime.now();
          // Yolda: 5 sn'de bir; normal çevrimiçi: 10 sn'de bir yayınla
          final interval = _hasActiveTrip ? 5 : 10;
          if (now.difference(_lastPublish).inSeconds >= interval) {
            _lastPublish = now;
            SignalRService.instance.invoke(
              'UpdateLocation',
              args: [pos.latitude, pos.longitude],
            );
          }
        });
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        ),
      );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Çıkış Yap'),
        content: const Text('Hesabınızdan çıkış yapmak istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<AuthCubit>().logout();
  }

  void _openProfileSettingsFromHome() {
    setState(() => _selectedTab = 3);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _profileController.showProfileSettings();
    });
  }

  void _openServicesFromHome() {
    setState(() => _selectedTab = 3);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _profileController.showServices();
    });
  }

  void _openWorkingHoursFromHome() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkingHoursEditorScreen(
          workingHours: _parseWorkingHours(),
          onSave: (hours) async {
            await BarbersRepo.instance.updateProfile(
              sharePhone: true,
              acceptsOffers: true,
              acceptsUrgentRequests: true,
              serviceRadiusKm: _profile?['serviceRadiusKm'] as int? ?? 10,
              workingHours: hours.map((h) => h.toJson()).toList(),
            );
            if (mounted) _load();
          },
        ),
      ),
    );
  }

  List<BusinessWorkingDay> _parseWorkingHours() {
    final raw = _profile?['workingHours'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(raw);
        return list.map((e) => BusinessWorkingDay.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }
    return BusinessWorkingDay.defaultList();
  }

  void _openCustomerPreviewFromHome() {
    final profileId = _profile?['barberProfileId'] as String?;
    if (profileId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClientBarberDetailScreen(barberProfileId: profileId),
      ),
    );
  }

  void _openReviewsTab() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BusinessReviewsScreen()),
    );
  }

  bool _isSameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  DateTime _selectedAppointmentDate() {
    final selected = _appointmentDate ?? DateTime.now();
    return DateTime(selected.year, selected.month, selected.day);
  }

  DateTime _startOfWeek(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  DateTime _startOfMonth(DateTime date) => DateTime(date.year, date.month, 1);

  bool _isWithinAppointmentView(DateTime requestedTime) {
    final selected = _selectedAppointmentDate();
    final requestDate = DateTime(
      requestedTime.year,
      requestedTime.month,
      requestedTime.day,
    );
    return switch (_appointmentView) {
      'week' =>
        !requestDate.isBefore(_startOfWeek(selected)) &&
            requestDate.isBefore(
              _startOfWeek(selected).add(const Duration(days: 7)),
            ),
      'month' =>
        !requestDate.isBefore(_startOfMonth(selected)) &&
            requestDate.isBefore(
              DateTime(selected.year, selected.month + 1, 1),
            ),
      _ => _isSameDay(requestDate, selected),
    };
  }

  String _appointmentMonthName(int month) => switch (month) {
    1 => 'Ocak',
    2 => 'Şubat',
    3 => 'Mart',
    4 => 'Nisan',
    5 => 'Mayıs',
    6 => 'Haziran',
    7 => 'Temmuz',
    8 => 'Ağustos',
    9 => 'Eylül',
    10 => 'Ekim',
    11 => 'Kasım',
    _ => 'Aralık',
  };

  String _appointmentListTitle() {
    final selected = _selectedAppointmentDate();
    final now = DateTime.now();
    return switch (_appointmentView) {
      'week' =>
        _startOfWeek(selected) == _startOfWeek(now)
            ? 'Bu haftaki randevular'
            : 'Seçili haftanın randevuları',
      'month' =>
        selected.year == now.year && selected.month == now.month
            ? 'Bu ayki randevular'
            : '${_appointmentMonthName(selected.month)} randevuları',
      _ =>
        _isSameDay(selected, now)
            ? 'Bugünkü randevular'
            : '${selected.day} ${_appointmentMonthName(selected.month)} randevuları',
    };
  }

  String _appointmentEmptyText() => switch (_appointmentView) {
    'week' => 'Bu hafta için randevu yok',
    'month' => 'Bu ay için randevu yok',
    _ => 'Bugün için randevu yok',
  };

  Future<void> _selectAppointmentDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _appointmentDate ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
      helpText: 'Randevu tarihini seçin',
      cancelText: 'Vazgeç',
      confirmText: 'Seç',
    );
    if (selected != null && mounted) {
      setState(() => _appointmentDate = selected);
    }
  }

  Future<bool> _act(Future<void> Function() action) async {
    if (_busy) return false;
    if (mounted) setState(() => _busy = true);
    _snack('İşleniyor...');
    var succeeded = false;
    try {
      await action();
      succeeded = true;
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      _snack('Bir hata oluştu. Lütfen tekrar deneyin.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (succeeded) {
      // Sadece istekleri yenile — profil/dashboard/değişmez
      await _loadRequests();
      _snack('İşlem başarılı.');
    }
    return succeeded;
  }

  Future<void> _rateClient(ServiceRequestModel r) async {
    final result = await showRatingDialog(
      context,
      title: 'Müşteriyi Puanla',
      subtitle:
          '${r.clientName?.isNotEmpty == true ? r.clientName : "Müşteri"} için deneyiminizi değerlendirin.',
    );
    if (result == null) return;
    final succeeded = await _act(
      () => RequestsRepo.instance.rate(r.id, result.score, result.comment),
    );
    if (succeeded) _snack('Değerlendirmeniz kaydedildi.');
  }

  void _showDetail(ServiceRequestModel r) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) => _AppointmentDetailSheet(
        request: r,
        onAccept: r.status == 'Pending'
            ? () {
                Navigator.pop(context);
                _act(() => RequestsRepo.instance.accept(r.id, idempotencyKey: newRequestUuid()));
              }
            : null,
        onReject: r.status == 'Pending'
            ? () {
                Navigator.pop(context);
                _act(() => RequestsRepo.instance.reject(r.id, idempotencyKey: newRequestUuid()));
              }
            : null,
        onComplete: r.status == 'Accepted' || r.status == 'OnTheWay' || r.status == 'Started'
            ? () {
                Navigator.pop(context);
                _showCompleteCodeDialog(r);
              }
            : null,
        onWay: r.status == 'Accepted'
            ? () {
                Navigator.pop(context);
                _act(() => RequestsRepo.instance.onTheWay(
                    r.id, idempotencyKey: newRequestUuid()));
              }
            : null,
        onStart: r.status == 'Accepted' || r.status == 'OnTheWay'
            ? () {
                Navigator.pop(context);
                _act(() => RequestsRepo.instance.start(
                    r.id, idempotencyKey: newRequestUuid()));
              }
            : null,
        onRate: r.status == 'Completed' && r.canRate
            ? () {
                Navigator.pop(context);
                _rateClient(r);
              }
            : null,
        onCancel: r.status == 'Accepted' || r.status == 'OnTheWay' || r.status == 'Started'
            ? () {
                Navigator.pop(context);
                _cancelAndReload(r);
              }
            : null,
        onEditNote: () {
          Navigator.pop(context);
          _editRequestNote(r);
        },
      ),
    );
  }

  Future<void> _cancelAndReload(ServiceRequestModel r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('İptal Et'),
        content: const Text('Bu işlemi iptal etmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('İptal Et'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final succeeded = await _act(() => RequestsRepo.instance.cancelRequest(r.id, reasonCode: 'other', idempotencyKey: newRequestUuid()));
    if (succeeded) _snack('İşlem iptal edildi.');
  }

  Future<void> _showCompleteCodeDialog(ServiceRequestModel r) async {
    final codeController = TextEditingController();
    final result = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.vpn_key_rounded, color: AppColors.success, size: 32),
            ),
            const SizedBox(height: 16),
            const Text('İşlem Tamamlama',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -0.5)),
            const SizedBox(height: 6),
            Text('${r.clientName ?? "Müşteri"} ile buluşmayı onaylamak için\ndoğrulama kodunu girin.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
            const SizedBox(height: 24),
            TextField(
              controller: codeController,
              autofocus: true,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 8),
              decoration: InputDecoration(
                hintText: '____',
                hintStyle: TextStyle(color: Colors.grey.shade300, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 8),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.primary, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('İşlemi Tamamla',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç', style: TextStyle(color: AppTheme.textSecondary)),
              ),
            ),
          ],
        ),
      ),
    );
    if (result != true || !mounted) return;
    final code = codeController.text.trim().toUpperCase();
    final succeeded = await _act(() async {
      await RequestsRepo.instance.verifyCode(r.id, code, idempotencyKey: newRequestUuid());
    });
    if (succeeded) {
      _snack('İşlem tamamlandı.');
    }
  }

  ServiceRequestModel? _requestForCustomer(BarberCustomerModel customer) {
    final requests = _requests ?? const <ServiceRequestModel>[];
    final recentJobs = [...customer.recentJobs]
      ..sort((a, b) => b.visitDate.compareTo(a.visitDate));
    for (final job in recentJobs) {
      for (final request in requests) {
        if (request.id == job.requestId) return request;
      }
    }
    return null;
  }

  void _showCustomerDetail(BarberCustomerModel customer) {
    final latestRequest = _requestForCustomer(customer);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) => _CustomerDetailSheet(
        customer: customer,
        onOpenLastJob: latestRequest == null
            ? null
            : () {
                Navigator.pop(context);
                _showDetail(latestRequest);
              },
      ),
    );
  }

  Future<void> _editRequestNote(ServiceRequestModel request) async {
    final controller = TextEditingController(text: request.addressNote ?? '');
    final note = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Randevu Notu'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Müşteri veya randevu için özel not yazın...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (note == null) return;
    await _act(() => RequestsRepo.instance.updateNote(request.id, note));
    if (mounted) _snack('Randevu notu kaydedildi.');
  }

  void _showCustomerFilters() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Müşteri filtresi',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            for (final item in const [
              ('all', 'Tüm müşteriler'),
              ('active', 'Aktif müşteriler'),
              ('new', 'İlk kez gelen'),
              ('vip', 'VIP müşteriler'),
            ])
              ListTile(
                leading: Icon(
                  _customerFilter == item.$1
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(item.$2),
                onTap: () {
                  setState(() => _customerFilter = item.$1);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13.5,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
        ),
      ],
    ),
  );

  Widget _buildBusinessHome() {
    final user = context.watch<AuthCubit>().state.user;
    final profile = _profile ?? const <String, dynamic>{};
    final services = profile['services'] as List? ?? const [];
    final photos = profile['photos'] as List? ?? const [];
    final profileScore = _calculateProfileScore(profile, services, photos);

    return BusinessHomeContent(
      scrollController: _homeScrollController,
      user: user,
      profile: _profile,
      dashboard: _dashboard,
      requests: _requests,
      reviews: _reviews,
      isOnline: _isOnline,
      busy: _busy,
      loadError: _loadError,
      isInitialLoading: _isInitialLoading,
      isRefreshing: _isRefreshing,
      profileError: _profileError,
      dashboardError: _dashboardError,
      requestsError: _requestsError,
      reviewsError: _reviewsError,
      profileScore: profileScore,
      serviceCount: services.length,
      photoCount: photos.length,
      onRefresh: _load,
      onToggleOnline: _toggleOnline,
      onOpenProfile: () => setState(() => _selectedTab = 3),
      onOpenAppointments: () => setState(() => _selectedTab = 1),
      onOpenCustomers: () => setState(() => _selectedTab = 2),
      onOpenServices: _openServicesFromHome,
      onOpenProfileSettings: _openProfileSettingsFromHome,
      onShowDetail: _showDetail,
    );
  }

  Widget _buildPremiumCustomers() {
    final customers = _customers ?? const <BarberCustomerModel>[];
    final totalRevenue = customers.fold<double>(
      0,
      (sum, customer) => sum + customer.totalSpent,
    );
    final completedJobCount = customers.fold<int>(
      0,
      (sum, customer) => sum + customer.completedJobCount,
    );
    final averageValue = completedJobCount == 0
        ? 0.0
        : totalRevenue / completedJobCount;
    final normalizedCustomerSearch = _customerSearch.trim().toLowerCase();
    final filteredCustomers = customers.where((customer) {
      final matchesSearch =
          normalizedCustomerSearch.isEmpty ||
          customer.displayName.toLowerCase().contains(
            normalizedCustomerSearch,
          ) ||
          customer.preferredServicesText.toLowerCase().contains(
            normalizedCustomerSearch,
          );
      final matchesFilter = switch (_customerFilter) {
        'active' => customer.isActive,
        'new' => customer.completedJobCount == 1,
        'vip' => customer.isVip,
        _ => true,
      };
      return matchesSearch && matchesFilter;
    }).toList();
    final repeatCustomers = customers
        .where((customer) => customer.completedJobCount > 1)
        .length;
    final pendingFollowUps = customers
        .where(
          (customer) =>
              DateTime.now().difference(customer.lastVisit).inDays > 30,
        )
        .length;
    final isInitialCustomersLoading = _isInitialLoading && _customers == null;
    final hasCustomerError = _customersError != null && _customers == null;
    final hasFatalCustomerError = hasCustomerError;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Müşteriler',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
              ),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (isInitialCustomersLoading)
            const _BarberCustomersInitialLoading()
          else if (hasFatalCustomerError)
            _BarberCustomersError(onRetry: _load)
          else ...[
            TextField(
              onChanged: (value) => setState(() => _customerSearch = value),
              decoration: InputDecoration(
                hintText: 'Müşteri ara...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: _showCustomerFilters,
                  icon: const Icon(Icons.tune_rounded),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _CustomerFilterSegment(
              value: _customerFilter,
              onChanged: (value) => setState(() => _customerFilter = value),
            ),
            const SizedBox(height: 16),
            _CustomerInsightMetrics(
              totalCustomers: customers.length,
              repeatCustomers: repeatCustomers,
              pendingFollowUps: pendingFollowUps,
            ),
            const SizedBox(height: 18),
            if (_customersError != null && _customers != null) ...[
              _BarberCustomersInlineError(onRetry: _load),
              const SizedBox(height: 12),
            ],
            if (hasCustomerError)
              Column(
                children: [
                  _DashboardEmpty(
                    icon: Icons.error_outline,
                    text: _customersError ?? 'Müşteriler yüklenemedi',
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tekrar Dene'),
                  ),
                ],
              )
            else if (customers.isEmpty)
              const _BarberCustomersEmpty(
                icon: Icons.people_outline,
                text:
                    'Henüz müşteri yok\nTamamlanan işlemlerden sonra müşteriler burada görünecek.',
              )
            else if (filteredCustomers.isEmpty)
              const _BarberCustomersFilteredEmpty(
                icon: Icons.people_outline,
                text: 'Bu filtreyle müşteri bulunamadı.',
              )
            else
              ...filteredCustomers.map(
                (customer) => _PremiumCustomerProfileCard(
                  customer: customer,
                  onTap: () => _showCustomerDetail(customer),
                ),
              ),
            const SizedBox(height: 18),
            _CustomerInsightsCard(
              customers: customers,
              totalRevenue: totalRevenue,
              averageValue: averageValue,
              reviews: _reviews,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showAppointmentsInitialLoading =
        _isInitialLoading &&
        _requests == null &&
        _requestsError == null;
    final showAppointmentsFatalError =
        _requests == null &&
        _requestsError != null;
    final showAppointmentsEmpty =
        _requests != null &&
        _requestsError == null &&
        _requests!.isEmpty;
    final selectedAppointmentDate = _selectedAppointmentDate();
    final normalizedSearch = _appointmentSearch.trim().toLowerCase();
    final visibleRequests = (_requests ?? const <ServiceRequestModel>[]).where((
      r,
    ) {
      final matchesSearch =
          normalizedSearch.isEmpty ||
          (r.clientName ?? '').toLowerCase().contains(normalizedSearch) ||
          r.items.any(
            (item) => item.serviceName.toLowerCase().contains(normalizedSearch),
          );
      final matchesFilter = switch (_appointmentFilter) {
        'active' => r.isActive,
        'completed' => r.status == 'Completed',
        'cancelled' =>
            r.status == 'Cancelled' || r.status == 'Rejected',
        _ => true,
      };
      final matchesDate = _isWithinAppointmentView(r.requestedTime);
      return matchesSearch && matchesFilter && matchesDate;
    }).toList();
    final pending = visibleRequests
        .where((r) => r.status == 'Pending')
        .toList();
    final upcoming = visibleRequests
        .where((r) => r.status == 'Accepted')
        .toList();
    final onTheWay = visibleRequests
        .where((r) => r.status == 'OnTheWay')
        .toList();
    final started = visibleRequests
        .where((r) => r.status == 'Started')
        .toList();
    final completed = visibleRequests
        .where((r) => r.status == 'Completed')
        .take(10)
        .toList();

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Text(switch (_selectedTab) {
          0 => 'Ana Sayfa',
          1 => 'İşlemler',
          2 => 'Müşteriler',
          _ => 'İşletme Profili',
        }),
        actions: [
          const NotificationButton(),
          if (_selectedTab == 3)
            PopupMenuButton<String>(
              tooltip: 'İşletme menüsü',
              icon: const Icon(Icons.menu),
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              onSelected: (value) {
                if (value == 'logout') {
                  _logout();
                } else if (value == 'services') {
                  _profileController.showServices();
                } else {
                  _profileController.showProfileSettings();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'profile',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.tune),
                    title: Text('Profil Ayarları'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'services',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.storefront_outlined),
                    title: Text('Hizmetler'),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'logout',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.logout_rounded, color: AppColors.error),
                    title: Text('Çıkış Yap',
                        style: TextStyle(color: AppColors.error)),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: IndexedStack(
        index: _selectedTab,
        children: [
          _buildBusinessHome(),
          RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'İşlemler',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.8,
                              height: 1.05,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'İş akışınızı yönetin, müşterilere hızlı dönüş yapın.',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _load,
                      tooltip: 'Yenile',
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _AppointmentViewSegment(
                  value: _appointmentView,
                  onChanged: (value) =>
                      setState(() => _appointmentView = value),
                  onCalendar: _selectAppointmentDate,
                ),
                if (_appointmentView != 'month') ...[
                  const SizedBox(height: 14),
                  _AppointmentWeekStrip(
                    selectedDate: selectedAppointmentDate,
                    onSelected: (date) =>
                        setState(() => _appointmentDate = date),
                  ),
                ],
                if (showAppointmentsInitialLoading) ...[
                  const SizedBox(height: 18),
                  const _BarberAppointmentsInitialLoading(),
                ] else if (showAppointmentsFatalError) ...[
                  const SizedBox(height: 18),
                  _BarberAppointmentsInlineError(
                    title: 'İşlemler yüklenemedi',
                    message: 'Bağlantınızı kontrol edip tekrar deneyin.',
                    semanticLabel: 'Randevular yüklenemedi. Tekrar dene.',
                    onRetry: _load,
                  ),
                ] else if (showAppointmentsEmpty) ...[
                  const SizedBox(height: 18),
                  _BarberAppointmentsEmpty(
                    onOpenProfile: () => setState(() => _selectedTab = 3),
                  ),
                ] else ...[
                  const SizedBox(height: 18),
                  if (_requestsError != null) ...[
                    _BarberAppointmentsInlineError(
                      title: 'İşlemler yüklenemedi',
                      message: 'Randevu bilgileri alınırken bir sorun oluştu.',
                      semanticLabel: 'Randevular yüklenemedi. Tekrar dene.',
                      onRetry: _load,
                    ),
                    const SizedBox(height: 10),
                  ],
                  _PremiumAppointmentList(
                    title: _appointmentListTitle(),
                    emptyText: _appointmentEmptyText(),
                    requests: visibleRequests,
                    onTapRequest: _showDetail,
                  ),
                  const SizedBox(height: 14),
                  // Birleşik işlem özeti (HeroCard + Summary tek kartta)
                  _AppointmentUnifiedSummary(
                    pending: pending.length,
                    active: onTheWay.length + started.length + upcoming.length,
                    completed: completed.length,
                    cancelled: visibleRequests
                        .where((r) => r.status == 'Cancelled')
                        .length,
                    rejected: visibleRequests
                        .where((r) => r.status == 'Rejected')
                        .length,
                    todayRevenue: completed
                        .where((r) => _isSameDay(
                            r.completedAt ?? r.requestedTime, DateTime.now()))
                        .fold<double>(0, (s, r) => s + r.totalPrice),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          onChanged: (value) =>
                              setState(() => _appointmentSearch = value),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Müşteri veya hizmet ara',
                            prefixIcon: const Icon(Icons.search),
                            isDense: true,
                          ),
                        ),
                      ),
                      if (_appointmentDate != null) ...[
                        const SizedBox(width: 8),
                        ActionChip(
                          avatar: const Icon(Icons.event, size: 16),
                          label: Text(
                            '${_appointmentDate!.day.toString().padLeft(2, '0')}.${_appointmentDate!.month.toString().padLeft(2, '0')}',
                          ),
                          onPressed: () =>
                              setState(() => _appointmentDate = null),
                        ),
                      ],
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Tarih seç',
                        onPressed: _selectAppointmentDate,
                        icon: const Icon(Icons.calendar_month_outlined),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _AppointmentSegmentedControl(
                    value: _appointmentFilter,
                    items: [
                      _SegmentItem(
                        value: 'all',
                        label: 'Tümü',
                        count: visibleRequests.length,
                      ),
                      _SegmentItem(
                        value: 'active',
                        label: 'Aktif',
                        count:
                            pending.length +
                            upcoming.length +
                            onTheWay.length +
                            started.length,
                      ),
                      _SegmentItem(
                        value: 'completed',
                        label: 'Tamamlanan',
                        count: completed.length,
                      ),
                      _SegmentItem(
                        value: 'cancelled',
                        label: 'İptal & Red',
                        count: visibleRequests
                            .where((r) =>
                                r.status == 'Cancelled' ||
                                r.status == 'Rejected')
                            .length,
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _appointmentFilter = value),
                  ),
                ],
              ],
            ),
          ),
          _buildPremiumCustomers(),
          BarberProfileScreen(
            embedded: true,
            controller: _profileController,
            onOpenReviews: _openReviewsTab,
            initialProfile: _profile,
            initialLogoBytes: _logoBytes,
            onLogoChanged: (bytes) {
              setState(() {
                _logoBytes = bytes;
              });
            },
            onProfileChanged: () {
              _load();
            },
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: _selectedTab,
        onTap: (index) {
          setState(() => _selectedTab = index);
          if (index == 1) {
            // Sadece işlemleri yenile
            _loadRequests();
          } else if (index == 2) {
            _loadCustomers();
          } else if (index != 3) {
            _load();
          }
        },
        items: const [
          AppBottomNavigationItem(
            label: 'Ana Sayfa',
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
          ),
          AppBottomNavigationItem(
            label: 'İşlemler',
            icon: Icons.calendar_month_outlined,
            selectedIcon: Icons.calendar_month,
          ),
          AppBottomNavigationItem(
            label: 'Müşteriler',
            icon: Icons.people_outline,
            selectedIcon: Icons.people,
          ),
          AppBottomNavigationItem(
            label: 'İşletme Profili',
            icon: Icons.storefront_outlined,
            selectedIcon: Icons.storefront,
          ),
        ],
      ),
    );
  }

  int _calculateProfileScore(
    Map<String, dynamic> profile,
    List<dynamic> services,
    List<dynamic> photos,
  ) {
    return BarberProfileCompletion.calculate(
      BarberProfileCompletionInput.fromRawData(
        profile: profile,
        serviceCount: services.length,
        photoCount: photos.length,
        hasLogo: _logoBytes != null,
      ),
    );
  }
}

class _BarberAppointmentsInitialLoading extends StatelessWidget {
  const _BarberAppointmentsInitialLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'İşlemler yükleniyor',
      child: Column(
        children: const [
          _AppointmentLoadingPlaceholder(height: 96),
          SizedBox(height: 10),
          _AppointmentLoadingPlaceholder(height: 82),
          SizedBox(height: 10),
          _AppointmentLoadingPlaceholder(height: 82),
          SizedBox(height: 10),
          _AppointmentLoadingPlaceholder(height: 82),
        ],
      ),
    );
  }
}

class _AppointmentLoadingPlaceholder extends StatelessWidget {
  const _AppointmentLoadingPlaceholder({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppTheme.fieldFill,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFECECEF)),
        ),
      ),
    );
  }
}

class _BarberAppointmentsInlineError extends StatelessWidget {
  const _BarberAppointmentsInlineError({
    required this.title,
    required this.message,
    required this.semanticLabel,
    required this.onRetry,
  });

  final String title;
  final String message;
  final String semanticLabel;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: _PremiumPanelCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.fieldFill,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  color: AppTheme.textSecondary,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: const Text('Tekrar Dene'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarberAppointmentsEmpty extends StatelessWidget {
  const _BarberAppointmentsEmpty({this.onOpenProfile});

  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Henüz randevu yok. İşletmeniz çevrimiçi olduğunda talepler burada görünecek.',
      child: _PremiumPanelCard(
        child: Column(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.calendar_month_outlined,
                  size: 32,
                  color: AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Henüz randevu yok',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Müşteriler sizi keşfettiğinde talepler burada görünecek.\nVitrininizi tamamlayın ve çevrimiçi olun.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            if (onOpenProfile != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onOpenProfile,
                icon: const Icon(Icons.storefront_outlined, size: 18),
                label: const Text('Vitrini Düzenle'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AppointmentDetailSheet extends StatelessWidget {
  const _AppointmentDetailSheet({
    required this.request,
    this.onAccept,
    this.onReject,
    this.onComplete,
    this.onCancel,
    this.onRate,
    this.onEditNote,
    this.onWay,
    this.onStart,
  });

  final ServiceRequestModel request;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;
  final VoidCallback? onRate;
  final VoidCallback? onEditNote;
  final VoidCallback? onWay;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final statusColor = requestStatusColor(request.status);
    final customerName = request.clientName?.trim().isNotEmpty == true
        ? request.clientName!.trim()
        : 'Müşteri';
    final serviceNames = request.items.isEmpty
        ? 'Hizmet'
        : request.items.map((item) => item.serviceName).join(', ');
    final duration = request.items.isEmpty ? 45 : request.items.length * 30;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
              ),
              const Expanded(
                child: Text(
                  'Randevu Detayı',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
              IconButton(
                onPressed: onEditNote,
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PremiumPanelCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppTheme.fieldFill,
                  child: Text(
                    customerName[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customerName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${request.totalPrice.toStringAsFixed(0)} TL · $serviceNames',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (request.clientPhone?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            _PremiumPanelCard(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => launchUrl(Uri.parse('tel:${request.clientPhone}')),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.call_rounded, color: AppColors.success, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Müşteriyi Ara',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(request.clientPhone!,
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          _PremiumPanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusPill(
                  text: requestStatusLabel(request.status),
                  color: statusColor,
                ),
                const SizedBox(height: 18),
                _DetailInfoRow(
                  icon: Icons.calendar_today_outlined,
                  title: _dateOnlyLabel(request.requestedTime),
                  subtitle: _weekdayFullLabel(request.requestedTime.weekday),
                ),
                _DetailInfoRow(
                  icon: Icons.schedule_rounded,
                  title:
                      '${_timeLabel(request.requestedTime)} · $duration dakika',
                  subtitle: 'Randevu saati',
                ),
                _DetailInfoRow(
                  icon: Icons.content_cut_rounded,
                  title: serviceNames,
                  subtitle: 'Hizmet',
                ),
                _DetailInfoRow(
                  icon: Icons.location_on_outlined,
                  title: request.addressNote?.trim().isNotEmpty == true
                      ? request.addressNote!.trim()
                      : 'Müşteri konumu',
                  subtitle: 'Adres / Not',
                ),
                _DetailInfoRow(
                  icon: Icons.payments_outlined,
                  title: '${request.totalPrice.toStringAsFixed(0)} TL',
                  subtitle: 'Ödeme durumu',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _PremiumPanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Randevu Geçmişi',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 12),
                _TimelineRow(
                  active: true,
                  title: 'Randevu oluşturuldu',
                  subtitle: formatDateTime(request.createdAt),
                ),
                if (request.respondedAt != null)
                  _TimelineRow(
                    active: true,
                    title: request.status == 'Rejected'
                        ? 'Reddedildi'
                        : 'Kabul edildi',
                    subtitle: formatDateTime(request.respondedAt!),
                  ),
                if (request.cancelledAt != null &&
                    request.respondedAt != request.cancelledAt)
                  _TimelineRow(
                    active: true,
                    title: 'İptal edildi',
                    subtitle: formatDateTime(request.cancelledAt!),
                  ),
                if (request.onTheWayAt != null)
                  _TimelineRow(
                    active: true,
                    title: 'Yola çıkıldı',
                    subtitle: formatDateTime(request.onTheWayAt!),
                  ),
                if (request.startedAt != null)
                  _TimelineRow(
                    active: true,
                    title: 'Hizmet başladı',
                    subtitle: formatDateTime(request.startedAt!),
                  ),
                if (request.completedAt != null)
                  _TimelineRow(
                    active: true,
                    title: 'Randevu tamamlandı',
                    subtitle: formatDateTime(request.completedAt!),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (onAccept != null || onReject != null) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade200),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    label: const Text('Reddet',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onAccept,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: AppColors.success,
                    ),
                    icon: const Icon(Icons.check_rounded, size: 20),
                    label: const Text('Kabul Et',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ] else if (onComplete != null) ...[
            FilledButton.icon(
              onPressed: onComplete,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                backgroundColor: AppColors.success,
              ),
              icon: const Icon(Icons.vpn_key_rounded),
              label: const Text('Kod Gir — İşlemi Tamamla',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            if (onWay != null || onStart != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (onWay != null) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onWay,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.directions_car_outlined,
                            size: 18),
                        label: const Text('Yola Çıktım',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onStart,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon:
                          const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Başladım',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
            if (onCancel != null) ...[
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.close_rounded, size: 18, color: Colors.red),
                label: const Text('İptal Et', style: TextStyle(color: Colors.red)),
              ),
            ],
          ] else if (onRate != null)
            FilledButton.icon(
              onPressed: onRate,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                backgroundColor: AppColors.warning,
              ),
              icon: const Icon(Icons.star_outline_rounded),
              label: const Text('Müşteriyi Puanla',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          if (request.isActive) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onEditNote,
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Not Ekle'),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailInfoRow extends StatelessWidget {
  const _DetailInfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: AppTheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.active,
    required this.title,
    required this.subtitle,
  });

  final bool active;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: active ? Colors.green.shade600 : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _dateOnlyLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

String _weekdayFullLabel(int weekday) => switch (weekday) {
  DateTime.monday => 'Pazartesi',
  DateTime.tuesday => 'Salı',
  DateTime.wednesday => 'Çarşamba',
  DateTime.thursday => 'Perşembe',
  DateTime.friday => 'Cuma',
  DateTime.saturday => 'Cumartesi',
  _ => 'Pazar',
};

class _AppointmentViewSegment extends StatelessWidget {
  const _AppointmentViewSegment({
    required this.value,
    required this.onChanged,
    required this.onCalendar,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onCalendar;

  @override
  Widget build(BuildContext context) {
    final items = const [('day', 'Gün'), ('week', 'Hafta'), ('month', 'Ay')];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        return Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.fieldFill,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    for (final item in items)
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => onChanged(item.$1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: EdgeInsets.symmetric(
                                vertical: compact ? 9 : 11),
                            decoration: BoxDecoration(
                              color: value == item.$1
                                  ? AppTheme.primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              item.$2,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: value == item.$1
                                    ? Colors.white
                                    : AppTheme.primary,
                                fontWeight: FontWeight.w800,
                                fontSize: compact ? 12.5 : 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onCalendar,
              icon: const Icon(Icons.calendar_month_outlined),
              tooltip: 'Tarih seç',
              visualDensity: VisualDensity.compact,
            ),
          ],
        );
      },
    );
  }
}

class _AppointmentWeekStrip extends StatelessWidget {
  const _AppointmentWeekStrip({
    required this.selectedDate,
    required this.onSelected,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelected;

  String _dayLabel(int weekday) => switch (weekday) {
    DateTime.monday => 'Pzt',
    DateTime.tuesday => 'Sal',
    DateTime.wednesday => 'Çar',
    DateTime.thursday => 'Per',
    DateTime.friday => 'Cum',
    DateTime.saturday => 'Cmt',
    _ => 'Paz',
  };

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = selectedDate.subtract(
      Duration(days: selectedDate.weekday - 1),
    );
    final days = List.generate(7, (index) => start.add(Duration(days: index)));
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 4.0;
        final itemWidth = (constraints.maxWidth - gap * 6) / 7;
        final compact = constraints.maxWidth < 360;
        return SizedBox(
          height: compact ? 72 : 82,
          child: Row(
            children: [
              for (var index = 0; index < days.length; index++) ...[
                if (index > 0) SizedBox(width: gap),
                Expanded(
                  child: _WeekDayItem(
                    date: days[index],
                    selected: _sameDay(days[index], selectedDate),
                    isToday: _sameDay(days[index], now),
                    compact: itemWidth < 48,
                    onTap: () => onSelected(days[index]),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _WeekDayItem extends StatelessWidget {
  const _WeekDayItem({
    required this.date,
    required this.selected,
    required this.isToday,
    required this.compact,
    required this.onTap,
  });
  final DateTime date;
  final bool selected, isToday, compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(vertical: compact ? 6 : 9),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isToday && !selected
                    ? AppTheme.primary.withValues(alpha: 0.35)
                    : const Color(0xFFECECEF)),
            boxShadow: [
              if (selected)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                date.day.toString(),
                style: TextStyle(
                  color: selected ? Colors.white : AppTheme.primary,
                  fontSize: compact ? 16 : 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      );
}

class _PremiumAppointmentList extends StatelessWidget {
  const _PremiumAppointmentList({
    required this.title,
    required this.emptyText,
    required this.requests,
    required this.onTapRequest,
  });

  final String title;
  final String emptyText;
  final List<ServiceRequestModel> requests;
  final ValueChanged<ServiceRequestModel> onTapRequest;

  @override
  Widget build(BuildContext context) {
    final orderedRequests = [...requests]
      ..sort((a, b) => b.requestedTime.compareTo(a.requestedTime));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _SectionTitle(title)),
            Text(
              '${orderedRequests.length} Randevu',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (orderedRequests.isEmpty)
          _DashboardEmpty(icon: Icons.event_available_outlined, text: emptyText)
        else ...[
          for (final request in orderedRequests)
            _PremiumAppointmentTile(
              request: request,
              onTap: () => onTapRequest(request),
            ),
        ],
      ],
    );
  }
}

class _PremiumAppointmentTile extends StatelessWidget {
  const _PremiumAppointmentTile({required this.request, required this.onTap});

  final ServiceRequestModel request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = requestStatusColor(request.status);
    final customerName = request.clientName?.trim().isNotEmpty == true
        ? request.clientName!.trim()
        : 'Müşteri';
    final service = _appointmentServiceSummary(request.items);
    final address = request.addressNote?.trim().isNotEmpty == true
        ? request.addressNote!.trim()
        : 'Adres bilgisi yok';
    final timeLabel = _compactDateTimeLabel(request.requestedTime);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFECECEF)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.025), blurRadius: 14, offset: const Offset(0, 6)),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        splashColor: color.withValues(alpha: 0.05),
        highlightColor: color.withValues(alpha: 0.02),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Sol durum çizgisi
            Container(width: 4, height: 72, margin: const EdgeInsets.only(right: 14),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2))),
            // İçerik
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Center(child: Text(customerName[0].toUpperCase(), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: color))),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(customerName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: -0.1))),
                const SizedBox(width: 6),
                _StatusPill(text: requestStatusLabel(request.status), color: color),
              ]),
              const SizedBox(height: 8),
              Text(service, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.primary.withValues(alpha: 0.8))),
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.schedule_rounded, size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(timeLabel, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                const SizedBox(width: 12),
                Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Expanded(child: Text(address, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500))),
                const SizedBox(width: 8),
                Text(_moneyLabel(request.totalPrice),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: -0.1)),
              ]),
            ])),
          ]),
        ),
      ),
    );
  }
}

class _AppointmentMetaLine extends StatelessWidget {
  const _AppointmentMetaLine({
    required this.icon,
    required this.text,
    this.maxLines = 1,
  });

  final IconData icon;
  final String text;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(icon, size: 15, color: AppTheme.textSecondary),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

class _AppointmentUnifiedSummary extends StatelessWidget {
  const _AppointmentUnifiedSummary({
    required this.pending,
    required this.active,
    required this.completed,
    required this.cancelled,
    required this.rejected,
    required this.todayRevenue,
  });

  final int pending, active, completed, cancelled, rejected;
  final double todayRevenue;

  @override
  Widget build(BuildContext context) {
    final total =
        pending + active + completed + cancelled + rejected;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF8F6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.calendar_month,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('İşlem Özeti',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3)),
                    const SizedBox(height: 3),
                    Text(
                      pending > 0
                          ? '$pending talep yanıt bekliyor'
                          : 'Bugün ${todayRevenue.toStringAsFixed(0)} TL kazanç',
                      style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$total',
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5)),
                  const Text('toplam',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final gap = 8.0;
              final itemWidth = (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  _SummaryMiniMetric(
                      width: itemWidth,
                      value: '$pending',
                      label: 'Bekleyen',
                      icon: Icons.inbox_outlined,
                      color: Colors.orange),
                  _SummaryMiniMetric(
                      width: itemWidth,
                      value: '$active',
                      label: 'Aktif',
                      icon: Icons.bolt_outlined,
                      color: AppColors.primary),
                  _SummaryMiniMetric(
                      width: itemWidth,
                      value: '$completed',
                      label: 'Tamamlanan',
                      icon: Icons.task_alt_outlined,
                      color: AppColors.success),
                  _SummaryMiniMetric(
                      width: itemWidth,
                      value: '${cancelled + rejected}',
                      label: 'İptal & Red',
                      icon: Icons.cancel_outlined,
                      color: Colors.red.shade400),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SummaryMiniMetric extends StatelessWidget {
  const _SummaryMiniMetric({
    required this.width,
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });
  final double width;
  final String value, label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3)),
                    Text(label,
                        style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _AppointmentSummaryPremium extends StatelessWidget {
  const _AppointmentSummaryPremium({
    required this.total,
    required this.approved,
    required this.pending,
    required this.cancelled,
  });

  final int total;
  final int approved;
  final int pending;
  final int cancelled;

  @override
  Widget build(BuildContext context) {
    return _PremiumPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Expanded(child: _SectionTitle('Randevu özeti')),
              Text(
                'Bugün',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final spacing = constraints.maxWidth >= 360 ? 10.0 : 8.0;
              final itemWidth = (constraints.maxWidth - spacing) / 2;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  _AppointmentSummaryBox(
                    label: 'Bekleyen',
                    value: pending,
                    width: itemWidth,
                  ),
                  _AppointmentSummaryBox(
                    label: 'Aktif',
                    value: approved,
                    width: itemWidth,
                  ),
                  _AppointmentSummaryBox(
                    label: 'Bugün',
                    value: total,
                    width: itemWidth,
                  ),
                  _AppointmentSummaryBox(
                    label: 'İptal',
                    value: cancelled,
                    width: itemWidth,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AppointmentSummaryBox extends StatelessWidget {
  const _AppointmentSummaryBox({
    required this.label,
    required this.value,
    required this.width,
  });

  final String label;
  final int value;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.fieldFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.025)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '$value',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11.5,
                height: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 132),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: TextStyle(
            color: color,
            fontSize: 11.2,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}

String _timeLabel(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

String _compactDateTimeLabel(DateTime date) =>
    '${date.day} ${_shortMonthName(date.month)}, ${_timeLabel(date)}';

String _shortMonthName(int month) => switch (month) {
  1 => 'Ocak',
  2 => 'Şubat',
  3 => 'Mart',
  4 => 'Nisan',
  5 => 'Mayıs',
  6 => 'Haziran',
  7 => 'Temmuz',
  8 => 'Ağustos',
  9 => 'Eylül',
  10 => 'Ekim',
  11 => 'Kasım',
  _ => 'Aralık',
};

String _moneyLabel(double value) => '${value.toStringAsFixed(0)} TL';

String _appointmentServiceSummary(
  List<({String serviceName, double price})> items,
) {
  if (items.isEmpty) return 'Hizmet bilgisi yok';
  final first = items.first.serviceName.trim();
  final firstName = first.isEmpty ? 'Hizmet bilgisi yok' : first;
  if (items.length == 1) return firstName;
  return '$firstName + ${items.length - 1} hizmet';
}

class _PremiumPanelCard extends StatelessWidget {
  const _PremiumPanelCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFECECEF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _AppointmentsHeroCard extends StatelessWidget {
  const _AppointmentsHeroCard({
    required this.pendingCount,
    required this.activeCount,
    required this.cancelledCount,
    required this.completedCount,
  });

  final int pendingCount;
  final int activeCount;
  final int cancelledCount;
  final int completedCount;

  @override
  Widget build(BuildContext context) {
    final needsAction = pendingCount;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF8F6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.calendar_month,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Operasyon Merkezi',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      needsAction == 0
                          ? 'Şu an yanıt bekleyen acil işlem yok.'
                          : '$needsAction işlem yanıtınızı bekliyor.',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final spacing = constraints.maxWidth >= 360 ? 8.0 : 7.0;
              final itemWidth = (constraints.maxWidth - spacing) / 2;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _PremiumMiniMetric(
                      value: '$pendingCount',
                      label: 'Talep',
                      icon: Icons.inbox_outlined,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _PremiumMiniMetric(
                      value: '$cancelledCount',
                      label: 'İptal',
                      icon: Icons.cancel_outlined,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _PremiumMiniMetric(
                      value: '$activeCount',
                      label: 'Aktif',
                      icon: Icons.bolt_outlined,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _PremiumMiniMetric(
                      value: '$completedCount',
                      label: 'Geçmiş',
                      icon: Icons.task_alt_outlined,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CustomerFilterSegment extends StatelessWidget {
  const _CustomerFilterSegment({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = const [
      ('all', 'Tümü'),
      ('active', 'Aktif'),
      ('new', 'İlk Kez'),
      ('vip', 'VIP'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.fieldFill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => onChanged(item.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: value == item.$1
                        ? AppTheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    item.$2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: value == item.$1 ? Colors.white : AppTheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CustomerInsightMetrics extends StatelessWidget {
  const _CustomerInsightMetrics({
    required this.totalCustomers,
    required this.repeatCustomers,
    required this.pendingFollowUps,
  });

  final int totalCustomers;
  final int repeatCustomers;
  final int pendingFollowUps;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = constraints.maxWidth >= 360 ? 10.0 : 8.0;
        final useThreeColumns = constraints.maxWidth >= 360;
        final itemWidth = useThreeColumns
            ? (constraints.maxWidth - spacing * 2) / 3
            : (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            _CustomerMetricBox(
              icon: Icons.groups_2_outlined,
              value: '$totalCustomers',
              label: 'Toplam Müşteri',
              width: itemWidth,
            ),
            _CustomerMetricBox(
              icon: Icons.repeat_rounded,
              value: '$repeatCustomers',
              label: 'Tekrar Gelen',
              width: itemWidth,
            ),
            _CustomerMetricBox(
              icon: Icons.hourglass_bottom_rounded,
              value: '$pendingFollowUps',
              label: 'Bekleyen Geri Dönüş',
              width: useThreeColumns ? itemWidth : constraints.maxWidth,
            ),
          ],
        );
      },
    );
  }
}

class _CustomerMetricBox extends StatelessWidget {
  const _CustomerMetricBox({
    required this.icon,
    required this.value,
    required this.label,
    required this.width,
  });

  final IconData icon;
  final String value;
  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFECECEF)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.025),
              blurRadius: 12,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            ExcludeSemantics(
              child: Icon(icon, size: 21, color: AppTheme.primary),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11.2,
                height: 1.12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarberCustomersInitialLoading extends StatelessWidget {
  const _BarberCustomersInitialLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Müşteriler yükleniyor',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          _CustomerSkeletonToolbar(),
          SizedBox(height: 14),
          _CustomerSkeletonCard(),
          _CustomerSkeletonCard(),
          _CustomerSkeletonCard(),
        ],
      ),
    );
  }
}

class _CustomerSkeletonToolbar extends StatelessWidget {
  const _CustomerSkeletonToolbar();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Column(
        children: [
          Container(
            height: 54,
            decoration: BoxDecoration(
              color: AppTheme.fieldFill,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(
              4,
              (index) => Expanded(
                child: Container(
                  height: 44,
                  margin: EdgeInsets.only(right: index == 3 ? 0 : 8),
                  decoration: BoxDecoration(
                    color: AppTheme.fieldFill,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerSkeletonCard extends StatelessWidget {
  const _CustomerSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFECECEF)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const _CustomerSkeletonBox(width: 48, height: 48, radius: 99),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      _CustomerSkeletonBox(width: 150, height: 16, radius: 8),
                      SizedBox(height: 9),
                      _CustomerSkeletonBox(width: 210, height: 12, radius: 8),
                    ],
                  ),
                ),
                const _CustomerSkeletonBox(width: 62, height: 28, radius: 99),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: const [
                Expanded(child: _CustomerSkeletonBox(height: 42, radius: 14)),
                SizedBox(width: 10),
                Expanded(child: _CustomerSkeletonBox(height: 42, radius: 14)),
                SizedBox(width: 10),
                Expanded(child: _CustomerSkeletonBox(height: 42, radius: 14)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerSkeletonBox extends StatelessWidget {
  const _CustomerSkeletonBox({
    this.width,
    required this.height,
    required this.radius,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F3),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _BarberCustomersError extends StatelessWidget {
  const _BarberCustomersError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Müşteriler yüklenemedi. Tekrar dene.',
      excludeSemantics: true,
      child: _CustomersStateCard(
        icon: Icons.error_outline_rounded,
        title: 'Müşteriler yüklenemedi',
        description: 'Müşteri bilgileri alınırken bir sorun oluştu.',
        action: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tekrar Dene'),
        ),
      ),
    );
  }
}

class _BarberCustomersInlineError extends StatelessWidget {
  const _BarberCustomersInlineError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Müşteriler yüklenemedi. Tekrar dene.',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBF7),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFFFE3C2)),
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.info_outline_rounded,
                color: Colors.orange.shade700,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Müşteri bilgileri yenilenemedi. Eski liste gösteriliyor.',
                style: TextStyle(fontWeight: FontWeight.w700, height: 1.25),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Tekrar Dene')),
          ],
        ),
      ),
    );
  }
}

class _BarberCustomersEmpty extends StatelessWidget {
  const _BarberCustomersEmpty({IconData? icon, String? text});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Henüz müşteri yok. Tamamlanan işlemlerden sonra müşteriler burada görünecek.',
      excludeSemantics: true,
      child: _CustomersStateCard(
        icon: Icons.people_outline_rounded,
        title: 'Henüz müşteri yok',
        description:
            'Tamamlanan işlemlerden sonra müşteriler burada görünecek.',
      ),
    );
  }
}

class _BarberCustomersFilteredEmpty extends StatelessWidget {
  const _BarberCustomersFilteredEmpty({IconData? icon, String? text});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Müşteri bulunamadı. Arama veya filtre seçiminizi değiştirin.',
      excludeSemantics: true,
      child: _CustomersStateCard(
        icon: Icons.search_off_rounded,
        title: 'Müşteri bulunamadı',
        description: 'Arama veya filtre seçiminizi değiştirin.',
      ),
    );
  }
}

class _CustomersStateCard extends StatelessWidget {
  const _CustomersStateCard({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFECECEF)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Icon(
              icon,
              size: 38,
              color: Colors.black.withValues(alpha: 0.18),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: action!,
            ),
          ],
        ],
      ),
    );
  }
}

Color _customerStatusColor(BarberCustomerModel customer) {
  if (customer.isVip) return const Color(0xFF635BFF);
  if (customer.isActive) return Colors.green;
  return Colors.orange;
}

String _customerInitial(String displayName) {
  final trimmed = displayName.trim();
  if (trimmed.isEmpty) return 'M';
  return trimmed.characters.first.toUpperCase();
}

String _customerServicesSummary(List<String> services) {
  final visibleServices = services.take(3).toList();
  if (visibleServices.isEmpty) return 'Hizmet geçmişi henüz oluşmadı';
  if (services.length <= 3) return visibleServices.join(', ');
  return '${visibleServices.join(', ')} +${services.length - 3}';
}

class _PremiumCustomerProfileCard extends StatelessWidget {
  const _PremiumCustomerProfileCard({
    required this.customer,
    required this.onTap,
  });

  final BarberCustomerModel customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final servicesText = _customerServicesSummary(customer.preferredServices);
    final semanticsLabel =
        '${customer.displayName}, ${customer.statusLabel}, $servicesText, '
        'Son ziyaret ${_dateOnlyLabel(customer.lastVisit)}, '
        'Toplam işlem ${customer.completedJobCount}, '
        'Toplam harcama ${_moneyLabel(customer.totalSpent)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFECECEF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Semantics(
        button: true,
        label: semanticsLabel,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: CircleAvatar(
                        radius: 23,
                        backgroundColor: AppTheme.fieldFill,
                        child: Text(
                          _customerInitial(customer.displayName),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  customer.displayName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16.5,
                                    height: 1.08,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _StatusPill(
                                text: customer.statusLabel,
                                color: _customerStatusColor(customer),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            servicesText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              height: 1.22,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final spacing = constraints.maxWidth >= 360 ? 10.0 : 8.0;
                    final itemWidth = constraints.maxWidth >= 360
                        ? (constraints.maxWidth - spacing * 2) / 3
                        : (constraints.maxWidth - spacing) / 2;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        _CustomerMiniInfo(
                          icon: Icons.calendar_today_outlined,
                          label: 'Son ziyaret',
                          value: _dateOnlyLabel(customer.lastVisit),
                          width: itemWidth,
                        ),
                        _CustomerMiniInfo(
                          icon: Icons.shopping_bag_outlined,
                          label: 'Toplam işlem',
                          value: '${customer.completedJobCount}',
                          width: itemWidth,
                        ),
                        _CustomerMiniInfo(
                          icon: Icons.payments_outlined,
                          label: 'Toplam harcama',
                          value: _moneyLabel(customer.totalSpent),
                          width: constraints.maxWidth >= 360
                              ? itemWidth
                              : constraints.maxWidth,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomerMiniInfo extends StatelessWidget {
  const _CustomerMiniInfo({
    required this.icon,
    required this.label,
    required this.value,
    required this.width,
  });

  final IconData icon;
  final String label;
  final String value;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
        decoration: BoxDecoration(
          color: AppTheme.fieldFill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(icon, size: 15, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerInsightsCard extends StatelessWidget {
  const _CustomerInsightsCard({
    required this.customers,
    required this.totalRevenue,
    required this.averageValue,
    required this.reviews,
  });

  final List<BarberCustomerModel> customers;
  final double totalRevenue;
  final double averageValue;
  final List<BarberReview> reviews;

  @override
  Widget build(BuildContext context) {
    final topCustomers = [...customers]
      ..sort((a, b) => b.totalSpent.compareTo(a.totalSpent));
    return _PremiumPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Müşteri İçgörüleri'),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final spacing = constraints.maxWidth >= 360 ? 10.0 : 8.0;
              final itemWidth = (constraints.maxWidth - spacing) / 2;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _DashboardMetric(
                      icon: Icons.payments_outlined,
                      value: _moneyLabel(totalRevenue),
                      label: 'Toplam hacim',
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _DashboardMetric(
                      icon: Icons.receipt_long_outlined,
                      value: _moneyLabel(averageValue),
                      label: 'Ortalama işlem',
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'Son Yorumlar',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          const SizedBox(height: 8),
          if (reviews.isEmpty)
            const Text(
              'Henüz yorum yok.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            ...reviews.take(2).map((review) => _CustomerReviewPreview(review)),
          if (topCustomers.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'En Sadık Müşteriler',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
            const SizedBox(height: 8),
            ...topCustomers
                .take(3)
                .toList()
                .asMap()
                .entries
                .map(
                  (entry) => _LoyalCustomerRow(
                    index: entry.key + 1,
                    customer: entry.value,
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _CustomerReviewPreview extends StatelessWidget {
  const _CustomerReviewPreview(this.review);

  final BarberReview review;

  @override
  Widget build(BuildContext context) {
    final name = review.clientName?.trim().isNotEmpty == true
        ? review.clientName!.trim()
        : 'Müşteri';
    final comment = review.comment?.trim().isNotEmpty == true
        ? review.comment!.trim()
        : 'Yorum bırakıldı.';
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          ExcludeSemantics(
            child: CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.fieldFill,
              child: Text(
                _customerInitial(name),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  comment,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StarRow(rating: review.score.toDouble(), size: 13),
        ],
      ),
    );
  }
}

class _LoyalCustomerRow extends StatelessWidget {
  const _LoyalCustomerRow({required this.index, required this.customer});

  final int index;
  final BarberCustomerModel customer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$index',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(
            child: Text(
              customer.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${customer.completedJobCount} işlem · ${_moneyLabel(customer.totalSpent)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerDetailSheet extends StatelessWidget {
  const _CustomerDetailSheet({
    required this.customer,
    required this.onOpenLastJob,
  });

  final BarberCustomerModel customer;
  final VoidCallback? onOpenLastJob;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
              ),
              const Expanded(
                child: Text(
                  'Müşteri Detayı',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 12),
          _PremiumPanelCard(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 38,
                  backgroundColor: AppTheme.fieldFill,
                  child: Text(
                    customer.displayName[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  customer.displayName,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${customer.completedJobCount} işlem · ${customer.totalSpent.toStringAsFixed(0)} TL',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (customer.phone != null && customer.phone!.isNotEmpty) ...[
            const SizedBox(height: 14),
            _PremiumPanelCard(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => launchUrl(Uri.parse('tel:${customer.phone}')),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.call_rounded, color: AppColors.success, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Müşteriyi Ara',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(customer.phone!,
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          _PremiumPanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Müşteri Özeti',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 14),
                _DetailInfoRow(
                  icon: Icons.calendar_today_outlined,
                  title: _dateOnlyLabel(customer.firstVisit),
                  subtitle: 'İlk işlem tarihi',
                ),
                _DetailInfoRow(
                  icon: Icons.sell_outlined,
                  title: customer.preferredServicesText.isEmpty
                      ? 'Hizmet geçmişi'
                      : customer.preferredServicesText,
                  subtitle: 'Tercih ettiği hizmetler',
                ),
                _DetailInfoRow(
                  icon: Icons.groups_2_outlined,
                  title: '${customer.completedJobCount}',
                  subtitle: 'Toplam iş',
                ),
                _DetailInfoRow(
                  icon: Icons.payments_outlined,
                  title: '${customer.totalSpent.toStringAsFixed(0)} TL',
                  subtitle: 'Toplam harcama',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _PremiumPanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Son Randevular & İşlemler',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 12),
                if (customer.recentJobs.isEmpty)
                  const Text(
                    'Tamamlanan işlem bulunamadı.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  )
                else
                  ...customer.recentJobs
                      .take(3)
                      .map(
                        (job) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.check_circle,
                            color: Colors.green.shade600,
                          ),
                          title: Text(formatDateTime(job.visitDate)),
                          subtitle: Text(job.services.join(', ')),
                          trailing: Text(
                            '${job.totalPrice.toStringAsFixed(0)} TL',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (onOpenLastJob != null)
            FilledButton.icon(
              onPressed: onOpenLastJob,
              icon: const Icon(Icons.work_outline_rounded),
              label: const Text('Son İşlem Detayını Aç'),
            ),
          if (onOpenLastJob != null) const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _PremiumMiniMetric extends StatelessWidget {
  const _PremiumMiniMetric({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.black87, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              letterSpacing: -0.2,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentItem {
  const _SegmentItem({
    required this.value,
    required this.label,
    required this.count,
  });

  final String value;
  final String label;
  final int count;
}

class _AppointmentSegmentedControl extends StatelessWidget {
  const _AppointmentSegmentedControl({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String value;
  final List<_SegmentItem> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: value == item.value
                      ? Colors.white
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: value == item.value
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => onChanged(item.value),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: value == item.value
                                  ? Colors.black
                                  : AppTheme.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '${item.count}',
                            style: TextStyle(
                              color: value == item.value
                                  ? Colors.black87
                                  : Colors.grey.shade500,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: AppTheme.primary,
      ),
    ),
  );
}

class _DashboardMetric extends StatelessWidget {
  const _DashboardMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 20, color: Colors.black87),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardEmpty extends StatelessWidget {
  const _DashboardEmpty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          children: [
            Icon(icon, size: 36, color: Colors.grey.shade300),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
