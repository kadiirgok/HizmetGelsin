import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../data/barbers_repo.dart';

enum DiscoveryMapMode { list, map }

abstract final class MapDiscoveryConfig {
  static const minZoom = 5.0;
  static const maxZoom = 18.0;
  static const initialZoom = 13.0;
  static const maxRadiusKm = 50.0;
  static const movementDebounce = Duration(milliseconds: 350);

  static double radiusForZoom(double zoom) => switch (zoom) {
    >= 15 => 3,
    >= 13 => 8,
    >= 11 => 20,
    _ => maxRadiusKm,
  };
}

bool hasValidBusinessCoordinate(NearbyBarber business) =>
    business.lat >= -90 &&
    business.lat <= 90 &&
    business.lng >= -180 &&
    business.lng <= 180 &&
    !(business.lat == 0 && business.lng == 0);

class BusinessCluster {
  const BusinessCluster({required this.center, required this.businesses});
  final LatLng center;
  final List<NearbyBarber> businesses;
  bool get isCluster => businesses.length > 1;
}

List<NearbyBarber> uniqueVisibleBusinesses(Iterable<NearbyBarber> businesses) =>
    <String, NearbyBarber>{
      for (final item in businesses)
        if (hasValidBusinessCoordinate(item)) item.barberProfileId: item,
    }.values.toList(growable: false);

List<BusinessCluster> clusterBusinesses(
  Iterable<NearbyBarber> businesses,
  double zoom,
) {
  final visible = uniqueVisibleBusinesses(businesses);
  if (visible.isEmpty) return const [];
  if (zoom >= 16) {
    return [
      for (final item in visible)
        BusinessCluster(center: LatLng(item.lat, item.lng), businesses: [item]),
    ];
  }
  final cell = switch (zoom) {
    < 9 => .25,
    < 11 => .10,
    < 13 => .04,
    < 15 => .015,
    _ => .006,
  };
  final buckets = <String, List<NearbyBarber>>{};
  for (final item in visible) {
    final key = '${(item.lat / cell).floor()}:${(item.lng / cell).floor()}';
    buckets.putIfAbsent(key, () => []).add(item);
  }
  return buckets.values
      .map((items) {
        final lat =
            items.fold<double>(0, (sum, item) => sum + item.lat) / items.length;
        final lng =
            items.fold<double>(0, (sum, item) => sum + item.lng) / items.length;
        return BusinessCluster(center: LatLng(lat, lng), businesses: items);
      })
      .toList(growable: false);
}

class MapDiscoveryState extends ChangeNotifier {
  MapDiscoveryState({this.mode = DiscoveryMapMode.list});

  DiscoveryMapMode mode;
  LatLng? mapCenter;
  double mapZoom = MapDiscoveryConfig.initialZoom;
  LatLng? searchCenter;
  double searchRadius = 8;
  List<NearbyBarber> visibleBusinesses = const [];
  String? selectedBusinessId;
  List<BusinessCluster> clusters = const [];
  DiscoveryFilters filters = const DiscoveryFilters();
  bool isMoving = false;
  bool isSearchingArea = false;
  String? mapError;
  Timer? _movementTimer;

  NearbyBarber? get selectedBusiness => visibleBusinesses
      .where((item) => item.barberProfileId == selectedBusinessId)
      .firstOrNull;
  bool get canSearchArea => isMoving && mapCenter != null && !isSearchingArea;

  void setMode(DiscoveryMapMode value) {
    if (mode == value) return;
    mode = value;
    notifyListeners();
  }

  void setInitialLocation(LatLng center) {
    mapCenter ??= center;
    searchCenter ??= center;
    searchRadius = MapDiscoveryConfig.radiusForZoom(mapZoom);
    notifyListeners();
  }

  void setFilters(DiscoveryFilters value) {
    filters = value;
    notifyListeners();
  }

  void setBusinesses(Iterable<NearbyBarber> items) {
    // Keep coordinate-less businesses in the list; only marker generation
    // applies the coordinate validity gate.
    visibleBusinesses = <String, NearbyBarber>{
      for (final item in items) item.barberProfileId: item,
    }.values.toList(growable: false);
    if (selectedBusinessId != null &&
        !visibleBusinesses.any(
          (item) => item.barberProfileId == selectedBusinessId,
        )) {
      selectedBusinessId = null;
    }
    clusters = clusterBusinesses(visibleBusinesses, mapZoom);
    notifyListeners();
  }

  void select(String? businessId) {
    selectedBusinessId = businessId;
    notifyListeners();
  }

  void moved(LatLng center, double zoom) {
    mapCenter = center;
    mapZoom = zoom.clamp(
      MapDiscoveryConfig.minZoom,
      MapDiscoveryConfig.maxZoom,
    );
    clusters = clusterBusinesses(visibleBusinesses, mapZoom);
    _movementTimer?.cancel();
    _movementTimer = Timer(MapDiscoveryConfig.movementDebounce, () {
      isMoving = true;
      notifyListeners();
    });
  }

  ({LatLng center, double radiusKm}) beginAreaSearch() {
    final center = mapCenter;
    if (center == null) throw StateError('map_center_required');
    isSearchingArea = true;
    isMoving = false;
    mapError = null;
    searchCenter = center;
    searchRadius = MapDiscoveryConfig.radiusForZoom(
      mapZoom,
    ).clamp(1, MapDiscoveryConfig.maxRadiusKm);
    notifyListeners();
    return (center: center, radiusKm: searchRadius);
  }

  void finishAreaSearch({String? safeError}) {
    isSearchingArea = false;
    mapError = safeError;
    notifyListeners();
  }

  @override
  void dispose() {
    _movementTimer?.cancel();
    super.dispose();
  }
}
