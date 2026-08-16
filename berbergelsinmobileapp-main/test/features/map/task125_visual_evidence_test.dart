import 'package:berbergelsin/core/theme/app_theme.dart';
import 'package:berbergelsin/core/widgets/customer_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/visual_test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestFonts();
  });

  Future<void> capture(WidgetTester tester, String name, Widget body) async {
    final key = GlobalKey();
    configureVisualTestViewport(tester, width: 390, height: 844);
    await tester.pumpWidget(
      buildVisualTestHarness(
        child: RepaintBoundary(
          key: key,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Keşfet'),
              actions: const [Icon(Icons.tune)],
            ),
            body: SafeArea(child: body),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byKey(key), matchesGoldenFile('task125/$name'));
  }

  Widget toggle({bool map = true}) => SegmentedButton<int>(
    segments: const [
      ButtonSegment(
        value: 0,
        icon: Icon(Icons.view_list),
        label: Text('Liste'),
      ),
      ButtonSegment(value: 1, icon: Icon(Icons.map), label: Text('Harita')),
    ],
    selected: {map ? 1 : 0},
    onSelectionChanged: (_) {},
  );
  Widget map({
    bool clusters = false,
    bool search = false,
    Widget? bottom,
  }) => Column(
    children: [
      Padding(padding: const EdgeInsets.all(12), child: toggle()),
      Expanded(
        child: Stack(
          children: [
            const Positioned.fill(child: _MapSurface()),
            if (clusters) ...[
              const Positioned(left: 80, top: 110, child: _Cluster(count: 12)),
              const Positioned(right: 70, top: 220, child: _Cluster(count: 7)),
            ] else ...[
              const Positioned(left: 70, top: 120, child: _Marker()),
              const Positioned(
                right: 80,
                top: 205,
                child: _Marker(selected: true),
              ),
              const Positioned(
                left: 150,
                top: 315,
                child: _Marker(closed: true),
              ),
            ],
            if (search)
              Positioned(
                top: 16,
                left: 90,
                right: 90,
                child: FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.refresh),
                  label: const Text('Bu alanda ara • 8 km'),
                ),
              ),
            if (bottom != null)
              Positioned(left: 8, right: 8, bottom: 8, child: bottom),
          ],
        ),
      ),
    ],
  );

  testWidgets('writes task 125 fake repository map smoke evidence', (
    tester,
  ) async {
    await capture(tester, 'map-default.png', map());
    await capture(tester, 'map-clusters.png', map(clusters: true));
    await capture(
      tester,
      'map-selected-business.png',
      map(
        bottom: const BusinessCard(
          name: 'Çok Uzun Profesyonel İşletme ve Yerel Hizmet Merkezi',
          category: 'Temizlik',
          rating: 4.8,
          reviewCount: 124,
          distanceText: '1,2 km',
          minimumPrice: 450,
          isOpen: true,
          favorite: true,
        ),
      ),
    );
    await capture(
      tester,
      'map-filters.png',
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionHeader(
            title: 'Keşif filtreleri',
            actionLabel: 'Temizle',
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final label in ['Temizlik', '4+ puan', '0–1000 ₺', '8 km'])
                AppFilterChip(label: label, selected: true, onSelected: (_) {}),
            ],
          ),
          const SizedBox(height: 16),
          const AppTextField(label: 'Hizmet'),
          const SizedBox(height: 12),
          const AppTextField(label: 'Minimum fiyat'),
          const SizedBox(height: 12),
          const PrimaryButton(label: 'Filtreleri uygula'),
        ],
      ),
    );
    await capture(tester, 'map-search-area.png', map(search: true));
    await capture(
      tester,
      'map-no-location.png',
      Column(
        children: [
          Padding(padding: const EdgeInsets.all(12), child: toggle()),
          Expanded(
            child: EmptyState(
              title: 'Yakındaki işletmeleri görmek için adres seçin',
              message:
                  'Kayıtlı adresinizi veya cihaz konumunu kullanabilirsiniz.',
              icon: Icons.location_off_outlined,
              actionLabel: 'Adreslerime git',
              onAction: () {},
            ),
          ),
        ],
      ),
    );
    await capture(
      tester,
      'map-error.png',
      map(
        bottom: ErrorState(
          title: 'Harita güncellenemedi',
          message: 'Önceki işletmeler gösterilmeye devam ediyor.',
          onRetry: () {},
        ),
      ),
    );
    await capture(
      tester,
      'list-map-sync.png',
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          toggle(map: false),
          const SizedBox(height: 12),
          const BusinessCard(
            name: 'Güvenilir Ev Hizmetleri',
            category: 'Temizlik',
            rating: 4.8,
            reviewCount: 124,
            distanceText: '1,2 km',
            minimumPrice: 450,
            isOpen: true,
            favorite: true,
          ),
          const BusinessCard(
            name: 'Usta Teknik Servis',
            category: 'Tesisat',
            rating: 4.6,
            reviewCount: 89,
            distanceText: '2,4 km',
            minimumPrice: 600,
            isOpen: false,
          ),
        ],
      ),
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}

class _MapSurface extends StatelessWidget {
  const _MapSurface();
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _MapPainter(),
    child: const ColoredBox(color: Color(0xFFE9EFEA)),
  );
}

class _MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 9;
    final minor = Paint()
      ..color = const Color(0xFFD0DAD4)
      ..strokeWidth = 2;
    for (var y = 70.0; y < size.height; y += 110) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 35), road);
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 35), minor);
    }
    for (var x = 45.0; x < size.width; x += 100) {
      canvas.drawLine(Offset(x, 0), Offset(x + 45, size.height), road);
      canvas.drawLine(Offset(x, 0), Offset(x + 45, size.height), minor);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Marker extends StatelessWidget {
  const _Marker({this.selected = false, this.closed = false});
  final bool selected, closed;
  @override
  Widget build(BuildContext context) => Container(
    width: 46,
    height: 46,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: closed ? AppColors.textSecondary : AppColors.primary,
      border: Border.all(
        color: selected ? AppColors.secondary : Colors.white,
        width: selected ? 4 : 2,
      ),
      boxShadow: AppShadows.card,
    ),
    child: const Icon(Icons.storefront, color: Colors.white),
  );
}

class _Cluster extends StatelessWidget {
  const _Cluster({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 27,
    backgroundColor: AppColors.primary,
    child: Text(
      '$count',
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    ),
  );
}
