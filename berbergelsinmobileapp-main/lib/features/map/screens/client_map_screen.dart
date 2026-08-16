import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/customer_ui.dart';

import '../controllers/discovery_controller.dart';
import '../controllers/map_discovery_state.dart';
import '../data/barbers_repo.dart';
import '../widgets/client_bottom_navigation.dart';
import '../widgets/discovery_filter_sheet.dart';

class ClientMapScreen extends StatefulWidget {
  const ClientMapScreen({super.key});
  @override
  State<ClientMapScreen> createState() => _ClientMapScreenState();
}

class _ClientMapScreenState extends State<ClientMapScreen> with AutomaticKeepAliveClientMixin {
  final _mapController = MapController();
  final _mapState = MapDiscoveryState();
  final _discovery = DiscoveryController.shared;
  bool _loadingLocation = true, _disposed = false;
  String? _locationMessage;
  LatLng? _myLocation;

  @override bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _mapState.filters = _discovery.filters;
    _mapState.addListener(_rebuild);
    _discovery.addListener(_syncDiscovery);
    _initializeLocation();
  }

  void _rebuild() { if (mounted) setState(() {}); }

  void _syncDiscovery() {
    if (!mounted) return;
    if (_discovery.status == DiscoveryStatus.success || _discovery.status == DiscoveryStatus.empty || _discovery.status == DiscoveryStatus.loadingMore) {
      _mapState.setBusinesses(_discovery.items);
    }
    if (_discovery.status == DiscoveryStatus.error || _discovery.status == DiscoveryStatus.rateLimited) {
      _mapState.finishAreaSearch(safeError: _discovery.safeErrorMessage);
    }
    setState(() {});
  }

  Future<void> _initializeLocation() async {
    final sharedLat = _discovery.latitude; final sharedLng = _discovery.longitude;
    if (sharedLat != null && sharedLng != null) { await _useLocation(LatLng(sharedLat, sharedLng), fetch: false); await _load(refresh: true); return; }
    await _useDeviceLocation();
  }

  Future<void> _useDeviceLocation() async {
    setState(() { _loadingLocation = true; _locationMessage = null; });
    if (!await Geolocator.isLocationServiceEnabled()) { if (mounted) setState(() { _loadingLocation = false; _locationMessage = 'Konum servisi kapalı.'; }); return; }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) { if (mounted) setState(() { _loadingLocation = false; _locationMessage = 'Konum izni gerekli.'; }); return; }
    try { final pos = await Geolocator.getCurrentPosition(); await _useLocation(LatLng(pos.latitude, pos.longitude)); }
    catch (_) { if (mounted) setState(() { _loadingLocation = false; _locationMessage = 'Konum alınamadı.'; }); }
  }

  Future<void> _useLocation(LatLng loc, {bool fetch = true}) async {
    if (!mounted) return;
    _mapState.setInitialLocation(loc); _discovery.setLocation(loc.latitude, loc.longitude);
    setState(() { _myLocation = loc; _loadingLocation = false; _locationMessage = null; });
    WidgetsBinding.instance.addPostFrameCallback((_) { if (!_disposed) _mapController.move(loc, MapDiscoveryConfig.initialZoom); });
    if (fetch) await _load(refresh: _discovery.items.isNotEmpty);
  }

  Future<void> _load({required bool refresh}) async {
    await _discovery.load(refresh: refresh);
    if (!mounted) return; _mapState.setBusinesses(_discovery.items); _discovery.startAutoRefresh();
  }

  Future<void> _searchArea() async {
    final s = _mapState.beginAreaSearch(); _discovery.setLocation(s.center.latitude, s.center.longitude);
    final f = _mapState.filters;
    final filters = DiscoveryFilters(query: f.query, category: f.category, serviceId: f.serviceId, minPrice: f.minPrice, maxPrice: f.maxPrice, minRating: f.minRating, serviceMode: f.serviceMode, availableAt: f.availableAt, radiusKm: s.radiusKm, sort: f.sort);
    _mapState.setFilters(filters); await _discovery.applyFilters(filters);
    if (!mounted) return; _mapState.setBusinesses(_discovery.items);
    _mapState.finishAreaSearch(safeError: _discovery.status == DiscoveryStatus.error || _discovery.status == DiscoveryStatus.rateLimited ? _discovery.safeErrorMessage : null);
  }

  Future<void> _filters() async {
    final v = await showDiscoveryFilterSheet(context, _mapState.filters);
    if (v == null || !mounted) return; _mapState.setFilters(v); await _discovery.applyFilters(v); _mapState.setBusinesses(_discovery.items);
  }

  int get _activeFilterCount {
    final f = _mapState.filters;
    return [f.category, f.serviceId, f.minPrice, f.maxPrice, f.minRating, f.serviceMode, f.availableAt].where((v) => v != null).length;
  }

  String? _img(String? p) => p == null ? null : p.startsWith('http') ? p : '${AppConfig.baseUrl}$p';

  void _selectBusiness(NearbyBarber b) {
    _mapState.select(b.barberProfileId);
    if (!_disposed && hasValidBusinessCoordinate(b)) _mapController.move(LatLng(b.lat, b.lng), _mapState.mapZoom < 15 ? 15 : _mapState.mapZoom);
  }

  @override void dispose() { _disposed = true; _discovery.stopAutoRefresh(); _mapState.removeListener(_rebuild); _mapState.dispose(); _discovery.removeListener(_syncDiscovery); super.dispose(); }

  // ── BUILD ──────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: Column(children: [
        // ── Premium Header ──
        Container(
          padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 16, 10),
          decoration: const BoxDecoration(color: AppColors.background),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Keşfet', style: AppTypography.titleLarge.copyWith(fontSize: 24, letterSpacing: -0.3)),
              if (_mapState.mapCenter != null)
                Text('${_mapState.visibleBusinesses.length} işletme yakında', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
            ])),
            // Filtre butonu
            Material(
              color: _activeFilterCount > 0 ? AppColors.primary : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _filters,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(border: _activeFilterCount == 0 ? Border.all(color: const Color(0xFFECECEF)) : null, borderRadius: BorderRadius.circular(14)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.tune_rounded, size: 18, color: _activeFilterCount > 0 ? Colors.white : AppColors.textSecondary),
                    if (_activeFilterCount > 0) ...[const SizedBox(width: 6), Text('$_activeFilterCount', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))],
                  ]),
                ),
              ),
            ),
          ]),
        ),
        // ── Liste/Harita Toggle ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              _ToggleChip(icon: Icons.view_list_rounded, label: 'Liste', active: _mapState.mode == DiscoveryMapMode.list, onTap: () => _mapState.setMode(DiscoveryMapMode.list)),
              _ToggleChip(icon: Icons.map_rounded, label: 'Harita', active: _mapState.mode == DiscoveryMapMode.map, onTap: () => _mapState.setMode(DiscoveryMapMode.map)),
            ]),
          ),
        ),
        Expanded(child: _content()),
      ]),
      bottomNavigationBar: const ClientBottomNavigation(currentIndex: 1),
    );
  }

  Widget _content() {
    if (_loadingLocation) return const _ExploreSkeleton();
    if (_mapState.mapCenter == null) return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 72, height: 72, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.06), shape: BoxShape.circle), child: const Icon(Icons.location_searching_rounded, color: AppColors.primary, size: 32)),
      const SizedBox(height: 16), const Text('Konum gerekiyor', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 4), Text(_locationMessage ?? 'Yakındaki işletmeleri görmek için konum izni verin.', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      const SizedBox(height: 16), FilledButton.tonal(onPressed: _useDeviceLocation, child: const Text('Konumu Al')),
    ])));
    return AnimatedSwitcher(duration: AppDurations.fast, child: _mapState.mode == DiscoveryMapMode.list ? _listView() : _mapView());
  }

  Widget _listView() {
    final items = _mapState.visibleBusinesses;
    if (_discovery.status == DiscoveryStatus.loading && items.isEmpty) return const _ExploreSkeleton();
    if (items.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 72, height: 72, decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.storefront_outlined, color: AppColors.textSecondary, size: 32)),
      const SizedBox(height: 16), const Text('İşletme bulunamadı', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 4), const Text('Haritayı taşıyın veya filtreleri genişletin.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
    ])));
    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: items.length + (_discovery.hasNextPage ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == items.length) return Padding(padding: const EdgeInsets.all(20), child: Center(child: _discovery.status == DiscoveryStatus.loadingMore ? const CircularProgressIndicator() : FilledButton.tonal(onPressed: _discovery.loadMore, child: const Text('Daha fazla yükle'))));
          final b = items[i];
          return _VitrinCard(business: b, imageUrl: _img(b.coverPhotoUrl), onTap: () { context.push('/isletme/${b.barberProfileId}'); });
        },
      ),
    );
  }

  Widget _mapView() {
    final center = _mapState.mapCenter!;
    return Stack(children: [
      FlutterMap(
        mapController: _mapController,
        options: MapOptions(initialCenter: center, initialZoom: _mapState.mapZoom, minZoom: MapDiscoveryConfig.minZoom, maxZoom: MapDiscoveryConfig.maxZoom, onTap: (_, __) => _mapState.select(null), onPositionChanged: (c, h) { if (h) _mapState.moved(c.center, c.zoom); }),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.berbergelsin.berbergelsin'),
          MarkerLayer(markers: _markers()),
        ],
      ),
      // Bu alanda ara
      Positioned(top: 12, left: 0, right: 0, child: Center(child: AnimatedSwitcher(duration: AppDurations.fast, child: _mapState.canSearchArea
        ? GestureDetector(onTap: _searchArea, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.2), blurRadius: 12, offset: const Offset(0, 4))]), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.refresh_rounded, color: Colors.white, size: 18), const SizedBox(width: 6), Text('Bu alanda ara • ${MapDiscoveryConfig.radiusForZoom(_mapState.mapZoom).round()} km', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))])))
        : _mapState.isSearchingArea
        ? Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12)]), child: const Row(mainAxisSize: MainAxisSize.min, children: [SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 8), Text('Aranıyor…', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))]))
        : const SizedBox.shrink(),
      ))),
      // Seçili işletme kartı
      if (_mapState.selectedBusiness != null)
        Positioned(left: 12, right: 12, bottom: 12, child: _SelectedCard(business: _mapState.selectedBusiness!, onDetail: () => context.push('/isletme/${_mapState.selectedBusiness!.barberProfileId}'))),
    ]);
  }

  List<Marker> _markers() => [
    if (_myLocation != null) Marker(point: _myLocation!, width: 20, height: 20, child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary.withAlpha(50), border: Border.all(color: AppColors.primary, width: 2.5), boxShadow: [BoxShadow(color: AppColors.primary.withAlpha(80), blurRadius: 8, spreadRadius: 2)]))),
    for (final c in _mapState.clusters) Marker(point: c.center, width: c.isCluster ? 48 : 42, height: c.isCluster ? 48 : 42, child: c.isCluster
      ? GestureDetector(onTap: () => _mapController.move(c.center, (_mapState.mapZoom + 2).clamp(MapDiscoveryConfig.minZoom, MapDiscoveryConfig.maxZoom)), child: CircleAvatar(backgroundColor: AppColors.primary, foregroundColor: Colors.white, child: Text('${c.businesses.length}', style: AppTypography.labelLarge)))
      : _BizDot(b: c.businesses.single, sel: _mapState.selectedBusinessId == c.businesses.single.barberProfileId, onTap: () => _selectBusiness(c.businesses.single))),
  ];
}

