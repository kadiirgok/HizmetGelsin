import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:berbergelsin/core/theme/app_theme.dart';
import 'package:berbergelsin/core/widgets/customer_ui.dart';
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
            appBar: AppBar(title: const Text('Randevularım')),
            body: SafeArea(child: body),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byKey(key), matchesGoldenFile('task127/$name'));
  }

  Widget filters(String selected) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final label in [
          'Yaklaşan',
          'Aktif talepler',
          'Geçmiş',
          'İptal edilen',
        ]) ...[
          ChoiceChip(
            label: Text(label),
            selected: label == selected,
            onSelected: (_) {},
          ),
          const SizedBox(width: 8),
        ],
      ],
    ),
  );
  Widget card(String name, String status) => AppointmentCard(
    businessName: name,
    dateText: 'Ev temizliği • 24.07.2026 14:30 • Atakent',
    status: status,
    onTap: () {},
  );
  testWidgets('writes task 127 fake repository appointments smoke evidence', (
    tester,
  ) async {
    await capture(
      tester,
      'appointments-upcoming.png',
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          filters('Yaklaşan'),
          const SizedBox(height: 12),
          card('Güvenilir Ev Hizmetleri', 'Randevu planlandı'),
        ],
      ),
    );
    await capture(
      tester,
      'appointments-active.png',
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          filters('Aktif talepler'),
          const SizedBox(height: 12),
          card('Usta Teknik Servis', 'Teklif geldi'),
        ],
      ),
    );
    await capture(
      tester,
      'appointments-history.png',
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          filters('Geçmiş'),
          const SizedBox(height: 12),
          card('Yerel Hizmet Merkezi', 'Tamamlandı'),
        ],
      ),
    );
    await capture(
      tester,
      'appointments-cancelled.png',
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          filters('İptal edilen'),
          const SizedBox(height: 12),
          card('Uzun İşletme Adı ve Hizmet Merkezi', 'İptal edildi'),
        ],
      ),
    );
    await capture(
      tester,
      'request-detail.png',
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionHeader(title: 'İşletme ve hizmet'),
          const StatusBadge(
            label: 'Randevu planlandı',
            tone: StatusTone.success,
          ),
          const SizedBox(height: 12),
          const ServiceCard(
            name: 'Ev temizliği',
            category: 'Temizlik',
            price: 450,
          ),
          const ProfileMenuTile(
            title: 'Hizmet konumu',
            subtitle: 'Atakent Mahallesi, İstanbul',
            icon: Icons.location_on_outlined,
          ),
          const PrimaryButton(label: 'Yeniden planla'),
        ],
      ),
    );
    await capture(
      tester,
      'request-timeline.png',
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionHeader(title: 'Durum zaman çizelgesi'),
          for (final item in [
            'Talep oluşturuldu',
            'Teklif geldi',
            'Randevu planlandı',
            'Hizmet başladı',
          ])
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.primaryContainer,
                  child: Icon(Icons.check, color: AppColors.primary),
                ),
                title: Text(item),
                subtitle: const Text('24.07.2026 14:30 • İşletme'),
              ),
            ),
        ],
      ),
    );
    await capture(
      tester,
      'cancel-flow.png',
      ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SectionHeader(title: 'Talebi iptal et'),
          Text('İptal nedeninizi seçin.'),
          SizedBox(height: 12),
          AppFilterChip(
            label: 'Planım değişti',
            selected: true,
            onSelected: _noop,
          ),
          AppTextField(label: 'Açıklama (isteğe bağlı)'),
          SizedBox(height: 16),
          PrimaryButton(label: 'İptali onayla'),
        ],
      ),
    );
    await capture(
      tester,
      'reschedule-flow.png',
      ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SectionHeader(title: 'Randevuyu yeniden planla'),
          ProfileMenuTile(
            title: 'Mevcut tarih',
            subtitle: '24.07.2026 14:30',
            icon: Icons.event,
          ),
          ProfileMenuTile(
            title: 'Yeni tarih seç',
            subtitle: 'Tarih ve saat',
            icon: Icons.calendar_month,
          ),
          SizedBox(height: 16),
          PrimaryButton(label: 'Yeni tarih talebi gönder'),
        ],
      ),
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}

void _noop(bool _) {}
