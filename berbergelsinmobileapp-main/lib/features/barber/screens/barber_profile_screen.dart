import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config.dart';
import '../../../core/data/selection_options.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../auth/widgets/verification_sheets.dart';
import '../../map/data/barbers_repo.dart';
import '../../map/widgets/barber_sheet.dart';
import '../../profile/screens/change_password_screen.dart';
import '../../profile/screens/notification_preferences_screen.dart';
import '../data/business_working_hours.dart';
import '../controllers/address_search_controller.dart';
import '../data/address_search_repository.dart';
import '../domain/barber_profile_completion_input.dart';
import '../utils/barber_profile_completion.dart';
import '../widgets/profile/working_hours_editor.dart';
import '../widgets/profile/address_search_field.dart';
import '../widgets/profile/resolved_address_form.dart';
import '../widgets/profile/photo_picker_sheet.dart';

enum _ProfileUploadKind { logo, cover, gallery }

/// İşletme profili: logo, işletme adı, tercihler, yarıçap ve hizmet yönetimi.
class BarberProfileController {
  VoidCallback? _showProfileSettings;
  VoidCallback? _showServices;
  VoidCallback? _showGallery;

  void showProfileSettings() => _showProfileSettings?.call();
  void showServices() => _showServices?.call();
  void showGallery() => _showGallery?.call();
}

enum BarberProfilePage { overview, settings, services }

class BarberProfileScreen extends StatefulWidget {
  const BarberProfileScreen({
    super.key,
    this.embedded = false,
    this.controller,
    this.page = BarberProfilePage.overview,
    this.onOpenReviews,
    this.initialProfile,
    this.initialLogoBytes,
    this.onLogoChanged,
    this.onProfileChanged,
  });

  final bool embedded;
  final BarberProfileController? controller;
  final BarberProfilePage page;
  final VoidCallback? onOpenReviews;
  final Map<String, dynamic>? initialProfile;
  final Uint8List? initialLogoBytes;
  final ValueChanged<Uint8List?>? onLogoChanged;
  final VoidCallback? onProfileChanged;

  @override
  State<BarberProfileScreen> createState() => _BarberProfileScreenState();
}

class _BarberProfileScreenState extends State<BarberProfileScreen> {
  static double? _cachedLat;
  static double? _cachedLng;
  final _businessName = TextEditingController();
  final _category = TextEditingController();
  final _description = TextEditingController();
  final _addressLine = TextEditingController();
  late final AddressSearchController _addressSearch;
  String? _placeId;
  String? _formattedAddress;
  String _serviceMode = 'Mobile';
  bool _sharePhone = true;
  bool _acceptsOffers = true;
  bool _acceptsUrgentRequests = true;
  double _radiusKm = 5;
  List<BarberServiceItem> _services = [];
  List<BusinessPhoto> _photos = [];
  List<String> _badges = [];
  List<BusinessWorkingDay> _workingHours = [];
  String? _barberStatus;
  String? _rejectionReason;
  List<String> _categoryOptions = ServiceSelectionOptions.categories;
  Uint8List? _logoBytes;
  String? _barberProfileId;
  bool _loading = true;
  bool _hasData = false;
  bool _busy = false;
  _ProfileUploadKind? _activeUpload;

  bool get _isUploading => _activeUpload != null;
  String? _loadError;
  double? _lat = _cachedLat;
  double? _lng = _cachedLng;
  bool _usingDeviceLocation = false;
  bool _locationBusy = false;
  final _mapController = MapController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _galleryKey = GlobalKey();

  ProfileEditSnapshot? _initialSnapshot;

  bool get _hasUnsavedProfileChanges {
    final snapshot = _initialSnapshot;
    if (snapshot == null) return false;
    return snapshot.isDirty(
      businessName: _businessName.text,
      category: _category.text,
      description: _description.text,
      addressLine: _addressLine.text,
      serviceMode: _serviceMode,
      sharePhone: _sharePhone,
      acceptsOffers: _acceptsOffers,
      acceptsUrgentRequests: _acceptsUrgentRequests,
      serviceRadiusKm: _radiusKm,
      lat: _lat,
      lng: _lng,
    );
  }

  void _onControllerChanged() {
    if (!mounted || _loading) return;
    setState(() {});
  }

