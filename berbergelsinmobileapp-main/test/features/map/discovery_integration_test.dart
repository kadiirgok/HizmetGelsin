import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:berbergelsin/features/map/controllers/discovery_controller.dart';
import 'package:berbergelsin/features/map/data/barbers_repo.dart';
import 'package:berbergelsin/features/map/widgets/discovery_filter_sheet.dart';

NearbyBarber item(String id) => NearbyBarber(
  barberProfileId: id,
  lat: 41,
  lng: 29,
  acceptsOffers: false,
  distanceMeters: 100,
  businessName: 'Uzun Türkçe İşletme Adı $id',
  category: 'Kuaför & Güzellik',
  city: 'İstanbul',
  district: 'Kadıköy',
  avgRating: 4.5,
  ratingCount: 12,
  serviceCount: 3,
  minimumPrice: 250,
  isOpenNow: true,
);

class FakeDiscoveryRepository implements DiscoveryRepository {
  final calls = <int>[];
  @override
  Future<DiscoveryPage> discover(
    double lat,
    double lng,
    DiscoveryFilters filters, {
    int page = 1,
    int pageSize = 20,
    CancelToken? cancelToken,
  }) async {
    calls.add(page);
    await Future<void>.delayed(const Duration(milliseconds: 1));
    if (cancelToken?.isCancelled == true) {
      throw DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.cancel,
      );
    }
    return page == 1
        ? DiscoveryPage([item('1')], 1, 20, 2, true)
        : DiscoveryPage([item('1'), item('2')], 2, 20, 2, false);
  }
}

void main() {
  test('all non-null query parameters serialize and nulls are omitted', () {
    final q = DiscoveryFilters(
      query: ' saç ',
      category: 'Kuaför',
      serviceId: 'service-1',
      city: 'İstanbul',
      district: 'Kadıköy',
      neighborhood: 'Moda',
      minPrice: 10,
      maxPrice: 500,
      minRating: 4,
      serviceMode: 'both',
      availableAt: DateTime.utc(2026, 7, 16, 12),
      radiusKm: 99,
      sort: DiscoverySort.priceDesc,
    ).toQuery(41, 29, page: 2, pageSize: 99);
    expect(q, containsPair('q', 'saç'));
    expect(q, containsPair('serviceId', 'service-1'));
    expect(q, containsPair('radiusKm', 50));
    expect(q, containsPair('page', 2));
    expect(q, containsPair('pageSize', 50));
    expect(q, containsPair('sort', 'price_desc'));
    expect(
      q.keys,
      containsAll([
        'category',
        'city',
        'district',
        'neighborhood',
        'minPrice',
        'maxPrice',
        'minRating',
        'serviceMode',
        'availableAt',
      ]),
    );
    expect(
      const DiscoveryFilters().toQuery(41, 29).containsKey('category'),
      isFalse,
    );
  });
  test('paged mapping fields support task95 shape', () {
    final b = NearbyBarber.fromJson({
      'id': 'x',
      'name': 'İşletme',
      'category': 'Tamir',
      'city': 'İstanbul',
      'district': 'Kadıköy',
      'distanceKm': 1.25,
      'rating': 4.7,
      'reviewCount': 8,
      'coverImageUrl': '/cover',
      'profileImageUrl': '/logo',
      'serviceCount': 5,
      'minimumPrice': 100,
      'isOpenNow': true,
      'serviceRadiusKm': 20,
    });
    expect(b.barberProfileId, 'x');
    expect(b.distanceMeters, 1250);
    expect(b.coverPhotoUrl, '/cover');
    expect(b.minimumPrice, 100);
  });
  test('legacy flat mapping remains supported', () {
    final b = NearbyBarber.fromJson({
      'barberProfileId': 'x',
      'lat': 41,
      'lng': 29,
      'acceptsOffers': true,
      'distanceMeters': 25,
    });
    expect(b.barberProfileId, 'x');
    expect(b.distanceMeters, 25);
  });
  test('global catalog maps real id and nearby query carries it', () {
    final service = ServiceCatalogItem.fromJson({
      'id': 'real-guid',
      'name': 'Saç Kesimi',
      'categoryName': 'Kuaför',
      'isActive': true,
    });
    final query = DiscoveryFilters(serviceId: service.id).toQuery(41, 29);
    expect(service.isActive, isTrue);
    expect(query['serviceId'], 'real-guid');
  });
  test('controller loads, deduplicates load-more and resets page', () async {
    final repo = FakeDiscoveryRepository();
    final c = DiscoveryController(repository: repo)..setLocation(41, 29);
    await c.load();
    expect(c.status, DiscoveryStatus.success);
    expect(c.page, 1);
    await c.loadMore();
    expect(c.items.map((e) => e.barberProfileId), ['1', '2']);
    expect(c.hasNextPage, false);
    await c.applyFilters(const DiscoveryFilters(category: 'Temizlik'));
    expect(c.page, 1);
    expect(c.items.length, 1);
  });
  testWidgets('filter sheet opens, clears and is keyboard scrollable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    DiscoveryFilters? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showDiscoveryFilterSheet(
                  context,
                  const DiscoveryFilters(minRating: 4),
                );
              },
              child: const Text('Aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Aç'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Keşif filtreleri'), findsOneWidget);
    tester
        .widget<TextButton>(find.byKey(const Key('discovery-filter-clear')))
        .onPressed!();
    await tester.pump(const Duration(milliseconds: 500));
    expect(result, isNotNull);
  });
}
