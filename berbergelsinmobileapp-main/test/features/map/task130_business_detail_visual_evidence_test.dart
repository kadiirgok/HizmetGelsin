import 'package:berbergelsin/features/favorites/data/favorites_repo.dart';
import 'package:berbergelsin/features/map/data/barbers_repo.dart';
import 'package:berbergelsin/features/map/screens/client_barber_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/visual_test_helper.dart';

class _DetailRepository implements BarberDetailRepository {
  @override
  Future<BarberDetail> detail(String id) async => BarberDetail(
    barberProfileId: id,
    businessName: 'Güvenilir Ev Hizmetleri',
    category: 'Temizlik',
    description: 'Eviniz için güvenilir, planlı ve özenli profesyonel hizmet.',
    serviceMode: 'Both',
    city: 'İstanbul',
    district: 'Kadıköy',
    workingHours: '[]',
    acceptsOffers: true,
    services: [
      BarberServiceItem(
        id: 'service-1',
        name: 'Detaylı ev temizliği',
        price: 1250,
        durationMinutes: 120,
      ),
    ],
    avgRating: 4.8,
    ratingCount: 124,
    isOpenNow: true,
    serviceRadiusKm: 15,
  );

  @override
  Future<BarberReviewsPage> reviews(
    String id, {
    int page = 1,
    int pageSize = 20,
  }) async => const BarberReviewsPage(
    items: [],
    page: 1,
    pageSize: 20,
    totalCount: 0,
    hasNextPage: false,
  );

  @override
  Future<BarberAvailabilitySummary> availability(
    String id,
    DateTime date,
  ) async => BarberAvailabilitySummary(
    barberProfileId: id,
    date: date,
    timeZone: 'Europe/Istanbul',
    isWorkingDay: true,
    isOpenNow: true,
    workingIntervals: const [AvailabilityInterval('09:00', '18:00')],
    precision: 'working_hours_only',
  );

  @override
  Future<List<int>> logoBytes(String id) async => const [];
}

class _FavoritesRepository implements FavoritesRepository {
  @override
  Future<FavoritePage> list({int page = 1, int pageSize = 20}) async =>
      FavoritePage(const [], page, false);
  @override
  Future<bool> status(String id) async => true;
  @override
  Future<void> add(String id) async {}
  @override
  Future<void> remove(String id) async {}
}

void main() {
  setUpAll(() async {
    await loadTestFonts();
  });

  testWidgets('renders final customer business detail evidence', (
    tester,
  ) async {
    configureVisualTestViewport(tester, width: 390, height: 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const key = Key('task130-business-detail');
    await tester.pumpWidget(
      buildVisualTestHarness(
        child: RepaintBoundary(
          key: key,
          child: ClientBarberDetailScreen(
            barberProfileId: 'business-1',
            repository: _DetailRepository(),
            favoritesRepository: _FavoritesRepository(),
            initialAvailabilityDate: DateTime(2026, 7, 19),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(key),
      matchesGoldenFile('task130/business-detail-final.png'),
    );
  });
}