  void _applyResolvedAddress(ResolvedAddress address) {
    setState(() {
      _placeId = address.placeId;
      _formattedAddress = address.formattedAddress;
      _addressLine.text = address.formattedAddress ?? _addressLine.text;
      _lat = address.latitude;
      _lng = address.longitude;
      _usingDeviceLocation = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _mapController.move(LatLng(address.latitude, address.longitude), 16);
      }
    });
  }

  Future<bool> _showExitConfirmationDialog() async {
    FocusScope.of(context).unfocus();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Kaydedilmemiş değişiklikler'),
        content: const Text(
          'Yaptığınız değişiklikler kaybolacak. Çıkmak istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Değişiklikleri Sil ve Çık'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  void initState() {
    super.initState();
    _addressSearch = AddressSearchController(
      repository: BackendAddressSearchRepository(),
    );
    _logoBytes = widget.initialLogoBytes;
    _attachController();
    _businessName.addListener(_onControllerChanged);
    _category.addListener(_onControllerChanged);
    _description.addListener(_onControllerChanged);
    _addressLine.addListener(_onControllerChanged);
    _load();
  }

  @override
  void didUpdateWidget(covariant BarberProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._showProfileSettings = null;
      oldWidget.controller?._showServices = null;
      oldWidget.controller?._showGallery = null;
      _attachController();
    }
    if (widget.initialLogoBytes != oldWidget.initialLogoBytes) {
      _logoBytes = widget.initialLogoBytes;
    }
    if (widget.initialProfile != oldWidget.initialProfile &&
        widget.initialProfile != null) {
      final profile = widget.initialProfile!;
      final serverLat = (profile['lat'] as num?)?.toDouble();
      final serverLng = (profile['lng'] as num?)?.toDouble();
      if (mounted) {
        setState(() {
          if (!_hasUnsavedProfileChanges) {
            _businessName.text = profile['businessName'] as String? ?? '';
            _category.text = profile['category'] as String? ?? '';
            _description.text = profile['description'] as String? ?? '';
            _addressLine.text = profile['addressLine'] as String? ?? '';
            _serviceMode = profile['serviceMode'] as String? ?? 'Mobile';
            _sharePhone = profile['sharePhone'] as bool? ?? false;
            _acceptsOffers = profile['acceptsOffers'] as bool? ?? false;
            _acceptsUrgentRequests =
                profile['acceptsUrgentRequests'] as bool? ?? false;
            _radiusKm = ((profile['serviceRadiusKm'] as num?)?.toDouble() ?? 5)
                .clamp(1, 30);

            _initialSnapshot = ProfileEditSnapshot.fromState(
              businessName: _businessName.text,
              category: _category.text,
              description: _description.text,
              addressLine: _addressLine.text,
              serviceMode: _serviceMode,
              sharePhone: _sharePhone,
              acceptsOffers: _acceptsOffers,
              acceptsUrgentRequests: _acceptsUrgentRequests,
              serviceRadiusKm: _radiusKm,
              lat: _lat,
              lng: _lng,
            );
          }
          _services = (profile['services'] as List? ?? [])
              .map((s) => BarberServiceItem.fromJson(s as Map<String, dynamic>))
              .toList();
          _photos = (profile['photos'] as List? ?? [])
              .map((p) => BusinessPhoto.fromJson(p as Map<String, dynamic>))
              .toList();
          _badges = (profile['badges'] as List? ?? []).cast<String>();
          _barberStatus = profile['status'] as String?;
          _rejectionReason = profile['rejectionReason'] as String?;

          if (serverLat != null && serverLng != null) {
            _lat = serverLat;
            _lng = serverLng;
            _cachedLat = serverLat;
            _cachedLng = serverLng;
            _usingDeviceLocation = false;
          }
        });
      }
    }
  }

  void _attachController() {
    widget.controller?._showProfileSettings = () =>
        _openPage(BarberProfilePage.settings);
    widget.controller?._showServices = () =>
        _openPage(BarberProfilePage.services);
    widget.controller?._showGallery = _scrollToGallery;
  }

  Future<void> _openPage(BarberProfilePage page) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => BarberProfileScreen(page: page)),
    );
    await _load();
  }

  Future<void> _showCustomerPreview() async {
    final profileId = _barberProfileId;
    if (profileId == null) return;
    final user = context.read<AuthCubit>().state.user;
    final detail = BarberDetail(
      barberProfileId: profileId,
      businessName: _businessName.text.trim(),
      category: _category.text.trim().isEmpty ? null : _category.text.trim(),
      description: _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
      addressLine: _addressLine.text.trim().isEmpty
          ? null
          : _addressLine.text.trim(),
      serviceMode: _serviceMode,
      firstName: user?.firstName,
      lastName: user?.lastName,
      workingHours: jsonEncode(_workingHours.map((e) => e.toJson()).toList()),
      acceptsOffers: _acceptsOffers,
      acceptsUrgentRequests: _acceptsUrgentRequests,
      phoneNumber: _sharePhone ? user?.phone : null,
      services: _services,
      photos: _photos,
      badges: _badges,
      lat: _lat,
      lng: _lng,
      avgRating: user?.avgRating,
      ratingCount: user?.ratingCount ?? 0,
      hasLogo: _logoBytes != null,
    );
    await showBarberSheet(
      context,
      profileId,
      _lat ?? 0,
      _lng ?? 0,
      previewOnly: true,
      initialDetail: detail,
      initialLogoBytes: _logoBytes,
    );
  }

  @override
  void dispose() {
    _businessName.removeListener(_onControllerChanged);
    _category.removeListener(_onControllerChanged);
    _description.removeListener(_onControllerChanged);
    _addressLine.removeListener(_onControllerChanged);
    _scrollController.dispose();
    widget.controller?._showProfileSettings = null;
    widget.controller?._showServices = null;
    widget.controller?._showGallery = null;
    _businessName.dispose();
    _category.dispose();
    _description.dispose();
    _addressLine.dispose();
    _addressSearch.dispose();
    super.dispose();
  }

  String _sanitizeError(dynamic error) {
    String msg = '';
    if (error is ApiException) {
      msg = error.message;
    } else if (error != null) {
      msg = error.toString();
    }

    final lower = msg.toLowerCase();
    if (lower.isEmpty ||
        lower.contains('dioexception') ||
        lower.contains('socketexception') ||
        lower.contains('httpexception') ||
        lower.contains('connection') ||
        lower.contains('network') ||
        lower.contains('500') ||
        lower.contains('403') ||
        lower.contains('401') ||
        lower.contains('response.data') ||
        lower.contains('stack trace') ||
        lower.contains('error')) {
      return 'İşletme profili yüklenemedi. Lütfen bağlantınızı kontrol edip tekrar deneyin.';
    }
    return msg;
  }

  Future<void> _load({bool forceApi = false}) async {
    try {
      List<String> categories = ServiceSelectionOptions.categories;
      try {
        categories = await BarbersRepo.instance.categories();
      } catch (_) {}

      final profile = (!forceApi && widget.initialProfile != null)
          ? widget.initialProfile!
          : await BarbersRepo.instance.myProfile();
      final profileId = profile['barberProfileId'] as String?;
      final serverLat = (profile['lat'] as num?)?.toDouble();
      final serverLng = (profile['lng'] as num?)?.toDouble();
      if (!mounted) return;
      setState(() {
        _loadError = null;
        _categoryOptions = categories;
        _barberProfileId = profileId;

        if (!_hasUnsavedProfileChanges) {
          _businessName.text = profile['businessName'] as String? ?? '';
          _category.text = profile['category'] as String? ?? '';
          _description.text = profile['description'] as String? ?? '';
          _addressLine.text = profile['addressLine'] as String? ?? '';
          _serviceMode = profile['serviceMode'] as String? ?? 'Mobile';
          _sharePhone = profile['sharePhone'] as bool? ?? false;
          _acceptsOffers = profile['acceptsOffers'] as bool? ?? false;
          _acceptsUrgentRequests =
              profile['acceptsUrgentRequests'] as bool? ?? false;
          _radiusKm = ((profile['serviceRadiusKm'] as num?)?.toDouble() ?? 5)
              .clamp(1, 30);

          _initialSnapshot = ProfileEditSnapshot.fromState(
            businessName: _businessName.text,
            category: _category.text,
            description: _description.text,
            addressLine: _addressLine.text,
            serviceMode: _serviceMode,
            sharePhone: _sharePhone,
            acceptsOffers: _acceptsOffers,
            acceptsUrgentRequests: _acceptsUrgentRequests,
            serviceRadiusKm: _radiusKm,
            lat: _lat,
            lng: _lng,
          );
        }

        _services = (profile['services'] as List? ?? [])
            .map((s) => BarberServiceItem.fromJson(s as Map<String, dynamic>))
            .toList();
        _photos = (profile['photos'] as List? ?? [])
            .map((p) => BusinessPhoto.fromJson(p as Map<String, dynamic>))
            .toList();
        _badges = (profile['badges'] as List? ?? []).cast<String>();
        _barberStatus = profile['status'] as String?;
        _rejectionReason = profile['rejectionReason'] as String?;

        List<BusinessWorkingDay> parsedHours = [];
        try {
          final rawHours = profile['workingHours'] as String?;
          if (rawHours != null && rawHours.isNotEmpty) {
            final List<dynamic> decoded = jsonDecode(rawHours);
            parsedHours = decoded
                .map(
                  (e) => BusinessWorkingDay.fromJson(e as Map<String, dynamic>),
                )
                .toList();
          }
        } catch (_) {}

        final Map<int, BusinessWorkingDay> map = {
          for (final day in parsedHours) day.day: day,
        };
        _workingHours = List.generate(7, (index) {
          final dayNum = index + 1;
          return map[dayNum] ??
              BusinessWorkingDay(
                day: dayNum,
                open: '09:00',
                close: '20:00',
                closed: true,
              );
        });

        if (serverLat != null && serverLng != null) {
          _lat = serverLat;
          _lng = serverLng;
          _cachedLat = serverLat;
          _cachedLng = serverLng;
          _usingDeviceLocation = false;
        }
        _loading = false;
        _hasData = true;
      });
      if (_logoBytes == null) {
        await _loadLogo();
      }
      if (widget.page == BarberProfilePage.overview &&
          (_lat == null || _lng == null)) {
        await _loadCurrentLocation();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (!_hasData) {
            _loadError = _sanitizeError(e);
          }
        });
        if (_hasData) {
          _snack(
            'Profil güncellenemedi. Mevcut bilgiler gösteriliyor.',
            error: true,
          );
        } else {
          _snack(_sanitizeError(e), error: true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (!_hasData) {
            _loadError = _sanitizeError(e);
          }
        });
        if (_hasData) {
          _snack(
            'Profil güncellenemedi. Mevcut bilgiler gösteriliyor.',
            error: true,
          );
        }
      }
    }
  }

  Future<void> _loadLogo() async {
    try {
      final bytes = await BarbersRepo.instance.logoBytes(_barberProfileId!);
      if (mounted) {
        setState(() => _logoBytes = Uint8List.fromList(bytes));
        widget.onLogoChanged?.call(_logoBytes);
      }
    } catch (_) {
      // logo yok - sorun değil
    }
  }

  void _notifyChanged() {
    widget.onProfileChanged?.call();
  }

  Future<void> _loadCurrentLocation({bool showErrors = false}) async {
    if (_locationBusy) return;
    setState(() => _locationBusy = true);
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (showErrors && mounted) {
        _snack(
          'Konum servisi kapalı. Konum ayarlarından açabilirsiniz.',
          error: true,
        );
        await Geolocator.openLocationSettings();
      }
      if (mounted) setState(() => _locationBusy = false);
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      if (showErrors && mounted) {
        _snack('Konum izni uygulama ayarlarından açılmalı.', error: true);
        await Geolocator.openAppSettings();
      }
      if (mounted) setState(() => _locationBusy = false);
      return;
    }
    if (permission == LocationPermission.denied) {
      if (mounted) setState(() => _locationBusy = false);
      return;
    }

    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted && (_lat == null || _lng == null)) {
        setState(() {
          _lat = lastKnown.latitude;
          _lng = lastKnown.longitude;
          _cachedLat = lastKnown.latitude;
          _cachedLng = lastKnown.longitude;
          _usingDeviceLocation = true;
        });
        try {
          _mapController.move(
            LatLng(lastKnown.latitude, lastKnown.longitude),
            15,
          );
        } catch (_) {}
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
        _cachedLat = position.latitude;
        _cachedLng = position.longitude;
        _usingDeviceLocation = true;
      });
      try {
        _mapController.move(LatLng(position.latitude, position.longitude), 15);
      } catch (_) {}
      try {
        await BarbersRepo.instance.updateLocation(
          position.latitude,
          position.longitude,
        );
      } on ApiException catch (e) {
        if (showErrors) {
          _snack(
            'Konum cihazda gösteriliyor ancak kaydedilemedi: ${e.message}',
            error: true,
          );
        }
      }
    } catch (_) {
      if (showErrors && mounted) {
        _snack('Konum alınamadı. Lütfen tekrar deneyin.', error: true);
      }
    } finally {
      if (mounted) setState(() => _locationBusy = false);
    }
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

  String get _todayWorkingHoursText {
    if (_workingHours.isEmpty) return '';
    final weekday = DateTime.now().weekday;
    final todayHour = _workingHours.firstWhere(
      (h) => h.day == weekday,
      orElse: () => _workingHours.first,
    );
    if (todayHour.closed) {
      return 'Bugün kapalı';
    }
    return 'Bugün ${todayHour.open}–${todayHour.close}';
  }

  void _scrollToGallery() {
    final context = _galleryKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _openWorkingHoursScreen() async {
    if (_busy) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => WorkingHoursEditorScreen(
          workingHours: _workingHours,
          onSave: (updatedHours) async {
            await BarbersRepo.instance.updateProfile(
              businessName: _businessName.text.trim().isEmpty
                  ? null
                  : _businessName.text.trim(),
              category: _category.text.trim().isEmpty
                  ? null
                  : _category.text.trim(),
              description: _description.text.trim().isEmpty
                  ? null
                  : _description.text.trim(),
              addressLine: _addressLine.text.trim().isEmpty
                  ? null
                  : _addressLine.text.trim(),
              serviceMode: _serviceMode,
              sharePhone: _sharePhone,
              acceptsOffers: _acceptsOffers,
              acceptsUrgentRequests: _acceptsUrgentRequests,
              serviceRadiusKm: _radiusKm.round(),
              workingHours: updatedHours.map((e) => e.toJson()).toList(),
            );
          },
        ),
      ),
    );
    await _load(forceApi: true);
    _notifyChanged();
  }

  Future<void> _pickLogo() async {
    final result = await showModalBottomSheet<PlatformFileResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PhotoPickerSheet(
        title: 'Logo Seç',
        subtitle: 'İşletmenizi temsil eden kare bir logo',
      ),
    );
    if (result == null) return;
    if (result.size > 10 * 1024 * 1024) {
      _snack('Logo 10 MB\'ı aşamaz.', error: true);
      return;
    }
    final contentType = result.name.toLowerCase().endsWith('.png')
        ? 'image/png'
        : 'image/jpeg';
    setState(() {
      _activeUpload = _ProfileUploadKind.logo;
    });
    try {
      await BarbersRepo.instance.uploadLogo(
        result.bytes,
        result.name,
        contentType,
      );
      setState(() => _logoBytes = result.bytes);
      widget.onLogoChanged?.call(_logoBytes);
      _notifyChanged();
      _snack('Logo güncellendi.');
    } on ApiException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('dosya') ||
          msg.contains('boyut') ||
          msg.contains('büyük') ||
          msg.contains('limit') ||
          msg.contains('uzantı') ||
          msg.contains('format')) {
        _snack(e.message, error: true);
      } else {
        _snack('Logo yüklenemedi. Lütfen tekrar deneyin.', error: true);
      }
    } catch (_) {
      _snack('Logo yüklenemedi. Lütfen tekrar deneyin.', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _activeUpload = null;
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await BarbersRepo.instance.updateProfile(
        businessName: _businessName.text.trim().isEmpty
            ? null
            : _businessName.text.trim(),
        category: _category.text.trim().isEmpty ? null : _category.text.trim(),
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        addressLine: _addressLine.text.trim().isEmpty
            ? null
            : _addressLine.text.trim(),
        serviceMode: _serviceMode,
        sharePhone: _sharePhone,
        acceptsOffers: _acceptsOffers,
        acceptsUrgentRequests: _acceptsUrgentRequests,
        serviceRadiusKm: _radiusKm.round(),
        workingHours: _workingHours.map((e) => e.toJson()).toList(),
      );
      if (_lat != null &&
          _lng != null &&
          (_lat != _cachedLat || _lng != _cachedLng)) {
        await BarbersRepo.instance.updateLocation(_lat!, _lng!);
        _cachedLat = _lat;
        _cachedLng = _lng;
      }
      _initialSnapshot = ProfileEditSnapshot.fromState(
        businessName: _businessName.text,
        category: _category.text,
        description: _description.text,
        addressLine: _addressLine.text,
        serviceMode: _serviceMode,
        sharePhone: _sharePhone,
        acceptsOffers: _acceptsOffers,
        acceptsUrgentRequests: _acceptsUrgentRequests,
        serviceRadiusKm: _radiusKm,
        lat: _lat,
        lng: _lng,
      );
      _notifyChanged();
      _snack('Profil kaydedildi.');
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editService(BarberServiceItem? service) async {
    final nameController = TextEditingController(text: service?.name ?? '');
    final priceController = TextEditingController(
      text: service == null ? '' : service.price.toStringAsFixed(0),
    );
    final descriptionController = TextEditingController(
      text: service?.description ?? '',
    );
    final durationController = TextEditingController(
      text: service?.durationMinutes?.toString() ?? '',
    );
    var priceType = service?.priceType ?? 'Fixed';
    var isPopular = service?.isPopular ?? false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          scrollable: true,
          title: Text(service == null ? 'Hizmet Ekle' : 'Hizmeti Düzenle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Hizmet adı'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Fiyat (TL)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Hizmet açıklaması',
                  hintText: 'Müşterinin hizmeti daha iyi anlaması için...',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: durationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Süre (dakika)',
                  hintText: 'Opsiyonel',
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                label: 'Popüler hizmet ${isPopular ? 'açık' : 'kapalı'}',
                container: true,
                child: SwitchListTile(
                  title: const Text('Popüler Hizmet'),
                  subtitle: const Text('Bu hizmet vitrinde öne çıkarılsın'),
                  value: isPopular,
                  onChanged: (val) {
                    setStateDialog(() {
                      isPopular = val;
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final name = nameController.text.trim();
    final price = double.tryParse(
      priceController.text.trim().replaceAll(',', '.'),
    );
    final description = descriptionController.text.trim();
    final duration = int.tryParse(durationController.text.trim());
    if (name.isEmpty || price == null || price < 1) {
      _snack('Geçerli bir ad ve fiyat girin.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      if (service == null) {
        await BarbersRepo.instance.addService(
          name,
          price,
          description: description.isEmpty ? null : description,
          priceType: priceType,
          durationMinutes: duration,
          isPopular: isPopular,
        );
      } else {
        await BarbersRepo.instance.updateService(
          service.id,
          name,
          price,
          description: description.isEmpty ? null : description,
          priceType: priceType,
          durationMinutes: duration,
          isPopular: isPopular,
        );
      }
      await _load(forceApi: true);
      _notifyChanged();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteService(BarberServiceItem service) async {
    setState(() => _busy = true);
    try {
      await BarbersRepo.instance.deleteService(service.id);
      await _load(forceApi: true);
      _notifyChanged();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickBusinessPhoto({bool isCover = false}) async {
    final result = await showModalBottomSheet<PlatformFileResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PhotoPickerSheet(
        title: isCover ? 'Kapak Fotoğrafı Seç' : 'Vitrin Fotoğrafı Ekle',
        subtitle: isCover
            ? 'Profilinizin üst kısmında görünür'
            : 'İşletmenizi tanıtan fotoğraflar',
      ),
    );
    if (result == null) return;
    if (result.size > 10 * 1024 * 1024) {
      _snack('Fotoğraf 10 MB sınırını aşamaz.', error: true);
      return;
    }
    final contentType = result.name.toLowerCase().endsWith('.png')
        ? 'image/png'
        : 'image/jpeg';
    setState(() {
      _activeUpload = isCover
          ? _ProfileUploadKind.cover
          : _ProfileUploadKind.gallery;
    });
    try {
      await BarbersRepo.instance.uploadPhoto(
        result.bytes,
        result.name,
        contentType,
        isCover: isCover,
      );
      await _load(forceApi: true);
      _notifyChanged();
      _snack(
        isCover ? 'Kapak fotoğrafı güncellendi.' : 'Vitrin fotoğrafı eklendi.',
      );
    } on ApiException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('dosya') ||
          msg.contains('boyut') ||
          msg.contains('büyük') ||
          msg.contains('limit') ||
          msg.contains('uzantı') ||
          msg.contains('format')) {
        _snack(e.message, error: true);
      } else {
        _snack(
          isCover
              ? 'Kapak fotoğrafı yüklenemedi. Lütfen tekrar deneyin.'
              : 'Fotoğraf yüklenemedi. Lütfen tekrar deneyin.',
          error: true,
        );
      }
    } catch (_) {
      _snack(
        isCover
            ? 'Kapak fotoğrafı yüklenemedi. Lütfen tekrar deneyin.'
            : 'Fotoğraf yüklenemedi. Lütfen tekrar deneyin.',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _activeUpload = null;
        });
      }
    }
  }

  Future<void> _setCoverPhoto(BusinessPhoto photo) async {
    if (photo.isCover || _isUploading || _busy) return;
    setState(() => _busy = true);
    try {
      await BarbersRepo.instance.setCoverPhoto(photo.id);
      await _load(forceApi: true);
      _notifyChanged();
      _snack('Kapak fotoğrafı güncellendi.');
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteBusinessPhoto(BusinessPhoto photo) async {
    if (_isUploading || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Fotoğraf silinsin mi?'),
        content: const Text('Bu fotoğraf vitrinden kaldırılacak.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await BarbersRepo.instance.deletePhoto(photo.id);
      await _load(forceApi: true);
      _notifyChanged();
      _snack('Fotoğraf kaldırıldı.');
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildSettingsSummary() {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openPage(BarberProfilePage.settings),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.tune, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Profil Ayarları Özeti',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                ],
              ),
              const SizedBox(height: 14),
              _summaryRow('Hizmet alanı', '${_radiusKm.round()} km'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServicesSummary() {
    final preview = _services.take(3).toList();
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openPage(BarberProfilePage.services),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.storefront_outlined, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Hizmetler Özeti',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${_services.length} hizmet',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (preview.isEmpty)
                const Text(
                  'Henüz hizmet eklenmemiş.',
                  style: TextStyle(color: AppTheme.textSecondary),
                )
              else
                ...preview.map(
                  (service) => _summaryRow(
                    service.name,
                    '${service.price.toStringAsFixed(0)} TL',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  BusinessPhoto? get _coverPhoto {
    if (_photos.isEmpty) return null;
    return _photos.where((p) => p.isCover).firstOrNull ?? _photos.first;
  }

  BarberProfileCompletionResult get _storefrontCompletion {
    final input = BarberProfileCompletionInput(
      businessName: _businessName.text,
      category: _category.text,
      description: _description.text,
      addressLine: _addressLine.text,
      latitude: _lat,
      longitude: _lng,
      hasLogo: _logoBytes != null,
      hasGalleryOrCoverPhoto: _photos.isNotEmpty,
      hasActiveService: _services.isNotEmpty,
      hasValidWorkingHours: BarberProfileCompletionInput.validateWorkingHours(
        _workingHours,
      ),
    );
    return BarberProfileCompletion.calculateDetailed(input);
  }

  int get _storefrontScore {
    return _storefrontCompletion.percentage;
  }

  List<String> get _storefrontMissingItems {
    return _storefrontCompletion.missingItems;
  }

  String _absolutePhotoUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = AppConfig.baseUrl.endsWith('/')
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
        : AppConfig.baseUrl;
    return url.startsWith('/') ? '$base$url' : '$base/$url';
  }

  Widget _coverGradientFallback() => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF373737), Color(0xFF111111)],
      ),
    ),
  );

  Widget _buildVerificationCard() {
    return Builder(builder: (context) {
      final user = context.watch<AuthCubit>().state.user;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.verified_user_outlined, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hesap Doğrulama',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // E-posta doğrulama
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: (user?.emailVerified == true || user?.email?.isEmpty == true)
                    ? null
                    : () => VerificationSheets.showEmailVerification(context, user),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        user?.emailVerified == true
                            ? Icons.check_circle
                            : Icons.warning_amber_rounded,
                        size: 20,
                        color: user?.emailVerified == true
                            ? Colors.green
                            : Colors.orange,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'E-posta',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              user?.emailVerified == true
                                  ? 'Doğrulandı'
                                  : (user?.email?.isNotEmpty == true
                                      ? 'Doğrulanmadı — Doğrulamak için tıklayın'
                                      : 'E-posta tanımlı değil'),
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (user?.emailVerified != true && user?.email?.isNotEmpty == true)
                        const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              // Telefon doğrulama
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: user?.isPhoneVerified == true
                    ? null
                    : () => VerificationSheets.showPhoneVerification(context, user),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        user?.isPhoneVerified == true
                            ? Icons.check_circle
                            : Icons.warning_amber_rounded,
                        size: 20,
                        color: user?.isPhoneVerified == true
                            ? Colors.green
                            : Colors.orange,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Telefon',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              user?.isPhoneVerified == true
                                  ? 'Doğrulandı'
                                  : 'Doğrulanmadı — Doğrulamak için tıklayın',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (user?.isPhoneVerified != true)
                        const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildShowcaseGallery() {
    final photos = [..._photos]
      ..sort((a, b) {
        if (a.isCover != b.isCover) return a.isCover ? -1 : 1;
        return a.sortOrder.compareTo(b.sortOrder);
      });
    return Container(
      key: _galleryKey,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 12),
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
                  color: AppTheme.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.photo_library_outlined,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Vitrin Galerisi',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      photos.isEmpty
                          ? 'Kapak ve iş fotoğraflarınızı ekleyin.'
                          : '${photos.length}/12 fotoğraf yayında',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 92,
                height: 42,
                child: FilledButton.tonal(
                  onPressed: (_busy || _isUploading)
                      ? null
                      : () => _pickBusinessPhoto(isCover: photos.isEmpty),
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: (_activeUpload == _ProfileUploadKind.gallery)
                      ? Semantics(
                          label: 'İşletme fotoğrafı yükleniyor',
                          child: const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primary,
                            ),
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined, size: 17),
                            SizedBox(width: 5),
                            Text('Ekle'),
                          ],
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (photos.isEmpty)
            Container(
              height: 132,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFFAF8F6),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.10),
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      color: AppTheme.primary,
                      size: 34,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Müşteriye güven veren görseller ekleyin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 162,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final photo = photos[index];
                  return SizedBox(
                    width: 190,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            _absolutePhotoUrl(photo.url),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: AppTheme.fieldFill,
                              child: const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Color(0x99000000)],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 10,
                            bottom: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: photo.isCover
                                    ? AppTheme.primary
                                    : Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                photo.isCover ? 'Kapak' : 'Vitrin',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 8,
                            top: 8,
                            child: PopupMenuButton<String>(
                              tooltip: 'Fotoğraf seçenekleri',
                              color: Colors.white,
                              enabled: !_isUploading && !_busy,
                              onSelected: (value) {
                                if (value == 'cover') {
                                  _setCoverPhoto(photo);
                                } else if (value == 'delete') {
                                  _deleteBusinessPhoto(photo);
                                }
                              },
                              itemBuilder: (context) => [
                                if (!photo.isCover)
                                  const PopupMenuItem(
                                    value: 'cover',
                                    child: Text('Kapak yap'),
                                  ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Sil'),
                                ),
                              ],
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.more_horiz, size: 20),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    final status = _barberStatus;
    if (status == null || status == 'Approved') return const SizedBox.shrink();

    final isRejected = status == 'Rejected';
    final isPending = status == 'PendingApproval';
    final color = isRejected
        ? AppColors.error
        : isPending
            ? AppColors.warning
            : AppColors.primary;
    final icon = isRejected
        ? Icons.cancel_outlined
        : isPending
            ? Icons.hourglass_bottom_rounded
            : Icons.info_outline;
    final label = switch (status) {
      'PendingApproval' => 'Onay Bekliyor',
      'Rejected' => 'Reddedildi',
      'Onboarding' => 'Kurulum Aşamasında',
      _ => status,
    };
    final description = isRejected && _rejectionReason != null
        ? _rejectionReason!
        : isPending
            ? 'Profiliniz admin onayına gönderildi. Onay sonrası hizmet vermeye başlayabilirsiniz.'
            : 'Profil kurulumunuz devam ediyor. Tüm adımları tamamlayın.';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: color,
                    )),
                  const SizedBox(height: 4),
                  Text(description,
                    style: TextStyle(
                      color: color.withValues(alpha: 0.7),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorefrontHealthCard() {
    final score = _storefrontScore;
    final missing = _storefrontMissingItems.take(4).toList();
    final progress = (score / 100).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Row(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 750),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => SizedBox(
              width: 74,
              height: 74,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: value,
                    strokeWidth: 7,
                    strokeCap: StrokeCap.round,
                    backgroundColor: Colors.white.withValues(alpha: 0.13),
                    color: Colors.white,
                  ),
                  Text(
                    '${(value * 100).round()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vitrin sağlığı',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  missing.isEmpty
                      ? 'Profiliniz müşteriye güçlü görünüyor.'
                      : 'Eksikler: ${missing.join(', ')}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    StorefrontHealthPill('${_services.length} hizmet'),
                    StorefrontHealthPill('${_photos.length} fotoğraf'),
                    StorefrontHealthPill(
                      _category.text.trim().isEmpty
                          ? 'Kategori yok'
                          : _category.text.trim(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServicesHeroCard() {
    final activeCount = _services.length;
    final popularCount = _services.where((service) => service.isPopular).length;
    final avgPrice = _services.isEmpty
        ? 0.0
        : _services.fold<double>(
                0,
                (sum, service) => sum + service.price.toDouble(),
              ) /
              _services.length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: const Icon(
                  Icons.design_services_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hizmet vitrini',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Müşterinin satın alacağı işleri netleştirin.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isSmall = constraints.maxWidth < 280;
              if (isSmall) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _DarkMiniMetric(
                            value: '${_services.length}',
                            label: 'Toplam',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _DarkMiniMetric(
                            value: '$activeCount',
                            label: 'Aktif',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _DarkMiniMetric(
                            value: '$popularCount',
                            label: 'Popüler',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _DarkMiniMetric(
                            value: _services.isEmpty
                                ? '—'
                                : avgPrice.toStringAsFixed(0),
                            label: 'Ort. TL',
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: _DarkMiniMetric(
                      value: '${_services.length}',
                      label: 'Toplam',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DarkMiniMetric(
                      value: '$activeCount',
                      label: 'Aktif',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DarkMiniMetric(
                      value: '$popularCount',
                      label: 'Popüler',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DarkMiniMetric(
                      value: _services.isEmpty
                          ? '—'
                          : avgPrice.toStringAsFixed(0),
                      label: 'Ort. TL',
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

  @override
  Widget build(BuildContext context) {
    final location = _lat != null && _lng != null ? LatLng(_lat!, _lng!) : null;
    final coverPhoto = _coverPhoto;

    final loadingContent = ListView(
      padding: EdgeInsets.fromLTRB(20, 40, 20, widget.embedded ? 90 : 20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 20),
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Semantics(
                  label: 'İşletme profili yükleniyor',
                  child: const Text(
                    'İşletme profili yükleniyor...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );

    final errorContent = ListView(
      padding: EdgeInsets.fromLTRB(20, 40, 20, widget.embedded ? 90 : 20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.storefront_outlined,
                  color: AppTheme.primary,
                  size: 46,
                ),
                const SizedBox(height: 14),
                Semantics(
                  label: 'İşletme profili yüklenemedi',
                  child: const Text(
                    'İşletme profili yüklenemedi',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _loadError ?? 'Bağlantınızı kontrol edip tekrar deneyin.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  label: 'İşletme profilini tekrar yükle',
                  child: FilledButton.icon(
                    onPressed: _loading
                        ? null
                        : () {
                            setState(() {
                              _loading = true;
                              _loadError = null;
                            });
                            _load();
                          },
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('Tekrar Dene'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    final content = (_loading && !_hasData)
        ? loadingContent
        : _loadError != null
        ? errorContent
        : ListView(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(20, 20, 20, widget.embedded ? 90 : 20),
            children: [
              if (widget.page == BarberProfilePage.overview) ...[
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    height: 248,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (coverPhoto != null)
                          Image.network(
                            _absolutePhotoUrl(coverPhoto.url),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _coverGradientFallback(),
                          )
                        else
                          _coverGradientFallback(),
                        if (_activeUpload == _ProfileUploadKind.cover)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.5),
                              alignment: Alignment.center,
                              child: Semantics(
                                label: 'Kapak fotoğrafı yükleniyor',
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: Colors.white,
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Kapak fotoğrafı yükleniyor...',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0xD9000000)],
                              stops: [0.25, 1],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Material(
                            color: Colors.white.withValues(alpha: 0.92),
                            shape: const CircleBorder(),
                            child: IconButton(
                              tooltip: 'Kapak fotoğrafını değiştir',
                              onPressed: (_busy || _isUploading)
                                  ? null
                                  : () => _pickBusinessPhoto(isCover: true),
                              icon: const Icon(
                                Icons.add_photo_alternate_outlined,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Semantics(
                                label: _logoBytes == null
                                    ? 'İşletme logosu ekle'
                                    : 'İşletme logosunu değiştir',
                                child: GestureDetector(
                                  onTap: (_busy || _isUploading)
                                      ? null
                                      : _pickLogo,
                                  child: Container(
                                    width: 78,
                                    height: 78,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 3,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          blurRadius: 10,
                                          color: Colors.black38,
                                        ),
                                      ],
                                      image: _logoBytes == null
                                          ? null
                                          : DecorationImage(
                                              image: MemoryImage(_logoBytes!),
                                              fit: BoxFit.cover,
                                            ),
                                    ),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        if (_logoBytes == null &&
                                            _activeUpload !=
                                                _ProfileUploadKind.logo)
                                          const Icon(
                                            Icons.storefront,
                                            size: 32,
                                            color: AppTheme.primary,
                                          ),
                                        if (_activeUpload ==
                                            _ProfileUploadKind.logo)
                                          Container(
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(
                                                alpha: 0.4,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(17),
                                            ),
                                            alignment: Alignment.center,
                                            child: Semantics(
                                              label:
                                                  'İşletme logosu yükleniyor',
                                              child: const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2.5,
                                                      color: Colors.white,
                                                    ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _businessName.text.trim().isEmpty
                                            ? 'İşletmeniz'
                                            : _businessName.text.trim(),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 23,
                                          fontWeight: FontWeight.w800,
                                          height: 1.05,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      const Text(
                                        'İşletme profili',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _ProfileCompletionStrip(
                  score: _storefrontScore,
                  onTap: () => _openPage(BarberProfilePage.settings),
                ),
                const SizedBox(height: 18),
                ProfileOverviewGrid(
                  score: _storefrontScore,
                  serviceCount: _services.length,
                  photoCount: _photos.length,
                  radiusKm: _radiusKm.round(),
                ),
                const SizedBox(height: 18),
                ProfileQuickActions(
                  onServices: () => _openPage(BarberProfilePage.services),
                  onWorkingHours: _openWorkingHoursScreen,
                  workingHoursSubtitle: _todayWorkingHoursText,
                  onPhotos: _busy ? null : _scrollToGallery,
                  onReviews: widget.onOpenReviews,
                ),
                const SizedBox(height: 18),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (_category.text.trim().isNotEmpty) ...[
                              const Icon(
                                Icons.category_outlined,
                                color: AppTheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _category.text.trim(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ] else
                              const Spacer(),
                            Text(
                              switch (_serviceMode) {
                                'Onsite' => 'Yerinde',
                                'Both' => 'İkisi de',
                                _ => 'Adrese',
                              },
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        if (_description.text.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            _description.text.trim(),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (_addressLine.text.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                color: AppTheme.primary,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _addressLine.text.trim(),
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (_addressLine.text.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            _addressLine.text.trim(),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              height: 1.3,
                            ),
                          ),
                        ],
                        if (_badges.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _badges
                                .map(
                                  (badge) => Chip(
                                    label: Text(badge),
                                    avatar: const Icon(
                                      Icons.local_activity_outlined,
                                      size: 16,
                                      color: AppTheme.primary,
                                    ),
                                    side: BorderSide.none,
                                    backgroundColor: AppTheme.fieldFill,
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${_photos.length} vitrin fotoğrafı',
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: (_busy || _isUploading)
                                  ? null
                                  : () => _pickBusinessPhoto(
                                      isCover: _photos.isEmpty,
                                    ),
                              icon:
                                  (_activeUpload == _ProfileUploadKind.gallery)
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppTheme.primary,
                                      ),
                                    )
                                  : const Icon(Icons.add_photo_alternate),
                              label:
                                  (_activeUpload == _ProfileUploadKind.gallery)
                                  ? const Text('Yükleniyor...')
                                  : const Text('Fotoğraf Ekle'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (_barberStatus != null && _barberStatus != 'Approved')
                  _buildStatusBanner(),
                _buildStorefrontHealthCard(),
                const SizedBox(height: 14),
                _buildShowcaseGallery(),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 21),
                    const SizedBox(width: 7),
                    const Expanded(
                      child: Text(
                        'İşletme Konumu',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (location != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.fieldFill,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _usingDeviceLocation ? 'Mevcut Konum' : 'Kayıtlı',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: location == null
                      ? const SizedBox(
                          height: 150,
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.location_off_outlined,
                                    color: AppTheme.textSecondary,
                                    size: 34,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'İşletme konumu alınamadı.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : SizedBox(
                          height: 210,
                          child: FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: location,
                              initialZoom: 15,
                              keepAlive: true,
                              onTap: (_, point) {
                                setState(() {
                                  _lat = point.latitude;
                                  _lng = point.longitude;
                                  _usingDeviceLocation = false;
                                });
                              },
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName:
                                    'com.berbergelsin.berbergelsin',
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: location,
                                    width: 46,
                                    height: 46,
                                    child: const Icon(
                                      Icons.location_on,
                                      color: AppTheme.primary,
                                      size: 46,
                                      shadows: [
                                        Shadow(
                                          blurRadius: 8,
                                          color: Colors.black38,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Material(
                                    color: Colors.white,
                                    elevation: 2,
                                    shape: const CircleBorder(),
                                    child: IconButton(
                                      tooltip: 'Konumu yenile',
                                      onPressed: _locationBusy
                                          ? null
                                          : () => _loadCurrentLocation(
                                              showErrors: true,
                                            ),
                                      icon: _locationBusy
                                          ? const SizedBox.square(
                                              dimension: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.my_location,
                                              size: 20,
                                            ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  color: Colors.white.withValues(alpha: 0.82),
                                  child: const Text(
                                    '© OpenStreetMap',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                if (location == null)
                  TextButton.icon(
                    onPressed: _locationBusy
                        ? null
                        : () => _loadCurrentLocation(showErrors: true),
                    icon: _locationBusy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                    label: Text(
                      _locationBusy
                          ? 'Konum alınıyor...'
                          : 'Cihaz Konumunu Göster',
                    ),
                  ),
                if (location != null && _usingDeviceLocation)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Haritada cihazınızın mevcut konumu gösteriliyor.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
              ],
              if (widget.page != BarberProfilePage.overview)
                const SizedBox(height: 4),
              if (widget.page == BarberProfilePage.overview)
                const SizedBox(height: 24),
              if (widget.page == BarberProfilePage.settings) ...[
                _ProfileSectionHeader(
                  icon: Icons.badge_outlined,
                  title: 'Temel bilgiler',
                  description:
                      'Müşterinin ilk gördüğü ad, kategori ve açıklamayı düzenleyin.',
                ),
                const SizedBox(height: 14),
                const Text(
                  'İşletme Bilgileri',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Müşterilerin göreceği işletme adını düzenleyin.',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _businessName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'İşletme Adı'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: ServiceSelectionOptions.validOrNull(
                    _categoryOptions,
                    _category.text,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Kategori',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: [
                    for (final item in _categoryOptions)
                      DropdownMenuItem(
                        value: item,
                        child: Text(item, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _category.text = value ?? ''),
                ),

                const SizedBox(height: 12),
                TextField(
                  controller: _description,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'İşletme açıklaması',
                    hintText:
                        'Müşterilere hizmetlerinizi ve farkınızı anlatın.',
                  ),
                ),
                const SizedBox(height: 12),
                _ProfileSectionHeader(
                  icon: Icons.location_on_outlined,
                  title: 'İşletme adresi',
                  description:
                      'Backend adres aramasıyla adresi bulun, alanları ve harita konumunu doğrulayın.',
                ),
                const SizedBox(height: 14),
                AddressSearchField(
                  controller: _addressSearch,
                  enabled: !_busy,
                  onSelected: _applyResolvedAddress,
                ),
                const SizedBox(height: 14),
                AddressLineForm(
                  addressLine: _addressLine,
                  enabled: !_busy,
                ),
                if (_placeId != null || _formattedAddress != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Seçilen adresin koordinatını aşağıdaki haritada kontrol edin. Haritaya dokunarak marker konumunu düzeltebilirsiniz.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _serviceMode,
                  decoration: const InputDecoration(labelText: 'Hizmet şekli'),
                  items: const [
                    DropdownMenuItem(
                      value: 'Mobile',
                      child: Text(
                        'Adrese hizmet veriyorum',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'Onsite',
                      child: Text(
                        'Müşteri işletmeye gelir',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'Both',
                      child: Text(
                        'İkisi de uygun',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) =>
                            setState(() => _serviceMode = value ?? 'Mobile'),
                ),
                const SizedBox(height: 30),
                _ProfileSectionHeader(
                  icon: Icons.radar_rounded,
                  title: 'Hizmet alanı',
                  description:
                      'İşletmenizin hangi mesafeye kadar görünür olacağını belirleyin.',
                ),
                const SizedBox(height: 14),
                const Text(
                  'Hizmet Alanı',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'İşletmenizin hizmet vereceği mesafe: ${_radiusKm.round()} km',
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('1 km', style: TextStyle(fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: _radiusKm,
                        min: 1,
                        max: 30,
                        divisions: 29,
                        activeColor: AppTheme.primary,
                        label: '${_radiusKm.round()} km',
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _radiusKm = v),
                      ),
                    ),
                    const Text('30 km', style: TextStyle(fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 24),
                Semantics(
                  label: _busy
                      ? 'Kaydediliyor'
                      : (!_hasUnsavedProfileChanges ? 'Değişiklik yok' : null),
                  child: FilledButton(
                    onPressed: (_busy || !_hasUnsavedProfileChanges)
                        ? null
                        : _save,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Değişiklikleri Kaydet'),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (widget.page == BarberProfilePage.services) ...[
                _buildServicesHeroCard(),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Hizmetler',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : () => _editService(null),
                      icon: const Icon(Icons.add),
                      label: const Text('Ekle'),
                    ),
                  ],
                ),
                if (_services.isEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F3F3),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(Icons.add_business_outlined),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Henüz hizmet eklenmedi',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Müşterilerin ne sunduğunuzu görebilmesi için ilk hizmetinizi ekleyin.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _editService(null),
                          icon: const Icon(Icons.add),
                          label: const Text('Hizmet Ekle'),
                        ),
                      ],
                    ),
                  ),
                ..._services.map(
                  (s) => Card(
                    child: ListTile(
                      title: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              s.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (s.isPopular) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Popüler',
                                style: TextStyle(
                                  color: AppTheme.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '${s.price.toStringAsFixed(0)} TL',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              if (s.priceType != 'Fixed')
                                Text(
                                  s.priceType == 'Starts'
                                      ? '(Başlayan)'
                                      : '(${s.priceType})',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              if (s.durationMinutes != null)
                                Text(
                                  '• ${s.durationMinutes} dk',
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                          if (s.description?.isNotEmpty == true) ...[
                            const SizedBox(height: 6),
                            Text(
                              s.description!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: _busy ? null : () => _editService(s),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: Colors.red.shade400,
                            ),
                            onPressed: _busy ? null : () => _deleteService(s),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (widget.page == BarberProfilePage.overview) ...[
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: () => _openPage(BarberProfilePage.settings),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF111111),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Profili Düzenle'),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _logout,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Çıkış Yap'),
                ),
              ],
            ],
          );
    final mainWidget = widget.embedded
        ? content
        : Scaffold(
            appBar: AppBar(
              title: Text(switch (widget.page) {
                BarberProfilePage.overview => 'İşletme Profili',
                BarberProfilePage.settings => 'Profil Ayarları',
                BarberProfilePage.services => 'Hizmetler',
              }),
              actions: widget.page == BarberProfilePage.overview
                  ? [_buildMenuButton()]
                  : null,
            ),
            body: content,
          );

    return PopScope<Object?>(
      canPop: widget.page == BarberProfilePage.settings
          ? (!_hasUnsavedProfileChanges && !_isUploading)
          : !_isUploading,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_isUploading) {
          _snack(
            'Görsel yüklenirken sayfadan çıkılamaz. Lütfen bekleyin.',
            error: true,
          );
          return;
        }
        final shouldPop = await _showExitConfirmationDialog();
        if (shouldPop && context.mounted) {
          final navigator = Navigator.of(context);
          if (navigator.canPop()) {
            navigator.pop(result);
          }
        }
      },
      child: mainWidget,
    );
  }

  Widget _buildMenuButton() {
    return PopupMenuButton<String>(
      tooltip: 'İşletme menüsü',
      icon: const Icon(Icons.menu),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) {
        switch (value) {
          case 'logout':
            _logout();
          case 'services':
            _openPage(BarberProfilePage.services);
          case 'changePassword':
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ChangePasswordScreen(),
              ),
            );
          case 'notifications':
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const NotificationPreferencesScreen(),
              ),
            );
          case 'deleteAccount':
            _confirmDeleteAccount();
          default:
            _openPage(BarberProfilePage.settings);
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
          value: 'changePassword',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.lock_outlined),
            title: Text('Şifre Değiştir'),
          ),
        ),
        const PopupMenuItem(
          value: 'notifications',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.notifications_outlined),
            title: Text('Bildirim Tercihleri'),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'deleteAccount',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline, color: AppColors.error),
            title: Text('Hesabımı Sil',
                style: TextStyle(color: AppColors.error)),
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
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hesabımı Sil'),
        content: const Text(
          'Hesabınız ve işletme profiliniz silinecek. '
          'Bu işlem geri alınamaz.\n\n'
          'Devam etmek istiyor musunuz?',
        ),
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
            child: const Text('Hesabımı Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await context.read<AuthCubit>().deleteAccount();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: AppColors.error,
          ),
        );
    }
  }
}

class StorefrontHealthPill extends StatelessWidget {
  const StorefrontHealthPill(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ProfileCompletionStrip extends StatelessWidget {
  const _ProfileCompletionStrip({required this.score, required this.onTap});

  final int score;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = (score / 100).clamp(0.0, 1.0);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFECECEF)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 6,
                      strokeCap: StrokeCap.round,
                      backgroundColor: AppTheme.fieldFill,
                      color: AppTheme.primary,
                    ),
                    Text(
                      '%$score',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Profil Tamamlama',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Profilini tamamlayarak daha fazla müşteriye ulaşın.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileOverviewGrid extends StatelessWidget {
  const ProfileOverviewGrid({
    super.key,
    required this.score,
    required this.serviceCount,
    required this.photoCount,
    required this.radiusKm,
  });

  final int score;
  final int serviceCount;
  final int photoCount;
  final int radiusKm;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Genel Bakış',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ProfileOverviewTile(
                title: 'Hizmet',
                value: '$serviceCount',
                subtitle: 'Aktif hizmet',
                icon: Icons.storefront_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ProfileOverviewTile(
                title: 'Fotoğraf',
                value: '$photoCount',
                subtitle: 'Vitrin görseli',
                icon: Icons.photo_camera_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ProfileOverviewTile(
                title: 'Vitrin Puanı',
                value: '%$score',
                subtitle: 'Profil sağlığı',
                icon: Icons.star_outline_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ProfileOverviewTile(
                title: 'Hizmet Alanı',
                value: '$radiusKm km',
                subtitle: 'Yarıçap',
                icon: Icons.location_on_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class ProfileOverviewTile extends StatelessWidget {
  const ProfileOverviewTile({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFECECEF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              Icon(icon, size: 20, color: AppTheme.primary),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileQuickActions extends StatelessWidget {
  const ProfileQuickActions({
    super.key,
    required this.onServices,
    required this.onWorkingHours,
    this.workingHoursSubtitle,
    required this.onPhotos,
    this.onReviews,
  });

  final VoidCallback onServices;
  final VoidCallback onWorkingHours;
  final String? workingHoursSubtitle;
  final VoidCallback? onPhotos;
  final VoidCallback? onReviews;

  @override
  Widget build(BuildContext context) {
    final items = [
      ProfileQuickActionData(
        icon: Icons.shopping_bag_outlined,
        label: 'Hizmetlerim',
        onTap: onServices,
      ),
      ProfileQuickActionData(
        icon: Icons.schedule_outlined,
        label: 'Çalışma Saatleri',
        subtitle: workingHoursSubtitle,
        onTap: onWorkingHours,
      ),
      ProfileQuickActionData(
        icon: Icons.photo_camera_outlined,
        label: 'Fotoğraflarım',
        onTap: onPhotos,
      ),
      if (onReviews != null)
        ProfileQuickActionData(
          icon: Icons.chat_bubble_outline,
          label: 'Yorumlarım',
          onTap: onReviews,
        ),
    ];

    final List<List<ProfileQuickActionData>> chunks = [];
    for (var i = 0; i < items.length; i += 2) {
      chunks.add(items.sublist(i, i + 2 > items.length ? items.length : i + 2));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Hızlı İşlemler',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        for (var rowIndex = 0; rowIndex < chunks.length; rowIndex++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in chunks[rowIndex]) ...[
                Expanded(child: ProfileQuickActionTile(item: item)),
                if (item != chunks[rowIndex].last) const SizedBox(width: 8),
              ],
              if (chunks[rowIndex].length == 1) ...[
                const SizedBox(width: 8),
                const Expanded(child: SizedBox()),
              ],
            ],
          ),
          if (rowIndex < chunks.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class ProfileQuickActionData {
  const ProfileQuickActionData({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
}

class ProfileQuickActionTile extends StatelessWidget {
  const ProfileQuickActionTile({super.key, required this.item});

  final ProfileQuickActionData item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: item.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFECECEF)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, color: AppTheme.primary, size: 22),
              const SizedBox(height: 6),
              Text(
                item.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (item.subtitle != null && item.subtitle!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  item.subtitle!,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileSectionHeader extends StatelessWidget {
  const _ProfileSectionHeader({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
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
                    fontSize: 17,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
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

class _DarkMiniMetric extends StatelessWidget {
  const _DarkMiniMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileEditSnapshot {
  final String businessName;
  final String category;
  final String description;
  final String addressLine;
  final String serviceMode;
  final bool sharePhone;
  final bool acceptsOffers;
  final bool acceptsUrgentRequests;
  final double serviceRadiusKm;
  final double? lat;
  final double? lng;

  const ProfileEditSnapshot({
    required this.businessName,
    required this.category,
    required this.description,
    required this.addressLine,
    required this.serviceMode,
    required this.sharePhone,
    required this.acceptsOffers,
    required this.acceptsUrgentRequests,
    required this.serviceRadiusKm,
    this.lat,
    this.lng,
  });

  factory ProfileEditSnapshot.fromState({
    required String businessName,
    required String category,
    required String description,
    required String addressLine,
    required String serviceMode,
    required bool sharePhone,
    required bool acceptsOffers,
    required bool acceptsUrgentRequests,
    required double serviceRadiusKm,
    double? lat,
    double? lng,
  }) {
    return ProfileEditSnapshot(
      businessName: businessName,
      category: category,
      description: description,
      addressLine: addressLine,
      serviceMode: serviceMode,
      sharePhone: sharePhone,
      acceptsOffers: acceptsOffers,
      acceptsUrgentRequests: acceptsUrgentRequests,
      serviceRadiusKm: serviceRadiusKm,
      lat: lat,
      lng: lng,
    );
  }

  static bool _doubleEquals(double? a, double? b, {double tolerance = 1e-6}) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return (a - b).abs() < tolerance;
  }

  static String _normalize(String s) {
    return s.trim();
  }

  bool isDirty({
    required String businessName,
    required String category,
    required String description,
    required String addressLine,
    required String serviceMode,
    required bool sharePhone,
    required bool acceptsOffers,
    required bool acceptsUrgentRequests,
    required double serviceRadiusKm,
    double? lat,
    double? lng,
  }) {
    return _normalize(this.businessName) != _normalize(businessName) ||
        _normalize(this.category) != _normalize(category) ||
        _normalize(this.description) != _normalize(description) ||
        _normalize(this.addressLine) != _normalize(addressLine) ||
        this.serviceMode != serviceMode ||
        this.sharePhone != sharePhone ||
        this.acceptsOffers != acceptsOffers ||
        this.acceptsUrgentRequests != acceptsUrgentRequests ||
        !_doubleEquals(this.serviceRadiusKm, serviceRadiusKm, tolerance: 0.1) ||
        !_doubleEquals(this.lat, lat) ||
        !_doubleEquals(this.lng, lng);
  }
}
