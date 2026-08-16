import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/customer_ui.dart';
import '../../map/widgets/client_bottom_navigation.dart';
import '../../notifications/controllers/notification_store.dart';
import '../../onboarding/widgets/kvkk_sheet.dart';
import '../../profile/screens/change_password_screen.dart';
import '../../profile/screens/notification_preferences_screen.dart';
import '../../requests/data/requests_repo.dart';
import '../bloc/auth_cubit.dart';
import '../models/app_user.dart';
import '../widgets/verification_sheets.dart';

class ClientProfileScreen extends StatefulWidget {
  const ClientProfileScreen({super.key});
  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  bool _loading = true;
  int _activeCount = 0, _completedCount = 0;
  bool _logoutBusy = false, _deleteBusy = false;

  @override
  void initState() {
    super.initState();
    NotificationStore.instance.addListener(_badgeChanged);
    _load();
  }

  void _badgeChanged() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    NotificationStore.instance.removeListener(_badgeChanged);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final requests = (await RequestsRepo.instance.mine()).items;
      if (!mounted) return;
      setState(() {
        _activeCount = requests.where((e) => e.isActive).length;
        _completedCount = requests.where((e) => e.status == 'Completed').length;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _maskPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) return '••••';
    return '${digits.substring(0, 2)}•• ••• •• ${digits.substring(digits.length - 2)}';
  }

  String _name(AppUser? user) => [user?.firstName, user?.lastName]
      .whereType<String>()
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .join(' ');

  String _initials(String name) {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'HG';
    return parts.take(2).map((e) => e.characters.first.toUpperCase()).join();
  }

