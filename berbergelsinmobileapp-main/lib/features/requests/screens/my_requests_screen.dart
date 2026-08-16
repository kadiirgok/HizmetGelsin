import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/session/customer_session_events.dart';
import '../../../core/theme/app_theme.dart';
import '../data/requests_repo.dart';
import '../controllers/request_submission.dart';
import '../widgets/rating_dialog.dart';
import '../../map/widgets/client_bottom_navigation.dart';
import '../../map/data/barbers_repo.dart';
import '../../../core/widgets/customer_ui.dart';
import 'request_detail_screen.dart';

String requestStatusLabel(String status) => switch (status) {
  'Pending' => 'Talep oluşturuldu',
  'OfferReceived' => 'Teklif geldi',
  'Accepted' => 'Onaylandı',
  'Scheduled' => 'Randevu planlandı',
  'OnTheWay' => 'Yolda',
  'Started' => 'Hizmet başladı',
  'Rejected' => 'Reddedildi',
  'Completed' => 'Tamamlandı',
  'Cancelled' => 'İptal Edildi',
  'ReschedulePending' => 'Yeni tarih bekleniyor',
  _ => status,
};

Color requestStatusColor(String status) => switch (status) {
  'Pending' => Colors.orange.shade700,
  'Accepted' => Colors.blue.shade700,
  'OnTheWay' => Colors.purple.shade600,
  'Started' => Colors.teal.shade700,
  'ReschedulePending' => Colors.amber.shade800,
  'Completed' => Colors.green.shade700,
  _ => Colors.red.shade700,
};

String formatDateTime(DateTime dt) =>
    '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} '
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

