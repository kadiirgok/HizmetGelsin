import 'dart:io';

import 'package:berbergelsin/core/theme/app_theme.dart';
import 'package:berbergelsin/features/map/data/barbers_repo.dart';
import 'package:berbergelsin/features/map/widgets/barber_sheet.dart';
import 'package:berbergelsin/features/requests/data/requests_repo.dart';
import 'package:berbergelsin/features/requests/screens/my_requests_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Creator implements ServiceRequestCreator {
  @override
  Future<ServiceRequestModel> create({
    required String barberProfileId,
    required List<String> serviceIds,
    required DateTime requestedTime,
    double? lat,
    double? lng,
    String? addressNote,
    String? addressId,
    String? serviceLocationType,
    required String idempotencyKey,
  }) async => ServiceRequestModel(
    id: '128b1234-1234-4234-8234-123456789012',
    barberProfileId: barberProfileId,
    barberBusinessName: 'Uzun İşletme Adı Hizmet Merkezi',
    status: 'Pending',
    requestedTime: requestedTime,
    lat: lat,
    lng: lng,
    totalPrice: 12500,
    items: const [],
    createdAt: DateTime.now(),
    canRate: false,
  );
}

class _Offers implements OffersRepository {
  _Offers(this.items);
  List<PriceOfferModel> items;
  @override
  Future<List<PriceOfferModel>> mine({CancelToken? cancelToken}) async => items;
  @override
  Future<OfferActionResult> action(
    String id,
    String action, {
    double? counterPrice,
    required String idempotencyKey,
  }) async => const OfferActionResult(status: 'Countered');
}

BarberDetail _detail() => BarberDetail(
  barberProfileId: 'business-128b',
  businessName: 'Uzun İşletme Adı Hizmet Merkezi',
  serviceMode: 'Both',
  workingHours:
      '[${List.generate(7, (i) => '{"day":${i + 1},"open":"00:00","close":"23:59","closed":false}').join(',')}]',
  acceptsOffers: false,
  services: [
    BarberServiceItem(
      id: 'service-1',
      name: 'Çok Uzun İsimli Kapsamlı Ev Bakım ve Profesyonel Temizlik Hizmeti',
      price: 12500,
      durationMinutes: 60,
    ),
    BarberServiceItem(id: 'service-2', name: 'Koltuk Temizliği', price: 1800),
  ],
);

PriceOfferModel _offer() => PriceOfferModel(
  id: 'offer-128b',
  barberProfileId: 'business-128b',
  barberBusinessName: 'Uzun İşletme Adı Hizmet Merkezi ve Profesyonel Ekip',
  proposedPrice: 98765,
  status: 'Pending',
  requestedTime: DateTime.now().add(const Duration(days: 2)),
  note:
      'Talebinizi inceledik. Uzun açıklamanızdaki bütün ayrıntıları randevu öncesinde birlikte kontrol edebiliriz.',
  createdAt: DateTime.now(),
  expiresAt: DateTime.now().add(const Duration(hours: 5)),
);

void main() {
  setUpAll(() async {
    final bytes = await File(
      r'.flutter-sdk-fast\flutter\bin\cache\artifacts\material_fonts\Roboto-Regular.ttf',
    ).readAsBytes();
    await (FontLoader('Roboto')..addFont(
          Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
        ))
        .load();
    final iconBytes = await File(
      r'.flutter-sdk-fast\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader('MaterialIcons')..addFont(
          Future.value(ByteData.view(Uint8List.fromList(iconBytes).buffer)),
        ))
        .load();
  });

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(Overlay), findsWidgets);
    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(Overlay).first,
        matchesGoldenFile('task128b/$name'),
      );
    }
  }

  testWidgets('renders current request flow screenshots', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light.copyWith(
          textTheme: AppTheme.light.textTheme.apply(fontFamily: 'Roboto'),
        ),
        home: RepaintBoundary(
          key: const Key('task128b-capture-root'),
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showBarberSheet(
                    context,
                    'business-128b',
                    41,
                    29,
                    initialDetail: _detail(),
                    requestCreator: _Creator(),
                  ),
                  child: const Text('Talep oluştur'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Talep oluştur'));
    await tester.pumpAndSettle();
    await capture(tester, 'request-service.png');
    await tester.tap(
      find.byKey(const ValueKey('barber-service-control-service-1')),
    );
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent * .62);
    await tester.pumpAndSettle();
    await capture(tester, 'request-location.png');
    await tester.tap(find.text('İşletmede'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Randevu Zamanı'));
    await tester.pumpAndSettle();
    await capture(tester, 'request-schedule.png');
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await capture(tester, 'request-summary.png');
    await tester.tap(find.text('Hizmet Talebi Oluştur'));
    await tester.pumpAndSettle();
    await capture(tester, 'request-success.png');
  });

  testWidgets('renders current offer screenshots', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light.copyWith(
          textTheme: AppTheme.light.textTheme.apply(fontFamily: 'Roboto'),
        ),
        home: RepaintBoundary(
          key: const Key('task128b-capture-root'),
          child: MyRequestsScreen(
            offersRepository: _Offers([_offer()]),
            requestsLoader: () async => [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tekliflerim'));
    await tester.pumpAndSettle();
    await capture(tester, 'offers-list.png');
    await tester.tap(find.text('Teklif Detayı'));
    await tester.pumpAndSettle();
    await capture(tester, 'offer-detail.png');
    await tester.tap(find.text('Karşı Teklif').last);
    await tester.pumpAndSettle();
    await capture(tester, 'counter-offer.png');
  });
}
