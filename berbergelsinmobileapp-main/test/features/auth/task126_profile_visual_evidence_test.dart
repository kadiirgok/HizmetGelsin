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
            appBar: AppBar(title: const Text('Hesabım')),
            body: SafeArea(child: body),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byKey(key), matchesGoldenFile('task126/$name'));
  }

  testWidgets('writes customer profile fake repository visual smoke evidence', (
    tester,
  ) async {
    Widget menu(
      String title,
      IconData icon, {
      String? subtitle,
      Widget? trailing,
    }) => ProfileMenuTile(
      title: title,
      icon: icon,
      subtitle: subtitle,
      trailing: trailing,
    );
    await capture(
      tester,
      'profile-home.png',
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: AppColors.primaryContainer,
            child: const ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Text('AY', style: TextStyle(color: Colors.white)),
              ),
              title: Text('Ayşe Yılmaz'),
              subtitle: Text('05•• ••• •• 42'),
              trailing: Icon(Icons.edit_outlined),
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(
            title: 'Hesabım',
            subtitle: 'Bilgilerinizi yönetin',
          ),
          Row(
            children: [
              Expanded(
                child: Card(
                  child: ListTile(title: Text('3'), subtitle: Text('Adres')),
                ),
              ),
              Expanded(
                child: Card(
                  child: ListTile(title: Text('8'), subtitle: Text('Favori')),
                ),
              ),
              Expanded(
                child: Card(
                  child: ListTile(title: Text('1'), subtitle: Text('Yaklaşan')),
                ),
              ),
            ],
          ),
          menu('Kişisel bilgiler', Icons.person_outline),
          menu(
            'Adreslerim',
            Icons.location_on_outlined,
            subtitle: '3 kayıtlı adres',
          ),
          menu('Favorilerim', Icons.favorite_border),
          menu('Yorumlarım', Icons.rate_review_outlined),
        ],
      ),
    );
    await capture(
      tester,
      'profile-loading.png',
      ListView(
        padding: EdgeInsets.all(16),
        children: [
          LoadingSkeleton(height: 100),
          SizedBox(height: 20),
          LoadingSkeleton(height: 72),
          SizedBox(height: 12),
          LoadingSkeleton(height: 72),
          SizedBox(height: 12),
          LoadingSkeleton(height: 72),
        ],
      ),
    );
    await capture(
      tester,
      'profile-edit.png',
      ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SectionHeader(title: 'Kişisel bilgiler'),
          AppTextField(label: 'Ad'),
          SizedBox(height: 12),
          AppTextField(label: 'Soyad'),
          SizedBox(height: 12),
          AppTextField(
            label: 'Telefon',
            helperText: 'Telefon numarası maskelidir.',
          ),
          SizedBox(height: 16),
          Text('Bu sürümde bilgiler salt okunur gösterilmektedir.'),
        ],
      ),
    );
    await capture(
      tester,
      'profile-account-summary.png',
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionHeader(title: 'Hesabım'),
          Row(
            children: [
              Expanded(
                child: Card(
                  child: ListTile(title: Text('3'), subtitle: Text('Adres')),
                ),
              ),
              Expanded(
                child: Card(
                  child: ListTile(title: Text('8'), subtitle: Text('Favori')),
                ),
              ),
              Expanded(
                child: Card(
                  child: ListTile(title: Text('1'), subtitle: Text('Yaklaşan')),
                ),
              ),
            ],
          ),
          menu(
            'Randevularım',
            Icons.calendar_month_outlined,
            subtitle: 'Yaklaşan ve geçmiş randevular',
          ),
          menu('Taleplerim', Icons.receipt_long_outlined),
          menu(
            'Bildirimlerim',
            Icons.notifications_none,
            trailing: const StatusBadge(label: '3', tone: StatusTone.warning),
          ),
        ],
      ),
    );
    await capture(
      tester,
      'profile-security.png',
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionHeader(title: 'Güvenlik ve destek'),
          menu(
            'Oturum ve güvenlik',
            Icons.shield_outlined,
            subtitle: 'Müşteri oturumu aktif',
          ),
          menu('KVKK ve gizlilik', Icons.privacy_tip_outlined),
          menu('Hesabımı silme talebi', Icons.delete_outline),
        ],
      ),
    );
    await capture(
      tester,
      'profile-logout.png',
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          menu('Oturum ve güvenlik', Icons.shield_outlined),
          const SizedBox(height: 16),
          SecondaryButton(label: 'Çıkış yap', icon: Icons.logout),
        ],
      ),
    );
    await capture(
      tester,
      'profile-delete-account.png',
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionHeader(title: 'Hesabımı silme talebi'),
          const Text('Hesap silme işlemi geri döndürülemez.'),
          const SizedBox(height: 16),
          const ErrorState(
            title: 'Talep gönderilemedi',
            message:
                'Bu sürümde hesap silme endpoint’i mevcut değil; oturumunuz korunuyor.',
          ),
        ],
      ),
    );
    await capture(
      tester,
      'profile-error.png',
      const ErrorState(
        title: 'Profil özeti yüklenemedi',
        message: 'Bağlantınızı kontrol edip tekrar deneyin.',
        onRetry: _noop,
        offline: true,
      ),
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}

void _noop() {}