/// Müşterinin randevuları; SignalR ile canlı güncellenir.
class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({
    super.key,
    this.requestsLoader,
    this.realtimeClient,
    this.sessionSource,
  });
  final Future<RequestPage> Function()? requestsLoader;
  final CustomerRealtimeClient? realtimeClient;
  final CustomerSessionVersionSource? sessionSource;

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  String _requestFilter = 'active';
  List<ServiceRequestModel>? _requests;
  String? _loadError;
  final _etaByRequest = <String, String>{};
  late final CustomerSessionEventSubscriptions _sessionEvents;
  bool _actionBusy = false;

  @override
  void initState() {
    super.initState();
    _sessionEvents = CustomerSessionEventSubscriptions(
      session: widget.sessionSource ?? CustomerSessionScope.instance,
      realtime: widget.realtimeClient ?? SignalRCustomerRealtimeClient.instance,
    );
    _load();
    for (final event in ['RequestUpdated']) {
      _sessionEvents.on(event, (args) => _load());
    }
    _sessionEvents.onReconnected(_load);
    _sessionEvents.on('TrackingUpdate', (args) {
      final payload = args?.firstOrNull;
      if (payload is! Map || !mounted) return;
      final requestId = payload['requestId'];
      final etaMinutes = payload['etaMinutes'];
      if (requestId is! String || etaMinutes is! num) return;
      final distanceMeters =
          (payload['distanceMeters'] as num?)?.toDouble() ?? 0;
      final distance = distanceMeters >= 1000
          ? '${(distanceMeters / 1000).toStringAsFixed(1)} km'
          : '${distanceMeters.round()} m';
      setState(
        () =>
            _etaByRequest[requestId] = '~${etaMinutes.round()} dk ($distance)',
      );
    });
  }

  @override
  void dispose() {
    _sessionEvents.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_sessionEvents.isCurrent) return;
    try {
      final page = await (widget.requestsLoader?.call() ?? RequestsRepo.instance.mine());
      if (!mounted || !_sessionEvents.isCurrent) return;
      setState(() {
        _loadError = null;
        _requests = page.items;
      });
    } catch (_) {
      if (mounted && _sessionEvents.isCurrent) {
        setState(
          () => _loadError = 'Randevular yüklenemedi. Lütfen tekrar deneyin.',
        );
      }
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        ),
      );
  }

  Future<bool> _act(Future<void> Function() action) async {
    if (_actionBusy) return false;
    _actionBusy = true;
    var succeeded = false;
    try {
      await action();
      succeeded = true;
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      _actionBusy = false;
    }
    await _load();
    return succeeded;
  }

  Future<void> _completeAndRate(ServiceRequestModel r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Randevuyu Bitir'),
        content: const Text(
          'Hizmet tamamlandı mı? Onayladıktan sonra işletmeyi puanlayabilirsiniz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Henüz Değil'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Evet, Bitti'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await RequestsRepo.instance.complete(
        r.id,
        idempotencyKey: newRequestUuid(),
      );
      await _load();
      if (!mounted) return;
      await _rate(r);
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  Future<void> _rate(ServiceRequestModel r) async {
    final result = await showRatingDialog(
      context,
      title: 'İşletmeyi Puanla',
      subtitle:
          '${r.barberBusinessName ?? "İşletme"} için deneyiminizi değerlendirin.',
    );
    if (result == null) return;
    final succeeded = await _act(
      () => RequestsRepo.instance.rate(r.id, result.score, result.comment),
    );
    if (succeeded) _snack('Değerlendirmeniz kaydedildi. Teşekkürler!');
  }

  @override
  Widget build(BuildContext context) {
    final all = _requests ?? const <ServiceRequestModel>[];
    final active = all.where((r) => r.isActive).toList();
    final past = all.where((r) => !r.isActive && r.status != 'Cancelled').toList();
    final cancelled = all.where((r) => r.status == 'Cancelled').toList();
    final filtered = switch (_requestFilter) {
      'active' => active, 'history' => past, 'cancelled' => cancelled, _ => active,
    };

    return Scaffold(
      extendBody: true,
      appBar: AppBar(title: const Text('İşlemlerim')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loadError != null
            ? _LoadErrorView(message: _loadError!, onRetry: _load)
            : _requests == null
            ? const _LoadingView()
            : all.isEmpty
            ? const _EmptyView('Henüz randevu veya talebiniz yok.')
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                children: [
                  // Üst özet
                  _SummaryHeader(active: active.length, past: past.length, cancelled: cancelled.length),
                  const SizedBox(height: 14),
                  _PremiumFilterBar(value: _requestFilter, onChanged: (v) => setState(() => _requestFilter = v)),
                  const SizedBox(height: 16),
                  if (filtered.isEmpty)
                    _FilterEmptyState(filter: _requestFilter)
                  else
                    ...filtered.map(_buildPremiumRequestCard),
                ],
              ),
      ),
      bottomNavigationBar: const ClientBottomNavigation(currentIndex: 2),
    );
  }

  Widget _buildPremiumRequestCard(ServiceRequestModel r) {
    final statusColor = requestStatusColor(r.status);
    final code = r.id.replaceAll('-', '').substring(0, 4).toUpperCase();
    final businessName = r.barberBusinessName?.trim().isNotEmpty == true ? r.barberBusinessName! : 'İşletme';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFECECEF)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(splashColor: AppColors.primary.withValues(alpha: 0.05), highlightColor: AppColors.primary.withValues(alpha: 0.02)),
        child: InkWell(
          onTap: () => _showDetail(r),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Üst satır - ikon + isim + durum
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    r.status == 'Accepted' ? Icons.check_circle_rounded :
                    r.status == 'Pending' ? Icons.hourglass_bottom_rounded :
                    r.status == 'Completed' ? Icons.verified_rounded :
                    Icons.schedule_rounded,
                    color: statusColor, size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(businessName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: -0.1)),
                    const SizedBox(height: 3),
                    Text(r.items.map((it) => it.serviceName).join(', '),
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5, fontWeight: FontWeight.w500),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('₺${r.totalPrice.toStringAsFixed(0)}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: -0.2)),
                  const SizedBox(height: 4),
                  _StatusBadge(label: requestStatusLabel(r.status), color: statusColor),
                ]),
              ]),
              // Tarih bilgisi
              Padding(
                padding: const EdgeInsets.only(top: 10, left: 60),
                child: Text(formatDateTime(r.requestedTime),
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
              ),
              // Kod + Aksiyonlar (Accepted / OnTheWay / Started)
              if (r.status == 'Accepted' || r.status == 'OnTheWay' || r.status == 'Started') ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFF0FFF4), Color(0xFFF5FFF8)]),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.15)),
                  ),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.vpn_key_rounded, color: AppColors.success, size: 18),
                      const SizedBox(width: 8),
                      const Text('Doğrulama Kodu:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.success.withValues(alpha: 0.2))),
                        child: Text(code, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 5, color: AppColors.success)),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      _PremiumActionChip(icon: Icons.call_rounded, label: 'İşletmeyi Ara', color: AppColors.success, onTap: () {
                        if (r.barberPhone?.isNotEmpty == true) launchUrl(Uri.parse('tel:${r.barberPhone}'));
                      }),
                      const SizedBox(width: 10),
                      _PremiumActionChip(icon: Icons.close_rounded, label: 'İptal Et', color: Colors.red.shade600, onTap: () => _cancelRequest(r)),
                    ]),
                  ]),
                ),
              ],
              // Puanla butonu
              if (r.status == 'Completed' && r.canRate) ...[
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: FilledButton.icon(
                  onPressed: () => _rate(r),
                  icon: const Icon(Icons.star_rounded, size: 18),
                  label: const Text('Puanla'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.warning, padding: const EdgeInsets.symmetric(vertical: 14)),
                )),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _cancelRequest(ServiceRequestModel r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('İptal Et'),
        content: const Text('Bu işlemi iptal etmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('İptal Et'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await RequestsRepo.instance.cancelRequest(r.id, reasonCode: 'other', idempotencyKey: newRequestUuid());
      if (mounted) _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade700));
      }
    }
  }

  void _showDetail(ServiceRequestModel r) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RequestDetailScreen(
          requestId: r.id,
          initialRequest: r,
          onChanged: _load,
        ),
      ),
    );
  }
}