// ── Mini Widgets ─────────────────────────────────────

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({required this.icon, required this.label, required this.active, required this.onTap});
  final IconData icon; final String label; final bool active; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(child: GestureDetector(onTap: onTap, child: AnimatedContainer(duration: AppDurations.fast, padding: const EdgeInsets.symmetric(vertical: 9), decoration: BoxDecoration(color: active ? AppColors.surface : Colors.transparent, borderRadius: BorderRadius.circular(12), boxShadow: active ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))] : null), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 17, color: active ? AppColors.primary : AppColors.textSecondary), const SizedBox(width: 6), Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: active ? AppColors.primary : AppColors.textSecondary))]))));
}

class _VitrinCard extends StatelessWidget {
  const _VitrinCard({required this.business, required this.onTap, this.imageUrl});
  final NearbyBarber business; final VoidCallback onTap; final String? imageUrl;

  static String _modeLabel(String? m) => m == 'Mobile' ? 'Adresinize gelir' : m == 'Onsite' ? 'İşletmeye gidilir' : 'Her ikisi de';
  static IconData _modeIcon(String? m) => m == 'Mobile' ? Icons.directions_car_rounded : m == 'Onsite' ? Icons.store_rounded : Icons.swap_horiz_rounded;

  @override
  Widget build(BuildContext context) {
    final hasCover = imageUrl?.isNotEmpty == true;
    final hasLogo = business.hasLogo && business.profileImageUrl?.isNotEmpty == true;
    final loc = [business.neighborhood, business.district].whereType<String>().where((e) => e.isNotEmpty).join(', ');
    final desc = business.description?.isNotEmpty == true ? business.description : null;
    final services = business.topServices?.isNotEmpty == true ? business.topServices! : null;
    final isOpen = business.isOpenNow == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFECECEF)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Kapak + Logo ──
          SizedBox(
            height: 140,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Kapak fotoğrafı
                if (hasCover)
                  Image.network(imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _CoverFallback(cat: business.category))
                else
                  _CoverFallback(cat: business.category),
                // Koyu gradient overlay
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xDD000000)],
                    ),
                  ),
                ),
                // Üst durum çubuğu (açık/kapalı + servis modu)
                Positioned(
                  top: 10, left: 12, right: 12,
                  child: Row(children: [
                    // Açık/Kapalı
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isOpen ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
                        const SizedBox(width: 5),
                        Text(isOpen ? 'Açık' : 'Kapalı', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    const Spacer(),
                    // Servis modu
                    if (business.serviceMode?.isNotEmpty == true)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(_modeIcon(business.serviceMode), size: 11, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(_modeLabel(business.serviceMode!), style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                  ]),
                ),
                // Logo (altta-solda)
                Positioned(
                  left: 14, bottom: 14,
                  child: Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8)],
                    ),
                    child: ClipOval(
                      child: hasLogo
                          ? Image.network(business.profileImageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _LogoFallback(cat: business.category))
                          : _LogoFallback(cat: business.category),
                    ),
                  ),
                ),
                // İsim (logo sağında)
                Positioned(
                  left: 74, bottom: 26,
                  child: Text(business.displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: -0.2)),
                ),
                // Kategori (isim altı)
                if (business.category?.isNotEmpty == true)
                  Positioned(
                    left: 74, bottom: 12,
                    child: Text(business.category!, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w500)),
                  ),
              ],
            ),
          ),
          // ── Kart alt bilgi ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Puan + mesafe + fiyat satırı
              Row(children: [
                if (business.avgRating != null) ...[
                  Icon(Icons.star_rounded, color: AppColors.warning, size: 16),
                  const SizedBox(width: 3),
                  Text(business.avgRating!.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.warning)),
                  if (business.ratingCount > 0)
                    Text(' (${business.ratingCount})', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(width: 12),
                ],
                Icon(Icons.near_me_rounded, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 3),
                Text(business.distanceMeters >= 1000 ? '${(business.distanceMeters / 1000).toStringAsFixed(1)} km' : '${business.distanceMeters.round()} m', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                const Spacer(),
                if (business.minimumPrice != null)
                  Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)), child: Text('₺${business.minimumPrice!.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
              ]),
              // Açıklama
              if (desc != null) ...[
                const SizedBox(height: 10),
                Text(desc!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
              ],
              // Servis chip'leri
              if (services != null) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6, runSpacing: 4,
                  children: services!.map((s) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                    child: Text('${s.name} ₺${s.price.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  )).toList(),
                ),
              ],
              // Konum
              if (loc.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(children: [Icon(Icons.location_on_outlined, size: 13, color: AppColors.textSecondary), const SizedBox(width: 3), Flexible(child: Text(loc, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500)))]),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

Color _catColor(String? c) {
  final l = (c ?? '').toLowerCase();
  if (l.contains('tesisat') || l.contains('su')) return const Color(0xFF1565C0);
  if (l.contains('elektrik')) return const Color(0xFFFF8F00);
  if (l.contains('temiz')) return const Color(0xFF00ACC1);
  if (l.contains('oto') || l.contains('ara')) return const Color(0xFFC62828);
  if (l.contains('ders') || l.contains('eğitim')) return const Color(0xFF7B1FA2);
  if (l.contains('kuaf') || l.contains('berber') || l.contains('güzellik')) return const Color(0xFF37474F);
  if (l.contains('nakliye') || l.contains('taşı')) return const Color(0xFF2E7D32);
  if (l.contains('sağlık') || l.contains('bakım')) return const Color(0xFFAD1457);
  if (l.contains('organizasyon')) return const Color(0xFF6A1B9A);
  if (l.contains('hayvan')) return const Color(0xFF8D6E63);
  if (l.contains('bahçe') || l.contains('peyzaj')) return const Color(0xFF43A047);
  if (l.contains('bilgisayar') || l.contains('teknik')) return const Color(0xFF455A64);
  if (l.contains('beyaz')) return const Color(0xFF795548);
  if (l.contains('inşaat') || l.contains('tadilat')) return const Color(0xFFBF360C);
  return const Color(0xFF546E7A);
}

IconData _catIco(String? c) {
  final l = (c ?? '').toLowerCase();
  if (l.contains('tesisat') || l.contains('su')) return Icons.plumbing_rounded;
  if (l.contains('elektrik')) return Icons.bolt_rounded;
  if (l.contains('temiz')) return Icons.cleaning_services_rounded;
  if (l.contains('oto') || l.contains('ara')) return Icons.car_repair_rounded;
  if (l.contains('ders') || l.contains('eğitim')) return Icons.school_rounded;
  if (l.contains('kuaf') || l.contains('berber') || l.contains('güzellik')) return Icons.content_cut_rounded;
  if (l.contains('nakliye') || l.contains('taşı')) return Icons.local_shipping_rounded;
  if (l.contains('sağlık') || l.contains('bakım')) return Icons.medical_services_rounded;
  if (l.contains('organizasyon')) return Icons.celebration_rounded;
  if (l.contains('hayvan')) return Icons.pets_rounded;
  if (l.contains('bahçe') || l.contains('peyzaj')) return Icons.yard_rounded;
  if (l.contains('bilgisayar') || l.contains('teknik')) return Icons.computer_rounded;
  if (l.contains('beyaz')) return Icons.devices_rounded;
  if (l.contains('inşaat') || l.contains('tadilat')) return Icons.construction_rounded;
  return Icons.handyman_rounded;
}

class _LogoFallback extends StatelessWidget {
  const _LogoFallback({required this.cat}); final String? cat;
  @override
  Widget build(BuildContext context) => Container(
    color: _catColor(cat),
    child: Center(child: Icon(_catIco(cat), size: 22, color: Colors.white)),
  );
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({required this.cat}); final String? cat;
  @override
  Widget build(BuildContext context) {
    final base = _catColor(cat);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(base, const Color(0xFF1A1A1C), 0.45)!, Color.lerp(base, const Color(0xFF1A1A1C), 0.75)!],
        ),
      ),
      child: Center(child: Icon(_catIco(cat), size: 48, color: Colors.white54)),
    );
  }
}

