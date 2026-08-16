import 'package:berbergelsin/features/map/controllers/map_discovery_state.dart';
import 'package:berbergelsin/features/map/data/barbers_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

NearbyBarber business(String id, double lat, double lng, {bool? open}) =>
    NearbyBarber(
      barberProfileId: id,
      businessName: 'İşletme $id',
      category: 'Temizlik',
      lat: lat,
      lng: lng,
      acceptsOffers: false,
      distanceMeters: 500,
      isOpenNow: open,
    );

void main() {
  test('invalid and duplicate coordinates are excluded safely', () {
    final result = uniqueVisibleBusinesses([
      business('valid', 41, 29),
      business('zero', 0, 0),
      business('lat', 91, 29),
      business('lng', 41, 181),
      business('valid', 41.1, 29.1),
    ]);
    expect(result.map((e) => e.barberProfileId), ['valid']);
    expect(result.single.lat, 41.1);
  });

  test(
    'coordinate-less businesses remain available in list but not clusters',
    () {
      final state = MapDiscoveryState();
      final noCoordinate = business('no-coordinate', 0, 0);
      state.setBusinesses([noCoordinate, business('valid-list', 41, 29)]);
      expect(
        state.visibleBusinesses.map((e) => e.barberProfileId),
        containsAll(['no-coordinate', 'valid-list']),
      );
      expect(
        state.clusters.map((e) => e.businesses.single.barberProfileId),
        contains('valid-list'),
      );
      expect(
        state.clusters.expand((e) => e.businesses),
        isNot(contains(noCoordinate)),
      );
      state.dispose();
    },
  );

  test('nearby markers cluster at low zoom and separate at high zoom', () {
    final items = [
      business('a', 41.000, 29.000),
      business('b', 41.002, 29.002),
      business('c', 41.200, 29.200),
    ];
    final low = clusterBusinesses(items, 10);
    final high = clusterBusinesses(items, 17);
    expect(low.any((e) => e.businesses.length == 2), isTrue);
    expect(low.fold<int>(0, (sum, e) => sum + e.businesses.length), 3);
    expect(high, hasLength(3));
    expect(high.every((e) => !e.isCluster), isTrue);
  });

  test('map/list mode preserves filters, location and selection', () {
    final state = MapDiscoveryState();
    const filters = DiscoveryFilters(
      category: 'Temizlik',
      serviceId: 'service',
      minPrice: 100,
      maxPrice: 900,
      minRating: 4,
      radiusKm: 20,
    );
    state.setInitialLocation(const LatLng(41, 29));
    state.setFilters(filters);
    state.setBusinesses([business('a', 41, 29)]);
    state.select('a');
    state.setMode(DiscoveryMapMode.map);
    state.setMode(DiscoveryMapMode.list);
    expect(state.filters, same(filters));
    expect(state.searchCenter, const LatLng(41, 29));
    expect(state.selectedBusinessId, 'a');
    state.dispose();
  });

  test('moving map debounces search button and clamps radius', () async {
    final state = MapDiscoveryState();
    state.setInitialLocation(const LatLng(41, 29));
    state.moved(const LatLng(40, 28), 2);
    expect(state.canSearchArea, isFalse);
    await Future<void>.delayed(
      MapDiscoveryConfig.movementDebounce + const Duration(milliseconds: 30),
    );
    expect(state.canSearchArea, isTrue);
    final search = state.beginAreaSearch();
    expect(search.center, const LatLng(40, 28));
    expect(search.radiusKm, lessThanOrEqualTo(50));
    expect(state.isSearchingArea, isTrue);
    state.dispose();
  });

  test('failed area search preserves old markers and exposes safe error', () {
    final state = MapDiscoveryState();
    state.setInitialLocation(const LatLng(41, 29));
    state.setBusinesses([business('a', 41, 29)]);
    state.beginAreaSearch();
    state.finishAreaSearch(safeError: 'İşletmeler yüklenemedi.');
    expect(state.visibleBusinesses.single.barberProfileId, 'a');
    expect(state.mapError, 'İşletmeler yüklenemedi.');
    expect(state.isSearchingArea, isFalse);
    state.dispose();
  });

  test('selection can be cleared and disappears with result set', () {
    final state = MapDiscoveryState();
    state.setBusinesses([business('a', 41, 29)]);
    state.select('a');
    expect(state.selectedBusiness, isNotNull);
    state.select(null);
    expect(state.selectedBusiness, isNull);
    state.select('a');
    state.setBusinesses([business('b', 42, 30)]);
    expect(state.selectedBusinessId, isNull);
    state.dispose();
  });
}