class _PremiumFilterBar extends StatelessWidget {
  const _PremiumFilterBar({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(16)),
    child: Row(children: [
      for (final item in const [('active', 'Aktif'), ('history', 'Geçmiş'), ('cancelled', 'İptal')])
        Expanded(child: GestureDetector(
          onTap: () => onChanged(item.$1),
          child: AnimatedContainer(
            duration: AppDurations.fast,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: value == item.$1 ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text(item.$2, textAlign: TextAlign.center, style: TextStyle(
              color: value == item.$1 ? Colors.white : AppColors.textSecondary,
              fontWeight: FontWeight.w700, fontSize: 13,
            )),
          ),
        )),
    ]),
  );
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.active, required this.past, required this.cancelled});
  final int active, past, cancelled;
  @override
  Widget build(BuildContext context) => Row(children: [
    _SummaryTile(label: 'Aktif', count: active, color: AppColors.primary),
    const SizedBox(width: 10),
    _SummaryTile(label: 'Geçmiş', count: past, color: AppColors.textSecondary),
    const SizedBox(width: 10),
    _SummaryTile(label: 'İptal', count: cancelled, color: AppColors.error),
  ]);
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.count, required this.color});
  final String label; final int count; final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Text('$count', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: color)),
        Text(label, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
  );
}

class _PremiumActionChip extends StatelessWidget {
  const _PremiumActionChip({required this.icon, required this.label, required this.color, this.onTap});
  final IconData icon; final String label; final Color color; final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: color.withValues(alpha: 0.08),
    borderRadius: BorderRadius.circular(22),
    child: InkWell(borderRadius: BorderRadius.circular(22), onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: color), const SizedBox(width: 5),
          Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: color)),
        ]),
      ),
    ),
  );
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: const [
    SizedBox(height: 8), LoadingSkeleton(height: 70), SizedBox(height: 10),
    LoadingSkeleton(height: 130), SizedBox(height: 10),
    LoadingSkeleton(height: 130),
  ]);
}

class _FilterEmptyState extends StatelessWidget {
  const _FilterEmptyState({required this.filter});
  final String filter;
  @override
  Widget build(BuildContext context) {
    final (title, msg) = switch (filter) {
      'active' => ('Aktif talep yok', 'Yeni bir hizmet keşfetmek için ana sayfaya dönebilirsiniz.'),
      'history' => ('Geçmiş randevu yok', 'Tamamlanan randevularınız burada görünecek.'),
      _ => ('İptal edilen kayıt yok', 'İptal edilen talepleriniz burada görünecek.'),
    };
    return EmptyState(title: title, message: msg, icon: Icons.calendar_today_outlined, actionLabel: 'Hizmet keşfet', onAction: () => context.go('/harita'));
  }
}

class _LoadErrorView extends StatelessWidget {
  const _LoadErrorView({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 72, height: 72, decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), shape: BoxShape.circle),
        child: const Icon(Icons.cloud_off_rounded, color: AppColors.error, size: 32)),
      const SizedBox(height: 16),
      Text(message, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      FilledButton.tonal(onPressed: onRetry, child: const Text('Tekrar Dene')),
    ])),
  );
}

class _EmptyView extends StatelessWidget {
  const _EmptyView(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 80, height: 80, decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(24)),
        child: const Icon(Icons.inbox_rounded, size: 36, color: AppColors.textSecondary)),
      const SizedBox(height: 16),
      Text(message, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
    ])),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SizedBox(width: 120, child: Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13.5))),
    Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
  ]));
}