class _BizDot extends StatelessWidget {
  const _BizDot({required this.b, required this.sel, required this.onTap});
  final NearbyBarber b; final bool sel; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: AnimatedContainer(duration: AppDurations.fast, decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle, border: Border.all(color: sel ? AppColors.secondary : Colors.white, width: sel ? 3.5 : 2), boxShadow: AppShadows.card), child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 19)));
}

class _SelectedCard extends StatelessWidget {
  const _SelectedCard({required this.business, required this.onDetail});
  final NearbyBarber business; final VoidCallback onDetail;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFECECEF)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 24, offset: const Offset(0, 8))]),
    child: Row(children: [
      Container(width: 52, height: 52, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.storefront_rounded, color: AppColors.primary, size: 24)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(business.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 2),
        Row(children: [
          if (business.avgRating != null) ...[Icon(Icons.star_rounded, color: AppColors.warning, size: 14), const SizedBox(width: 2), Text(business.avgRating!.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.warning)), const SizedBox(width: 8)],
          if (business.distanceMeters > 0) Text(business.distanceMeters >= 1000 ? '${(business.distanceMeters / 1000).toStringAsFixed(1)} km' : '${business.distanceMeters.round()} m', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ]),
      ])),
      Material(color: AppColors.primary, borderRadius: BorderRadius.circular(12), child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onDetail, child: const Padding(padding: EdgeInsets.all(10), child: Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20)))),
    ]),
  );
}

class _ExploreSkeleton extends StatelessWidget {
  const _ExploreSkeleton();
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: const [
    SizedBox(height: 8), LoadingSkeleton(height: 80), SizedBox(height: 10),
    LoadingSkeleton(height: 80), SizedBox(height: 10),
    LoadingSkeleton(height: 80),
  ]);
}
