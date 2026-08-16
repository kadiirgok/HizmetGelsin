import 'dart:convert';

import 'package:berbergelsin/features/addresses/data/client_addresses_repo.dart';
import 'package:berbergelsin/features/map/data/barbers_repo.dart';
import 'package:berbergelsin/features/map/widgets/barber_sheet.dart';
import 'package:berbergelsin/features/map/widgets/barber_sheet/barber_sheet_hero.dart';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';

class _FakeAddressesRepository implements ClientAddressesRepository {
  _FakeAddressesRepository(this.items);
  final List<ClientAddress> items;
  int calls = 0;
  @override
  Future<List<ClientAddress>> list() async {
    calls++;
    return items;
  }

  @override
  Future<ClientAddress> get(String id) => throw UnimplementedError();
  @override
  Future<ClientAddress> create(ClientAddress value) =>
      throw UnimplementedError();
  @override
  Future<ClientAddress> update(ClientAddress value) =>
      throw UnimplementedError();
  @override
  Future<void> delete(String id) => throw UnimplementedError();
  @override
  Future<ClientAddress> setDefault(String id) => throw UnimplementedError();
}

void main() {
  BarberDetail detail({
    bool includePhone = true,
    List<BarberServiceItem>? services,
    String? businessName,
    List<BusinessPhoto> photos = const [],
    List<BarberReview> reviews = const [],
    String? description,
    List<String> badges = const [],
  }) => BarberDetail(
    barberProfileId: 'profile-1',
    businessName: businessName ?? 'Test İşletmesi',
    category: 'Berber',
    description: description,
    badges: badges,
    city: 'İstanbul',
    district: 'Beşiktaş',
    workingHours: jsonEncode([
      for (var day = 1; day <= 7; day++)
        {
          'day': day,
          'open': day == 6 ? '10:00' : '09:00',
          'close': day == 6 ? '18:00' : '20:00',
          'closed': day == 7,
        },
    ]),
    acceptsOffers: false,
    phoneNumber: includePhone ? '5550000000' : null,
    photos: photos,
    reviews: reviews,
    services:
        services ??
        List.generate(
          8,
          (index) => BarberServiceItem(
            id: 'service-$index',
            name: 'Hizmet ${index + 1}',
            price: 100 + index.toDouble(),
            durationMinutes: 30,
          ),
        ),
  );

  Future<void> openPreview(
    WidgetTester tester, {
    double width = 390,
    BarberDetail? initialDetail,
    bool previewOnly = true,
    double textScale = 1,
    ClientAddressesRepository? addressesRepository,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showBarberSheet(
                context,
                'profile-1',
                0,
                0,
                previewOnly: previewOnly,
                initialDetail: initialDetail ?? detail(),
                addressesRepository: addressesRepository,
              ),
              child: const Text('Önizlemeyi Aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Önizlemeyi Aç'));
    await tester.pumpAndSettle();
  }

  testWidgets('preview scroll reaches working hours and final day', (
    tester,
  ) async {
    await openPreview(tester);

    expect(find.text('Hizmetler', skipOffstage: false), findsOneWidget);
    expect(find.text('Hizmet 1', skipOffstage: false), findsOneWidget);

    await tester.fling(
      find.byType(ListView).first,
      const Offset(0, -5000),
      5000,
    );
    await tester.pumpAndSettle();
    expect(find.text('Çalışma Saatleri'), findsOneWidget);
    expect(find.text('Pazar'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('working-hours-toggle')));
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Pazar'), findsOneWidget);
    expect(find.text('Kapalı'), findsOneWidget);
    expect(
      scrollable.position.pixels,
      closeTo(scrollable.position.maxScrollExtent, 0.1),
    );
  });

  testWidgets('request form uses the address selected on customer home', (
    tester,
  ) async {
    final home = ClientAddress(
      id: 'home',
      label: 'Ev',
      addressLine: 'Ev adresi',
      latitude: 41,
      longitude: 29,
      isDefault: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      version: 'v1',
      province: 'İstanbul',
      district: 'Kadıköy',
    );
    final work = ClientAddress(
      id: 'work',
      label: 'İş',
      addressLine: 'İş adresi',
      latitude: 41.1,
      longitude: 29.1,
      isDefault: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      version: 'v1',
      province: 'İstanbul',
      district: 'Beşiktaş',
    );
    CustomerAddressSelectionStore.instance.select(work);
    addTearDown(CustomerAddressSelectionStore.instance.clearSession);

    final repository = _FakeAddressesRepository([home, work]);
    await openPreview(
      tester,
      width: 600,
      previewOnly: false,
      addressesRepository: repository,
    );
    expect(repository.calls, 1);
    expect(CustomerAddressSelectionStore.instance.selectedAddressId, 'work');
    final picker = find.byKey(
      const Key('saved-address-picker'),
      skipOffstage: false,
    );
    for (var i = 0; i < 12 && picker.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -450));
      await tester.pumpAndSettle();
    }
    expect(picker, findsOneWidget);
    await tester.scrollUntilVisible(
      picker,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.bySemanticsLabel(RegExp(r'İş.*seçili')), findsOneWidget);
  });

  testWidgets('320 px preview has no overflow and closes with one pop', (
    tester,
  ) async {
    await openPreview(tester, width: 320);
    expect(tester.takeException(), isNull);

    Navigator.of(tester.element(find.byType(BarberSheetHero))).pop();
    await tester.pumpAndSettle();

    expect(find.text('Önizlemeyi Aç'), findsOneWidget);
    expect(find.text('Müşteri görünümü önizlemesi'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview closes and reopens without losing cover source state', (
    tester,
  ) async {
    final coverDetail = detail(
      photos: [
        BusinessPhoto(
          id: 'selected-cover',
          url: 'https://example.invalid/selected-cover.jpg',
          isCover: true,
        ),
      ],
    );
    await openPreview(tester, initialDetail: coverDetail);
    expect(find.byType(BarberSheetHero), findsOneWidget);
    Navigator.of(tester.element(find.byType(BarberSheetHero))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.byType(BarberSheetHero), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets('${width.toInt()} px preview has no overflow', (tester) async {
      await openPreview(tester, width: width);
      expect(tester.takeException(), isNull);
    });
  }

  group('BarberSheet preview characterization', () {
    testWidgets('banner form checkbox and phone behavior stay unchanged', (
      tester,
    ) async {
      await openPreview(tester);
      expect(find.text('Müşteri görünümü önizlemesi'), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('barber-preview-banner')))
            .height,
        inInclusiveRange(56, 72),
      );
      expect(
        find.text('Hizmet Talebi Oluştur', skipOffstage: false),
        findsNothing,
      );
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(
        find.byKey(const ValueKey('barber-service-selection-indicator')),
        findsNothing,
      );
      expect(find.byTooltip('Ara'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await openPreview(tester, initialDetail: detail(includePhone: false));
      expect(find.byTooltip('Ara'), findsNothing);
    });

    testWidgets('one primary vertical scroll keeps sections reachable', (
      tester,
    ) async {
      await openPreview(tester);
      final vertical = tester
          .widgetList<Scrollable>(find.byType(Scrollable))
          .where((w) => w.axisDirection == AxisDirection.down);
      expect(vertical, hasLength(1));
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('Hizmetler', skipOffstage: false), findsOneWidget);
      expect(
        find.text('Çalışma Saatleri', skipOffstage: false),
        findsOneWidget,
      );
    });
  });

  group('BarberSheet customer mode characterization', () {
    testWidgets('service selection and request form remain available', (
      tester,
    ) async {
      await openPreview(tester, width: 600, previewOnly: false);
      expect(find.byTooltip('Ara'), findsOneWidget);
      final firstService = find.byKey(
        const ValueKey('barber-service-control-service-0'),
      );
      expect(firstService, findsOneWidget);
      expect(
        tester.getSemantics(firstService).flagsCollection.isSelected,
        Tristate.isFalse,
      );
      await tester.tap(firstService);
      await tester.pump();
      expect(
        tester.getSemantics(firstService).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        find.text('Hizmet Talebi Oluştur', skipOffstage: false),
        findsOneWidget,
      );
    });
  });

  group('BarberSheet section extraction regression', () {
    testWidgets('long identity and service remain safe at 320 px', (
      tester,
    ) async {
      await openPreview(
        tester,
        width: 320,
        initialDetail: detail(
          businessName:
              'Çok Uzun İsimli Profesyonel Mobil Teknik Servis İşletmesi',
          services: [
            BarberServiceItem(
              id: 'long',
              name:
                  'Çok uzun açıklamalı kapsamlı yerinde bakım ve onarım hizmeti',
              price: 6000000,
              durationMinutes: 120,
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('BarberSheet hero identity and action hierarchy', () {
    testWidgets('identity fields and logo fallback render only once', (
      tester,
    ) async {
      await openPreview(tester);
      expect(find.text('Test İşletmesi'), findsOneWidget);
      expect(find.textContaining('Berber'), findsOneWidget);
      expect(find.textContaining('Beşiktaş / İstanbul'), findsOneWidget);
      expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
      final semantics = tester.getSemantics(find.text('Test İşletmesi'));
      expect(semantics.flagsCollection.isHeader, isTrue);
    });

    testWidgets('compact hero stays within target height', (tester) async {
      await openPreview(tester, width: 390);
      final height = tester.getSize(find.byType(BarberSheetHero)).height;
      expect(height, inInclusiveRange(215, 280));
    });

    testWidgets('unresolved cover keeps stable fallback and compact logo', (
      tester,
    ) async {
      await openPreview(
        tester,
        initialDetail: detail(
          photos: [
            BusinessPhoto(
              id: 'cover',
              url: 'https://example.invalid/cover.jpg',
              isCover: true,
            ),
          ],
        ),
      );
      expect(find.byType(BarberSheetHero), findsOneWidget);
      expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('preview phone visibility is passive information', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await openPreview(
        tester,
        initialDetail: detail(
          description: 'Teknik servis',
          badges: const ['Telefonla Ulaşılabilir'],
        ),
      );
      expect(find.text('Telefon müşterilere görünür'), findsOneWidget);
      expect(find.byTooltip('Ara'), findsNothing);
      final phoneStatusSemantics = find.ancestor(
        of: find.text('Telefon müşterilere görünür', skipOffstage: false),
        matching: find.byType(Semantics),
      );
      expect(phoneStatusSemantics, findsWidgets);
      expect(
        tester.widget<Semantics>(phoneStatusSemantics.first).properties.button,
        isNot(true),
      );
      semantics.dispose();
    });

    testWidgets('gallery follows hero and description remains available', (
      tester,
    ) async {
      await openPreview(
        tester,
        initialDetail: detail(
          description: 'Uzman teknik servis açıklaması',
          photos: [
            BusinessPhoto(
              id: 'photo',
              url: 'https://example.invalid/photo.jpg',
              isCover: true,
            ),
          ],
        ),
      );
      expect(
        find.text('Uzman teknik servis açıklaması', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('barber-photo-gallery')), findsNothing);
      expect(
        tester.getTopLeft(find.text('Uzman teknik servis açıklaması')).dy,
        greaterThan(tester.getBottomLeft(find.byType(BarberSheetHero)).dy),
      );
    });

    testWidgets('customer call action is single and follows privacy', (
      tester,
    ) async {
      await openPreview(tester, width: 600, previewOnly: false);
      expect(find.byTooltip('Ara'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await openPreview(
        tester,
        width: 600,
        previewOnly: false,
        initialDetail: detail(includePhone: false),
      );
      expect(find.byTooltip('Ara'), findsNothing);
    });

    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      testWidgets(
        '${width.toInt()} px hero is overflow safe at 1.3 text scale',
        (tester) async {
          await openPreview(
            tester,
            width: width,
            textScale: 1.3,
            initialDetail: detail(
              businessName:
                  'Çok Uzun İsimli Profesyonel Mobil Teknik Servis İşletmesi',
            ),
          );
          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byType(BarberSheetHero)).height,
            lessThanOrEqualTo(360),
          );
        },
      );
    }
  });

  group('BarberSheet gallery and public review integration', () {
    final publicReviews = [
      BarberReview(
        score: 5,
        clientName: 'Birinci Müşteri',
        comment: 'Birinci yorum',
        createdAt: DateTime(2026, 7, 12),
      ),
      BarberReview(
        score: 4,
        clientName: 'İkinci Müşteri',
        comment: 'İkinci yorum',
        createdAt: DateTime(2026, 7, 11),
      ),
      BarberReview(
        score: 3,
        clientName: 'Üçüncü Müşteri',
        comment: 'Üçüncü yorum',
        createdAt: DateTime(2026, 7, 10),
      ),
    ];
    final publicPhotos = [
      BusinessPhoto(
        id: 'cover',
        url: 'https://example.invalid/cover.jpg',
        isCover: true,
      ),
      BusinessPhoto(
        id: 'gallery-one',
        url: 'https://example.invalid/gallery-one.jpg',
      ),
      BusinessPhoto(
        id: 'gallery-two',
        url: 'https://example.invalid/gallery-two.jpg',
      ),
    ];

    testWidgets('preview shows deduplicated gallery and at most two reviews', (
      tester,
    ) async {
      await openPreview(
        tester,
        initialDetail: detail(photos: publicPhotos, reviews: publicReviews),
      );

      expect(find.text('2 fotoğraf', skipOffstage: false), findsOneWidget);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -1500));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('barber-gallery-photo-cover')),
        findsNothing,
      );
      expect(find.text('Birinci Müşteri', skipOffstage: false), findsOneWidget);
      expect(find.text('İkinci Müşteri', skipOffstage: false), findsOneWidget);
      expect(find.text('Üçüncü Müşteri', skipOffstage: false), findsNothing);
      expect(
        find.text('Hizmet Talebi Oluştur', skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets('customer uses same public summary before request form', (
      tester,
    ) async {
      await openPreview(
        tester,
        width: 600,
        previewOnly: false,
        initialDetail: detail(photos: publicPhotos, reviews: publicReviews),
      );

      expect(find.text('2 fotoğraf', skipOffstage: false), findsOneWidget);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -1500));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(find.text('Birinci Müşteri', skipOffstage: false), findsOneWidget);
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final reviewOffset = scrollable.position.pixels;
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        find.text('Hizmet Talebi Oluştur', skipOffstage: false),
        findsOneWidget,
      );
      expect(scrollable.position.pixels, greaterThanOrEqualTo(reviewOffset));
      expect(find.textContaining('Tüm yorum'), findsNothing);
    });
  });
}
