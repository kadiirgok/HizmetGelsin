import 'package:berbergelsin/core/theme/app_theme.dart';
import 'package:berbergelsin/core/widgets/customer_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/visual_test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestFonts();
  });

  Future<void> capture(WidgetTester tester, String name, Widget child) async {
    final key = GlobalKey();
    configureVisualTestViewport(tester, width: 390, height: 844);
    await tester.pumpWidget(
      buildVisualTestHarness(
        child: RepaintBoundary(
          key: key,
          child: Scaffold(body: SafeArea(child: child)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byKey(key), matchesGoldenFile('task124/$name'));
  }

  testWidgets('writes task 124 fake-repository UI smoke evidence', (
    tester,
  ) async {
    Widget page(List<Widget> children) =>
        ListView(padding: const EdgeInsets.all(16), children: children);
    await capture(
      tester,
      'home.png',
      page([
        const Text('Merhaba, Ayşe', style: AppTypography.titleLarge),
        AddressSelector(
          address: 'Ev • Atakent Mahallesi, İstanbul',
          onTap: () {},
        ),
        const SearchField(
          hintText: 'Hangi hizmeti veya işletmeyi arıyorsunuz?',
        ),
        const SectionHeader(title: 'Kategoriler', actionLabel: 'Tümünü gör'),
        Wrap(
          spacing: 8,
          children: [
            CategoryChip(label: 'Temizlik', selected: true, onSelected: (_) {}),
            CategoryChip(label: 'Tesisat', onSelected: (_) {}),
          ],
        ),
        const SectionHeader(title: 'Yakındaki işletmeler'),
        const BusinessCard(
          name: 'Güvenilir Ev Hizmetleri',
          category: 'Temizlik',
          rating: 4.8,
          reviewCount: 124,
          distanceText: '1,2 km',
          minimumPrice: 450,
          isOpen: true,
        ),
      ]),
    );
    await capture(
      tester,
      'home-loading.png',
      page(const [
        LoadingSkeleton(height: 64),
        SizedBox(height: 16),
        LoadingSkeleton(height: 52),
        SizedBox(height: 24),
        LoadingSkeleton(height: 48),
        SizedBox(height: 24),
        LoadingSkeleton(height: 220),
      ]),
    );
    await capture(
      tester,
      'address-selector.png',
      page([
        const SectionHeader(title: 'Arama konumunu seç'),
        const ProfileMenuTile(
          title: 'Ev',
          subtitle: 'Atakent Mahallesi, İstanbul',
          icon: Icons.location_on,
        ),
        const ProfileMenuTile(
          title: 'Mevcut konumumu kullan',
          icon: Icons.my_location,
        ),
        const ProfileMenuTile(title: 'Yeni adres ara', icon: Icons.search),
        const ProfileMenuTile(
          title: 'Manuel adres gir',
          icon: Icons.edit_location_alt,
        ),
      ]),
    );
    await capture(
      tester,
      'address-search.png',
      page(const [
        SectionHeader(title: 'Yeni adres ara'),
        SearchField(hintText: 'En az 3 karakter yazın'),
        SizedBox(height: 16),
        ProfileMenuTile(
          title: 'Atakent Mahallesi',
          subtitle: 'Küçükçekmece, İstanbul',
          icon: Icons.location_on_outlined,
        ),
        ProfileMenuTile(
          title: 'Atatürk Mahallesi',
          subtitle: 'Ümraniye, İstanbul',
          icon: Icons.location_on_outlined,
        ),
      ]),
    );
    await capture(
      tester,
      'categories.png',
      page([
        const SectionHeader(title: 'Tüm kategoriler'),
        const SearchField(hintText: 'Kategori ara'),
        const SizedBox(height: 16),
        for (final name in [
          'Temizlik',
          'Tesisat',
          'Elektrik',
          'Evden Eve Nakliyat',
        ])
          ProfileMenuTile(title: name, icon: Icons.handyman_outlined),
      ]),
    );
    await capture(
      tester,
      'search-results.png',
      page(const [
        SectionHeader(title: 'Kategoriler'),
        ProfileMenuTile(title: 'Temizlik', icon: Icons.category_outlined),
        SectionHeader(title: 'Hizmetler'),
        ServiceCard(name: 'Ev temizliği', category: 'Temizlik'),
        SectionHeader(title: 'İşletmeler'),
        ProfileMenuTile(
          title: 'Güvenilir Ev Hizmetleri',
          subtitle: 'Temizlik',
          icon: Icons.storefront,
        ),
      ]),
    );
    await capture(
      tester,
      'nearby-businesses.png',
      page(const [
        SectionHeader(title: 'Yakındaki işletmeler', actionLabel: 'Tümünü gör'),
        BusinessCard(
          name: 'Güvenilir Ev Hizmetleri',
          category: 'Temizlik',
          rating: 4.8,
          reviewCount: 124,
          distanceText: '1,2 km',
          minimumPrice: 450,
          isOpen: true,
        ),
        BusinessCard(
          name: 'Usta Teknik Servis',
          category: 'Tesisat',
          rating: 4.6,
          reviewCount: 89,
          distanceText: '2,4 km',
          minimumPrice: 600,
          isOpen: false,
        ),
      ]),
    );
    await capture(
      tester,
      'upcoming-appointment.png',
      page(const [
        SectionHeader(title: 'Yaklaşan randevu', actionLabel: 'Tüm randevular'),
        AppointmentCard(
          businessName: 'Güvenilir Ev Hizmetleri',
          dateText: 'Ev temizliği • 24.07.2026 14:30',
          status: 'Onaylandı',
        ),
      ]),
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}