  Future<void> _confirmLogout() async {
    if (_logoutBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Oturumu kapat?'),
        content: const Text('Bu cihazdaki müşteri oturumunuz kapatılacak.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Çıkış yap'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _logoutBusy = true);
    await context.read<AuthCubit>().logout();
  }

  Future<void> _confirmDelete() async {
    if (_deleteBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hesabımı silme talebi'),
        content: const Text(
          'Hesabınız silinmek üzere işaretlenecek ve bu cihazdaki oturumunuz kapatılacak. Devam etmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Silme talebi gönder'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleteBusy = true);
    try {
      await ApiClient.instance.delete('/api/client/profile');
      if (!mounted) return;
      await context.read<AuthCubit>().logout();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _deleteBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthCubit>().state.user;
    final name = _name(user);
    final displayName = name.isEmpty ? 'Müşteri' : name;
    final email = user?.email;
    final unread = NotificationStore.instance.unread.clamp(0, 99);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 16, 96), children: [
          // ── Premium Hero ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1A1A1C), Color(0xFF2D2D30)]),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 10))],
            ),
            child: Column(children: [
              Row(children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF444448), Color(0xFF55555A)]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Center(child: Text(_initials(name), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800))),
                ),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: -0.2)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: const Text('Müşteri', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  if (email?.isNotEmpty == true) ...[
                    const SizedBox(height: 6),
                    Text(email!, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
                  ],
                ])),
                IconButton(onPressed: () => _showPersonalInfo(user), icon: const Icon(Icons.edit_outlined, color: Colors.white54)),
              ]),
              const SizedBox(height: 18),
              // İstatistikler
              if (_loading)
                const Row(children: [Expanded(child: LoadingSkeleton(height: 52)), SizedBox(width: 10), Expanded(child: LoadingSkeleton(height: 52)), SizedBox(width: 10), Expanded(child: LoadingSkeleton(height: 52))])
              else
                Row(children: [
                  _StatTile(label: 'Aktif', value: _activeCount, icon: Icons.calendar_month_outlined),
                  const SizedBox(width: 10),
                  _StatTile(label: 'Tamamlanan', value: _completedCount, icon: Icons.verified_rounded),
                  const SizedBox(width: 10),
                  _StatTile(label: 'Puanım', value: user?.avgRating != null ? user!.avgRating!.toStringAsFixed(1) : '—', icon: Icons.star_rounded, isRating: user?.avgRating != null),
                ]),
            ]),
          ),
          const SizedBox(height: 20),
          // ── Menü grupları ──
          _PremiumMenuGroup(title: 'Hesabım', items: [
            _MenuItem(icon: Icons.person_outline, title: 'Kişisel bilgiler', subtitle: 'Ad, soyad, telefon ve e-posta', onTap: () => _showPersonalInfo(user)),
            _MenuItem(icon: Icons.lock_outlined, title: 'Şifre Değiştir', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePasswordScreen()))),
            _MenuItem(icon: Icons.rate_review_outlined, title: 'Yorumlarım', onTap: () => context.push('/yorumlarim')),
          ]),
          const SizedBox(height: 14),
          _PremiumMenuGroup(title: 'Aktivite', items: [
            _MenuItem(icon: Icons.calendar_month_outlined, title: 'İşlemlerim', subtitle: '$_activeCount aktif, $_completedCount tamamlanan', onTap: () => context.go('/taleplerim')),
            _MenuItem(icon: Icons.notifications_outlined, title: 'Bildirimler', subtitle: unread > 0 ? '$unread okunmamış' : 'Hepsi okundu', onTap: () => context.push('/bildirimler'), trailing: unread > 0 ? Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)), child: Text('$unread', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.warning))) : null),
            _MenuItem(icon: Icons.tune_outlined, title: 'Bildirim Tercihleri', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationPreferencesScreen()))),
          ]),
          const SizedBox(height: 14),
          _PremiumMenuGroup(title: 'Doğrulama', items: [
            _MenuItem(icon: user?.emailVerified == true ? Icons.verified : Icons.warning_amber_rounded, title: 'E-posta', subtitle: user?.emailVerified == true ? 'Doğrulandı' : (email?.isNotEmpty == true ? 'Doğrulanmadı' : 'Tanımlı değil'), onTap: (user?.emailVerified == true || email?.isEmpty == true) ? null : () => VerificationSheets.showEmailVerification(context, user), trailing: user?.emailVerified == true ? const Icon(Icons.check_circle, color: AppColors.success, size: 18) : null),
            _MenuItem(icon: user?.isPhoneVerified == true ? Icons.verified : Icons.warning_amber_rounded, title: 'Telefon', subtitle: user?.isPhoneVerified == true ? 'Doğrulandı' : 'Doğrulanmadı', onTap: user?.isPhoneVerified == true ? null : () => VerificationSheets.showPhoneVerification(context, user), trailing: user?.isPhoneVerified == true ? const Icon(Icons.check_circle, color: AppColors.success, size: 18) : null),
          ]),
          const SizedBox(height: 14),
          _PremiumMenuGroup(title: 'Yasal', items: [
            _MenuItem(icon: Icons.privacy_tip_outlined, title: 'KVKK ve Gizlilik Politikası', subtitle: 'Kullanıcı sözleşmesi ve kişisel veriler', onTap: () => showKvkkSheet(context)),
          ]),
          const SizedBox(height: 20),
          // Çıkış
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: _logoutBusy ? null : _confirmLogout,
            icon: _logoutBusy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.logout, size: 18),
            label: Text(_logoutBusy ? 'Çıkış yapılıyor…' : 'Çıkış Yap'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade600, side: BorderSide(color: Colors.red.shade200), padding: const EdgeInsets.symmetric(vertical: 14)),
          )),
          const SizedBox(height: 8),
          Center(
            child: TextButton(onPressed: _deleteBusy ? null : _confirmDelete,
              child: Text(_deleteBusy ? 'Siliniyor…' : 'Hesabımı Sil', style: TextStyle(color: Colors.red.shade400, fontSize: 13)),
            ),
          ),
        ]),
      ),
      bottomNavigationBar: const ClientBottomNavigation(currentIndex: 3),
    );
  }

  void _showPersonalInfo(AppUser? user) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => AppBottomSheet(
        title: 'Kişisel bilgiler',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              initialValue: user?.firstName ?? '',
              readOnly: true,
              decoration: const InputDecoration(labelText: 'Ad'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              initialValue: user?.lastName ?? '',
              readOnly: true,
              decoration: const InputDecoration(labelText: 'Soyad'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              initialValue: _maskPhone(user?.phone ?? ''),
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Telefon',
                helperText: 'Telefon numarası güvenlik nedeniyle maskelidir.',
              ),
            ),
            if (user?.email?.isNotEmpty == true) ...[
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                initialValue: user!.email,
                readOnly: true,
                decoration: const InputDecoration(labelText: 'E-posta'),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Bu sürümde profil bilgileri salt okunur gösterilmektedir.',
              style: AppTypography.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.icon, this.isRating = false});
  final String label; final dynamic value; final IconData icon; final bool isRating;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Icon(icon, color: isRating ? const Color(0xFFFFB800) : Colors.white60, size: 18),
        const SizedBox(height: 4),
        Text('$value', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

class _PremiumMenuGroup extends StatelessWidget {
  const _PremiumMenuGroup({required this.title, required this.items});
  final String title; final List<Widget> items;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.textSecondary, letterSpacing: 0.3))),
    Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFECECEF))),
      child: Column(children: [
        for (var i = 0; i < items.length; i++) ...[items[i],
          if (i < items.length - 1) const Divider(height: 1, indent: 52, endIndent: 16)],
      ])),
  ]);
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.title, this.subtitle, this.trailing, this.onTap});
  final IconData icon; final String title; final String? subtitle; final Widget? trailing; final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AppColors.primary, size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))],
        ])),
        if (trailing != null) trailing! else const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
      ]),
    ),
  );
}

// Eski widget'lar kaldırıldı
