import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config.dart';
import '../../../core/theme/app_theme.dart';

import '../../../core/widgets/customer_ui.dart';
import '../data/barbers_repo.dart';
import '../controllers/discovery_controller.dart';
import '../widgets/client_bottom_navigation.dart';
import '../widgets/discovery_filter_sheet.dart';
import '../../notifications/widgets/notification_button.dart';
import '../../requests/data/requests_repo.dart';
import '../../auth/bloc/auth_cubit.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  final _search = TextEditingController();
  final _mapController = MapController();
  Timer? _searchDebounce;
  LatLng? _myLocation;
  List<NearbyBarber> _businesses = [];
  List<String> _categoryOptions = [];
  ServiceRequestModel? _upcomingAppointment;
  List<CategoryGroup> _categoryGroups = [];
  bool _catalogLoading = true;
  bool _appointmentLoading = true;
  String? _catalogError;
  String? _category;
  bool _loading = true;
  String? _error;
  final _discovery = DiscoveryController.shared;
  DiscoveryFilters _filters = const DiscoveryFilters();

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _discovery.addListener(_syncDiscovery);
    _init();
  }

  @override
  void dispose() {
    _search.dispose();
    _searchDebounce?.cancel();
    _discovery.removeListener(_syncDiscovery);
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    final query = _search.text.trim();
    if (query.isEmpty) {
      _load();
      return;
    }
    if (query.length < 2) return;
    _searchDebounce = Timer(const Duration(milliseconds: 450), _load);
  }

  void _syncDiscovery() {
    if (!mounted) return;
    setState(() {
      _businesses = _discovery.items;
      _loading =
          _discovery.status == DiscoveryStatus.loading ||
          _discovery.status == DiscoveryStatus.refreshing;
      _error = switch (_discovery.status) {
        DiscoveryStatus.error ||
        DiscoveryStatus.rateLimited ||
        DiscoveryStatus.locationPermissionRequired ||
        DiscoveryStatus.locationUnavailable => _discovery.safeErrorMessage,
        _ => null,
      };
    });
  }

  Future<void> _init() async {
    await Future.wait([
      _loadCategories(),
      _loadAppointment(),
    ]);
    await _resolveLocation();
    await _load();
  }

  Future<void> _loadCategories() async {
    try {
      final results = await Future.wait([
        BarbersRepo.instance.serviceCatalog(),
        BarbersRepo.instance.categoryGroups(),
      ]);
      final services = results[0] as List<ServiceCatalogItem>;
      final groups = results[1] as List<CategoryGroup>;
      final categories =
          services
              .map((e) => e.categoryName.trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      if (!mounted) return;
      setState(() {
        _categoryOptions = categories;
        _categoryGroups = groups;
        _catalogError = null;
        _catalogLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _catalogLoading = false;
          _catalogError = 'Hizmet kataloğu yüklenemedi.';
        });
      }
    }
  }

  Future<void> _loadAppointment() async {
    try {
      final now = DateTime.now();
      final items =
          (await RequestsRepo.instance.mine()).items
              .where((e) => e.isActive && e.requestedTime.isAfter(now))
              .toList()
            ..sort((a, b) => a.requestedTime.compareTo(b.requestedTime));
      if (mounted) {
        setState(() {
          _upcomingAppointment = items.firstOrNull;
          _appointmentLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _appointmentLoading = false);
    }
  }

  Future<void> _refreshHome() async {
    if (_loading) return;
    await Future.wait([
      _loadCategories(),
      _loadAppointment(),
      _load(),
    ]);
  }

  Future<void> _resolveLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }
    final pos = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    _myLocation = LatLng(pos.latitude, pos.longitude);
  }

  Future<void> _load() async {
    final loc = _myLocation;
    if (loc == null) {
      setState(() {
        _loading = false;
        _error = 'Yakındaki işletmeleri göstermek için konum izni gerekli.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _discovery.setLocation(loc.latitude, loc.longitude);
      _filters = DiscoveryFilters(
        query: _search.text,
        category: _category,
        serviceId: _filters.serviceId,
        minPrice: _filters.minPrice,
        maxPrice: _filters.maxPrice,
        minRating: _filters.minRating,
        serviceMode: _filters.serviceMode,
        availableAt: _filters.availableAt,
        radiusKm: _filters.radiusKm,
        sort: _filters.sort,
      );
      await _discovery.applyFilters(_filters);
      final list = _discovery.items;
      if (!mounted) return;
      setState(() {
        _businesses = list;
        _loading = false;
      });
      if (list.isNotEmpty) {
        _mapController.move(LatLng(list.first.lat, list.first.lng), 13);
      } else {
        _mapController.move(loc, 13);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'İşletmeler yüklenemedi. Lütfen tekrar deneyin.';
        });
      }
    }
  }

  void _openBusiness(NearbyBarber business) {
    context.push('/isletme/${business.barberProfileId}');
  }

  String _photoUrl(String path) =>
      path.startsWith('http') ? path : '${AppConfig.baseUrl}$path';

  Future<void> _openCategory(String category) async {
    setState(() => _category = category);
    await _load();
    if (mounted) context.go('/kesfet');
  }

  Future<void> _showSubCategories(CategoryGroup group) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => AppBottomSheet(
        title: group.name,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .55,
          child: ListView.separated(
            itemCount: group.categories.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
            itemBuilder: (_, i) {
              final sub = group.categories[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primaryContainer,
                  child: Icon(
                    _businessIcon(sub.name),
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                title: Text(sub.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(ctx);
                  _openCategory(sub.name);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showCategories() async {
    var query = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final visible = _categoryOptions
              .where((e) => e.toLowerCase().contains(query.toLowerCase()))
              .toList();
          return AppBottomSheet(
            title: 'Tüm kategoriler',
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .65,
              child: Column(
                children: [
                  SearchField(
                    hintText: 'Kategori ara',
                    onSubmitted: (value) =>
                        setSheetState(() => query = value.trim()),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Expanded(
                    child: visible.isEmpty
                        ? const EmptyState(
                            title: 'Kategori bulunamadı',
                            message: 'Arama metnini değiştirip tekrar deneyin.',
                          )
                        : ListView.builder(
                            itemCount: visible.length,
                            itemBuilder: (_, index) {
                              final category = visible[index];
                              return ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: AppColors.primaryContainer,
                                  child: Icon(
                                    Icons.handyman_outlined,
                                    color: AppColors.primary,
                                  ),
                                ),
                                title: Text(
                                  category,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: null,
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _openCategory(category);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showSearchResults() async {
    final query = _search.text.trim();
    if (query.isEmpty) {
      await _load();
      return;
    }
    if (query.length < 2) return;
    List<ServiceCatalogItem> services = const [];
    try {
      services = await BarbersRepo.instance.serviceCatalog(query: query);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Arama tamamlanamadı. Lütfen tekrar deneyin.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    final queryLower = query.toLowerCase();
    final categories = _categoryOptions
        .where((e) => e.toLowerCase().contains(queryLower))
        .toSet()
        .toList();
    final businesses = {
      for (final business in _businesses) business.barberProfileId: business,
    }.values.toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => AppBottomSheet(
        title: 'Arama sonuçları',
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .68,
          child: categories.isEmpty && services.isEmpty && businesses.isEmpty
              ? const EmptyState(
                  title: 'Sonuç bulunamadı',
                  message: 'Farklı bir hizmet, kategori veya işletme arayın.',
                  icon: Icons.search_off,
                )
              : ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    if (categories.isNotEmpty) ...[
                      const SectionHeader(title: 'Kategoriler'),
                      for (final category in categories)
                        ListTile(
                          leading: const Icon(Icons.category_outlined),
                          title: Text(category),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _openCategory(category);
                          },
                        ),
                    ],
                    if (services.isNotEmpty) ...[
                      const SectionHeader(title: 'Hizmetler'),
                      for (final service in services)
                        ServiceCard(
                          name: service.name,
                          category: service.categoryName,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _openCategory(service.categoryName);
                          },
                        ),
                    ],
                    if (businesses.isNotEmpty) ...[
                      const SectionHeader(title: 'İşletmeler'),
                      for (final business in businesses.take(10))
                        ListTile(
                          leading: const Icon(Icons.storefront_outlined),
                          title: Text(
                            business.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(business.category ?? 'Yerel hizmet'),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _openBusiness(business);
                          },
                        ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = _myLocation;
    final firstName = context.watch<AuthCubit>().state.user?.firstName?.trim();
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Text(
          firstName?.isNotEmpty == true ? 'Merhaba, $firstName' : 'Merhaba',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          const NotificationButton(),
          IconButton(
            key: const Key('open-discovery-filters'),
            tooltip: 'Filtreler',
            icon: const Icon(Icons.tune),
            onPressed: () async {
              final value = await showDiscoveryFilterSheet(context, _filters);
              if (value == null || !mounted) return;
              setState(() => _filters = value);
              await _load();
            },
          ),
          IconButton(
            tooltip: 'Haritayı büyüt',
            onPressed: () => context.go('/harita/tam'),
            icon: const Icon(Icons.map_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshHome,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
          children: [
            // ── Hoş geldin kartı ──
            _WelcomeCard(
              firstName: firstName,
              hasLocation: _myLocation != null,
            ),
            const SizedBox(height: 20),
            // ── Arama ──
            _ModernSearchBar(
              controller: _search,
              onSearch: _showSearchResults,
              onLocationTap: () async {
                await _resolveLocation();
                await _load();
              },
            ),
            const SizedBox(height: 14),
            SectionHeader(
              title: 'Kategoriler',
              actionLabel: 'Tümünü gör',
              onAction: _showCategories,
            ),
            const SizedBox(height: 8),
            if (_catalogLoading)
              const Row(
                children: [
                  LoadingSkeleton(height: 72, width: 80),
                  SizedBox(width: 10),
                  LoadingSkeleton(height: 72, width: 80),
                  SizedBox(width: 10),
                  LoadingSkeleton(height: 72, width: 80),
                ],
              )
            else if (_catalogError != null)
              ErrorState(message: _catalogError!, onRetry: _loadCategories)
            else if (_categoryOptions.isEmpty)
              const EmptyState(
                title: 'Kategori bulunamadı',
                message: 'Hizmet kataloğu şu anda boş görünüyor.',
              )
            else if (_categoryGroups.isNotEmpty)
              _CategoryGrid(
                groups: _categoryGroups.take(8).toList(),
                selected: _category,
                hasMore: _categoryGroups.length > 8,
                onGroupSelected: (group) => _showSubCategories(group),
                onShowAll: _showCategories,
              )
            else
              _CategoryGrid(
                categories: _categoryOptions.take(8).toList(),
                selected: _category,
                hasMore: _categoryOptions.length > 8,
                onSelected: (item) {
                  setState(() => _category = _category == item ? null : item);
                  _openCategory(item);
                },
                onShowAll: _showCategories,
              ),
            const SizedBox(height: 16),
            if (loc != null)
              _MapPreview(
                location: loc,
                businesses: _businesses,
                mapController: _mapController,
                onExpand: () => context.go('/harita/tam'),
                onTapBusiness: _openBusiness,
              )
            else
              EmptyState(
                title: 'Yakındaki işletmeleri görmek için adres seçin',
                message:
                    'Yakındaki işletmeleri görmek için konum izni verin.',
                icon: Icons.location_off_outlined,
                actionLabel: 'Konum ver',
                onAction: _resolveLocation,
              ),
            const SizedBox(height: 18),
            _ResultsHeader(
              total: _businesses.length,
              loading: _loading,
              category: _category,
              onHistory: () => context.go('/taleplerim'),
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _loading
                  ? const Padding(
                      key: ValueKey('loading'),
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: [
                          LoadingSkeleton(height: 128),
                          SizedBox(height: 12),
                          LoadingSkeleton(height: 20, width: 220),
                          SizedBox(height: 8),
                          LoadingSkeleton(height: 16),
                        ],
                      ),
                    )
                  : _error != null
                      ? _StateCard(
                          key: const ValueKey('error'),
                          message: _error!,
                          onRetry: _init,
                        )
                      : _businesses.isEmpty
                          ? _StateCard(
                              key: const ValueKey('empty'),
                              message:
                                  'Bu filtrelerle çevrimiçi işletme bulunamadı. Kategori veya bölgeyi genişletmeyi deneyin.',
                              onRetry: _load,
                            )
                          : Column(
                              key: const ValueKey('list'),
                              children: _businesses
                                  .take(6)
                                  .map(
                                    (b) => _BusinessCard(
                                      business: b,
                                      imageUrl: b.coverPhotoUrl == null
                                          ? null
                                          : _photoUrl(b.coverPhotoUrl!),
                                      onTap: () => _openBusiness(b),
                                    ),
                                  )
                                  .toList(),
                            ),
            ),
            if (_businesses.length > 6)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: TextButton(
                  onPressed: () => context.go('/kesfet'),
                  child: const Text('Tüm yakındaki işletmeleri gör'),
                ),
              ),
            const SizedBox(height: 18),
            if (_appointmentLoading) ...[
              const SizedBox(height: AppSpacing.lg),
              const LoadingSkeleton(height: 80),
            ] else if (_upcomingAppointment != null) ...[
              const SizedBox(height: AppSpacing.lg),
              SectionHeader(
                title: 'Yaklaşan randevu',
                actionLabel: 'Tüm randevular',
                onAction: () => context.go('/taleplerim'),
              ),
              AppointmentCard(
                businessName:
                    _upcomingAppointment!.barberBusinessName ?? 'İşletme',
                dateText:
                    '${_upcomingAppointment!.items.map((e) => e.serviceName).join(', ')} • ${_upcomingAppointment!.requestedTime.day}.${_upcomingAppointment!.requestedTime.month}.${_upcomingAppointment!.requestedTime.year} ${_upcomingAppointment!.requestedTime.hour.toString().padLeft(2, '0')}:${_upcomingAppointment!.requestedTime.minute.toString().padLeft(2, '0')}',
                status: _upcomingAppointment!.status,
                onTap: () => context.push('/talep/${_upcomingAppointment!.id}'),
              ),
            ],
            if (_discovery.hasNextPage)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton(
                  key: const Key('discovery-load-more'),
                  onPressed: _discovery.status == DiscoveryStatus.loadingMore
                      ? null
                      : _discovery.loadMore,
                  child: Text(
                    _discovery.status == DiscoveryStatus.loadingMore
                        ? 'Yükleniyor…'
                        : 'Daha fazla göster',
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: const ClientBottomNavigation(currentIndex: 0),
    );
  }
}

class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({
    required this.total,
    required this.loading,
    required this.onHistory,
    this.category,
  });

  final int total;
  final bool loading;
  final String? category;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final title = category?.isNotEmpty == true
        ? '$category işletmeleri'
        : 'Önerilen işletmeler';
    final summary = loading
        ? 'Sana en yakın uygun işletmeler aranıyor'
        : total == 0
        ? 'Filtreleri değiştirerek daha fazla işletme keşfedebilirsin'
        : '$total işletme bulundu';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FA),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFECECEF)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onHistory,
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: const Text('Geçmiş'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapPreview extends StatelessWidget {
  const _MapPreview({
    required this.location,
    required this.businesses,
    required this.mapController,
    required this.onExpand,
    required this.onTapBusiness,
  });

  final LatLng location;
  final List<NearbyBarber> businesses;
  final MapController mapController;
  final VoidCallback onExpand;
  final ValueChanged<NearbyBarber> onTapBusiness;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 210,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFECECEF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Harita
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: location,
              initialZoom: 13,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.berbergelsin.berbergelsin',
              ),
              MarkerLayer(
                markers: [
                  // Kullanıcı konumu
                  Marker(
                    point: location,
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // İşletme marker'ları
                  for (final b in businesses.take(15))
                    Marker(
                      point: LatLng(b.lat, b.lng),
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      child: GestureDetector(
                        onTap: () => onTapBusiness(b),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppColors.primary, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.storefront_rounded,
                            color: AppColors.primary,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          // Alt gradient overlay
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 60,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.15),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Tıklama overlay'i
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onExpand,
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          // Haritayı aç butonu
          Positioned(
            right: 10,
            bottom: 10,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: onExpand,
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_full_rounded,
                            size: 16, color: AppColors.primary),
                        SizedBox(width: 6),
                        Text(
                          'Harita',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
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

class _BusinessCard extends StatelessWidget {
  const _BusinessCard({
    required this.business,
    required this.onTap,
    this.imageUrl,
  });

  final NearbyBarber business;
  final VoidCallback onTap;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final location = [
      business.neighborhood,
      business.district,
      business.city,
    ].whereType<String>().where((e) => e.isNotEmpty).join(' / ');
    final category = business.category?.trim();
    final description = business.description?.trim();
    return _PremiumBusinessCardView(
      business: business,
      imageUrl: imageUrl,
      category: category,
      location: location,
      description: description,
      onTap: onTap,
    );
  }
}

class _PremiumBusinessCardView extends StatelessWidget {
  const _PremiumBusinessCardView({
    required this.business,
    required this.location,
    required this.onTap,
    this.imageUrl,
    this.category,
    this.description,
  });

  final NearbyBarber business;
  final String location;
  final VoidCallback onTap;
  final String? imageUrl;
  final String? category;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final hasCover = imageUrl?.isNotEmpty == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE9E9EC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 132,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasCover)
                      Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _BusinessCoverFallback(category: category),
                      )
                    else
                      _BusinessCoverFallback(category: category),
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
                      left: 16,
                      bottom: 14,
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.85),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.14),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Icon(
                          _businessIcon(category),
                          color: AppTheme.primary,
                          size: 26,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 14,
                      bottom: 16,
                      child: _MiniBadge(
                        icon: Icons.near_me_rounded,
                        text: _distanceLabel(business.distanceMeters),
                        dark: true,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            business.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (business.ratingCount > 0)
                          _MiniBadge(
                            icon: Icons.star_rounded,
                            text:
                                '${business.avgRating?.toStringAsFixed(1) ?? '-'} (${business.ratingCount})',
                          )
                        else
                          const _MiniBadge(
                            icon: Icons.auto_awesome_rounded,
                            text: 'Yeni',
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if ((category?.isNotEmpty ?? false) ||
                        location.isNotEmpty) ...[
                      Row(
                        children: [
                          if (category?.isNotEmpty ?? false)
                            Flexible(
                              child: _InfoLine(
                                icon: Icons.work_outline_rounded,
                                text: category!,
                              ),
                            ),
                          if ((category?.isNotEmpty ?? false) &&
                              location.isNotEmpty)
                            const SizedBox(width: 10),
                          if (location.isNotEmpty)
                            Expanded(
                              child: _InfoLine(
                                icon: Icons.location_on_outlined,
                                text: location,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (description?.isNotEmpty == true) ...[
                      Text(
                        description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF4E4E55),
                          height: 1.28,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        if (business.minimumPrice != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withAlpha(20),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '₺${business.minimumPrice!.toStringAsFixed(0)} başlayan',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Profili gör',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.icon, required this.text, this.dark = false});

  final IconData icon;
  final String text;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide.none,
      backgroundColor: dark
          ? Colors.black.withValues(alpha: 0.72)
          : AppTheme.fieldFill,
      avatar: Icon(
        icon,
        size: 15,
        color: dark ? Colors.white : AppTheme.primary,
      ),
      label: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: dark ? Colors.white : AppTheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _BusinessCoverFallback extends StatelessWidget {
  const _BusinessCoverFallback({this.category});

  final String? category;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF111111), Color(0xFF3A3A3C)],
        ),
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 22),
          child: Icon(_businessIcon(category), size: 64, color: Colors.white24),
        ),
      ),
    );
  }
}

String _distanceLabel(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

IconData _iconFromName(String name) => switch (name) {
    'plumbing_rounded' => Icons.plumbing_rounded,
    'bolt_rounded' => Icons.bolt_rounded,
    'build_rounded' => Icons.build_rounded,
    'cleaning_services_rounded' => Icons.cleaning_services_rounded,
    'local_shipping_rounded' => Icons.local_shipping_rounded,
    'car_repair_rounded' => Icons.car_repair_rounded,
    'content_cut_rounded' => Icons.content_cut_rounded,
    'health_and_safety_rounded' => Icons.health_and_safety_rounded,
    'school_rounded' => Icons.school_rounded,
    'event_rounded' => Icons.event_rounded,
    'pets_rounded' => Icons.pets_rounded,
    'yard_rounded' => Icons.yard_rounded,
    'computer_rounded' => Icons.computer_rounded,
    'construction_rounded' => Icons.construction_rounded,
    'kitchen_rounded' => Icons.kitchen_rounded,
    _ => Icons.handyman_rounded,
  };

IconData _businessIcon(String? category) {
  final value = category?.toLowerCase() ?? '';
  if (value.contains('tesisat')) return Icons.plumbing_rounded;
  if (value.contains('elektrik')) return Icons.bolt_rounded;
  if (value.contains('temiz')) return Icons.cleaning_services_rounded;
  if (value.contains('oto') || value.contains('araç')) {
    return Icons.car_repair_rounded;
  }
  if (value.contains('ders') || value.contains('eğitim')) {
    return Icons.school_rounded;
  }
  if (value.contains('kuaf') ||
      value.contains('berber') ||
      value.contains('güzellik')) {
    return Icons.content_cut_rounded;
  }
  if (value.contains('nakliye') || value.contains('taşı')) {
    return Icons.local_shipping_rounded;
  }
  return Icons.handyman_rounded;
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    this.categories = const [],
    this.groups = const [],
    required this.selected,
    required this.hasMore,
    this.onSelected,
    this.onGroupSelected,
    required this.onShowAll,
  });

  final List<String> categories;
  final List<CategoryGroup> groups;
  final String? selected;
  final bool hasMore;
  final ValueChanged<String>? onSelected;
  final ValueChanged<CategoryGroup>? onGroupSelected;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final useGroups = groups.isNotEmpty;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (useGroups)
          for (final g in groups)
            _CategoryCard(
              label: g.name,
              icon: g.icon != null
                  ? _iconFromName(g.icon!)
                  : _businessIcon(g.name),
              selected: g.name == selected,
              onTap: () => onGroupSelected?.call(g),
            )
        else
          for (final item in categories)
            _CategoryCard(
              label: item,
              icon: _businessIcon(item),
              selected: item == selected,
              onTap: () => onSelected?.call(item),
            ),
        if (hasMore)
          _CategoryCard(
            label: 'Tümü',
            icon: Icons.apps_rounded,
            selected: false,
            isMore: true,
            onTap: onShowAll,
          ),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.isMore = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool isMore;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : (isMore ? AppColors.primaryContainer : AppColors.surface),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : const Color(0xFFECECEF),
          ),
          boxShadow: selected
              ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.18), blurRadius: 12, offset: const Offset(0, 4))]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: selected ? Colors.white : AppColors.textSecondary),
            const SizedBox(height: 6),
            Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: selected ? Colors.white : AppColors.textPrimary, height: 1.2)),
          ],
        ),
      ),
    );
  }
}

// ── Welcome Card ──────────────────────────────────────────────────

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.firstName, required this.hasLocation});
  final String? firstName;
  final bool hasLocation;

  @override
  Widget build(BuildContext context) {
    final greeting = firstName?.isNotEmpty == true ? 'Merhaba, $firstName' : 'Merhaba';
    final initial = firstName?.isNotEmpty == true ? firstName!.substring(0, 1).toUpperCase() : '?';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1A1A1C), Color(0xFF2D2D30)]),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 30, offset: const Offset(0, 14))],
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF444448), Color(0xFF55555A)]), borderRadius: BorderRadius.circular(16)),
          child: Center(child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800))),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(greeting, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: Colors.white, height: 1.15)),
          const SizedBox(height: 3),
          Text('Bugün hangi hizmete ihtiyacın var?', style: TextStyle(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.6), fontWeight: FontWeight.w500)),
        ])),
      ]),
    );
  }
}

// ── Modern Search Bar ─────────────────────────────────────────────

class _ModernSearchBar extends StatelessWidget {
  const _ModernSearchBar({
    required this.controller,
    required this.onSearch,
    required this.onLocationTap,
  });

  final TextEditingController controller;
  final VoidCallback onSearch;
  final VoidCallback onLocationTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8E8EC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => onSearch(),
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Hizmet veya işletme ara...',
          hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.7), fontSize: 15),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 22),
          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            if (controller.text.isNotEmpty)
              IconButton(tooltip: 'Temizle', onPressed: () { controller.clear(); onSearch(); }, icon: const Icon(Icons.close_rounded, size: 20)),
            IconButton(tooltip: 'Konumumla', onPressed: onLocationTap, icon: const Icon(Icons.near_me_rounded, size: 20)),
          ]),
          filled: true,
          fillColor: AppColors.background,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Tekrar Dene')),
          ],
        ),
      ),
    );
  }
}
