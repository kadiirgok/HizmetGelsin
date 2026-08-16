import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/session/customer_session_events.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/customer_ui.dart';
import '../../map/data/barbers_repo.dart';
import '../controllers/request_submission.dart';
import '../data/requests_repo.dart';
import '../widgets/rating_dialog.dart';
import 'my_requests_screen.dart'
    show formatDateTime, requestStatusColor, requestStatusLabel;

enum RequestDetailState {
  initial,
  loading,
  success,
  actionSubmitting,
  concurrencyConflict,
  rateLimited,
  networkError,
  timelineError,
}

({RequestDetailState state, String message}) mapRequestLifecycleError(
  ApiException e,
) => switch ((e.code, e.statusCode)) {
  ('request_not_found', _) || (_, 404) => (
    state: RequestDetailState.networkError,
    message: 'Talep bulunamadı.',
  ),
  ('request_forbidden', _) || (_, 401) || (_, 403) => (
    state: RequestDetailState.networkError,
    message: 'Bu talebi görüntüleme yetkiniz yok.',
  ),
  ('request_invalid_transition', _) => (
    state: RequestDetailState.networkError,
    message: 'Talebin durumu değişti. Bilgiler yenilendi.',
  ),
  ('request_concurrency_conflict', _) => (
    state: RequestDetailState.concurrencyConflict,
    message: 'Kayıt başka bir cihazda değişti. Bilgiler yenilendi.',
  ),
  ('request_cancellation_invalid', _) => (
    state: RequestDetailState.networkError,
    message: 'İptal nedenini kontrol edin.',
  ),
  ('request_reschedule_invalid', _) => (
    state: RequestDetailState.networkError,
    message: 'Yeni tarih veya saat uygun değil.',
  ),
  ('request_reschedule_conflict', _) => (
    state: RequestDetailState.concurrencyConflict,
    message: 'Seçilen zaman başka bir randevuyla çakışıyor.',
  ),
  ('request_idempotency_conflict', _) => (
    state: RequestDetailState.concurrencyConflict,
    message: 'İşlem içeriği değişti. Lütfen yeniden deneyin.',
  ),
  ('request_rate_limited', _) => (
    state: RequestDetailState.rateLimited,
    message: 'Çok fazla işlem yapıldı. Lütfen biraz bekleyin.',
  ),
  _ => (
    state: RequestDetailState.networkError,
    message: 'İşlem tamamlanamadı. Lütfen tekrar deneyin.',
  ),
};

class RequestDetailScreen extends StatefulWidget {
  const RequestDetailScreen({
    super.key,
    required this.requestId,
    this.initialRequest,
    this.repository,
    this.onChanged,
    this.realtimeClient,
    this.sessionSource,
  });
  final String requestId;
  final ServiceRequestModel? initialRequest;
  final RequestTrackingRepository? repository;
  final VoidCallback? onChanged;
  final CustomerRealtimeClient? realtimeClient;
  final CustomerSessionVersionSource? sessionSource;
  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  late final RequestTrackingRepository _repo =
      widget.repository ?? RequestsRepo.instance;
  ServiceRequestModel? _request;
  List<RequestTimelineEntry>? _timeline;
  RequestDetailState _state = RequestDetailState.initial;
  String? _error;
  late final CustomerSessionEventSubscriptions _sessionEvents;
  bool _actionBusy = false;
  String? _retrySignature, _retryKey;
  bool get _canResolveReschedule {
    final last = _timeline?.lastOrNull;
    return last != null &&
        last.toStatus == 'ReschedulePending' &&
        last.changedByRole == 'Berber';
  }

  @override
  void initState() {
    super.initState();
    _sessionEvents = CustomerSessionEventSubscriptions(
      session: widget.sessionSource ?? CustomerSessionScope.instance,
      realtime: widget.realtimeClient ?? SignalRCustomerRealtimeClient.instance,
    );
    _request = widget.initialRequest;
    _refresh();
    for (final event in ['RequestUpdated', 'RequestTimelineUpdated']) {
      _sessionEvents.on(event, (args) {
        final p = args?.firstOrNull;
        if (p is Map && p['requestId'] == widget.requestId) _refresh();
      });
    }
  }

  @override
  void dispose() {
    _sessionEvents.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!_sessionEvents.isCurrent) return;
    if (_request == null && mounted) {
      setState(() => _state = RequestDetailState.loading);
    }
    try {
      final values = await Future.wait([
        _repo.detail(widget.requestId),
        _repo.timeline(widget.requestId),
      ]);
      if (!mounted || !_sessionEvents.isCurrent) return;
      setState(() {
        _request = values[0] as ServiceRequestModel;
        _timeline = values[1] as List<RequestTimelineEntry>;
        _state = RequestDetailState.success;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted && _sessionEvents.isCurrent) {
        final m = mapRequestLifecycleError(e);
        setState(() {
          _state = m.state;
          _error = m.message;
        });
      }
    }
  }

  String _keyFor(String signature) {
    if (_retrySignature != signature) {
      _retrySignature = signature;
      _retryKey = newRequestUuid();
    }
    return _retryKey!;
  }

  Future<void> _action(
    String signature,
    Future<void> Function(String) call,
  ) async {
    if (_actionBusy) return;
    _actionBusy = true;
    if (mounted) {
      setState(() {
        _state = RequestDetailState.actionSubmitting;
        _error = null;
      });
    }
    try {
      await call(_keyFor(signature));
      _retrySignature = null;
      _retryKey = null;
      widget.onChanged?.call();
      await _refresh();
    } on ApiException catch (e) {
      final m = mapRequestLifecycleError(e);
      if (mounted) {
        setState(() {
          _state = m.state;
          _error = m.message;
        });
      }
      if (e.code == 'request_concurrency_conflict' ||
          e.code == 'request_invalid_transition') {
        await _refresh();
      }
    } finally {
      _actionBusy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _cancel() async {
    String? code;
    final note = TextEditingController();
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Talebi İptal Et',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                DropdownButtonFormField<String>(
                  initialValue: code,
                  decoration: const InputDecoration(
                    labelText: 'İptal nedeni *',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'plans_changed',
                      child: Text('Planım değişti'),
                    ),
                    DropdownMenuItem(
                      value: 'time_not_suitable',
                      child: Text('Saat uygun değil'),
                    ),
                    DropdownMenuItem(value: 'other', child: Text('Diğer')),
                  ],
                  onChanged: (v) => setLocal(() => code = v),
                ),
                TextField(
                  controller: note,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Açıklama'),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: code == null
                        ? null
                        : () => Navigator.pop(context, true),
                    child: const Text('İptal Et'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == true && code != null) {
      await _action(
        'cancel:$code:${note.text.trim()}',
        (key) => _repo.cancelRequest(
          widget.requestId,
          reasonCode: code!,
          reasonText: note.text.trim(),
          idempotencyKey: key,
        ),
      );
    }
    note.dispose();
  }

  Future<void> _reschedule() async {
    var selected = DateTime.now().add(const Duration(days: 1));
    final result = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Yeniden Planla',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text('Yeni zaman: ${formatDateTime(selected)}'),
              const Text(
                'Bu bir slot garantisi değildir; işletmenin onayı gerekir.',
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(context, selected),
                child: const Text('Öneriyi Gönder'),
              ),
            ],
          ),
        ),
      ),
    );
    if (result != null) {
      await _action(
        'reschedule:${result.toUtc().toIso8601String()}',
        (key) =>
            _repo.reschedule(widget.requestId, result, idempotencyKey: key),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _request;
    final statusColor = r != null ? requestStatusColor(r.status) : AppColors.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('Randevu Detayı')),
      body: r == null
          ? _buildLoadingError()
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  // ── Hero kartı ──
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF1A1A1C), Color(0xFF2D2D30)]),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 10))],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          width: 52, height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                          child: Icon(_statusIcon(r.status), color: Colors.white, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.barberBusinessName ?? 'İşletme',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -0.2)),
                          const SizedBox(height: 4),
                          Text(r.items.map((e) => e.serviceName).join(' • '),
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 13, fontWeight: FontWeight.w500),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        ])),
                      ]),
                      const SizedBox(height: 18),
                      Row(children: [
                        _HeroInfo(label: 'Tarih', value: formatDateTime(r.requestedTime)),
                        const SizedBox(width: 20),
                        _HeroInfo(label: 'Tutar', value: '₺${r.totalPrice.toStringAsFixed(0)}'),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                          ),
                          child: Text(requestStatusLabel(r.status),
                            style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: 12)),
                        ),
                      ]),
                      if (r.status == 'ReschedulePending') ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity, padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                          child: const Text('⏳ Yeniden planlama karşı tarafın onayını bekliyor.',
                            style: TextStyle(color: Colors.white70, fontSize: 13)),
                        ),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // ── Bilgi kartları ──
                  _InfoCard(icon: Icons.calendar_month_rounded, label: 'Randevu zamanı',
                    value: formatDateTime(r.requestedTime)),
                  const SizedBox(height: 8),
                  _InfoCard(icon: Icons.handyman_rounded, label: 'Hizmetler',
                    value: r.items.map((e) => '${e.serviceName} (₺${e.price.toStringAsFixed(0)})').join('\n')),
                  if (r.addressNote?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    _InfoCard(icon: Icons.location_on_rounded, label: 'Adres', value: r.addressNote!),
                  ],

                  // ── Doğrulama kodu + Aksiyonlar (Accepted / OnTheWay / Started) ──
                  if (r.status == 'Accepted' || r.status == 'OnTheWay' || r.status == 'Started') ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFF0FFF4), Color(0xFFF5FFF8)]),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.success.withValues(alpha: 0.15)),
                      ),
                      child: Column(children: [
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.vpn_key_rounded, color: AppColors.success, size: 20),
                          ),
                          const SizedBox(width: 10),
                          const Text('Doğrulama Kodu', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        ]),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.success.withValues(alpha: 0.2))),
                          child: Text(r.id.replaceAll('-', '').substring(0, 4).toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 26, letterSpacing: 8, color: AppColors.success)),
                        ),
                        const SizedBox(height: 12),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          _DetailActionChip(icon: Icons.call_rounded, label: 'İşletmeyi Ara', color: AppColors.success, onTap: () {
                            if (r.barberPhone?.isNotEmpty == true) launchUrl(Uri.parse('tel:${r.barberPhone}'));
                          }),
                          const SizedBox(width: 10),
                          _DetailActionChip(icon: Icons.close_rounded, label: 'İptal Et', color: Colors.red.shade600, onTap: _cancel),
                        ]),
                      ]),
                    ),
                  ],
                  // ── Puanla (Completed + canRate) ──
                  if (r.status == 'Completed' && r.canRate) ...[
                    const SizedBox(height: 14),
                    SizedBox(width: double.infinity, child: FilledButton.icon(
                      onPressed: () async {
                        final result = await showRatingDialog(context, title: 'İşletmeyi Puanla', subtitle: '${r.barberBusinessName ?? "İşletme"} için deneyiminizi değerlendirin.');
                        if (result != null && mounted) {
                          try { await RequestsRepo.instance.rate(r.id, result.score, result.comment); if (mounted) { _snack('Değerlendirmeniz kaydedildi.'); _refresh(); } } on ApiException catch (e) { if (mounted) _snack(e.message); }
                        }
                      },
                      icon: const Icon(Icons.star_rounded, size: 18),
                      label: const Text('Puanla'),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.warning, padding: const EdgeInsets.symmetric(vertical: 14)),
                    )),
                  ],
                  // ── Hata / Progress ──
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.error.withValues(alpha: 0.15))),
                      child: Row(children: [
                        const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13))),
                      ]),
                    ),
                  ],
                  if (_state == RequestDetailState.actionSubmitting) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(),
                  ],

                  // ── Aksiyon butonları ──
                  if (['Pending', 'Accepted', 'OnTheWay'].contains(r.status) ||
                      (r.status == 'ReschedulePending' && _canResolveReschedule)) ...[
                    const SizedBox(height: 16),
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      if (['Pending', 'Accepted', 'OnTheWay'].contains(r.status))
                        OutlinedButton.icon(
                          onPressed: _actionBusy ? null : _cancel,
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text('İptal Et'),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade600, side: BorderSide(color: Colors.red.shade300)),
                        ),
                      if (r.status == 'ReschedulePending' && _canResolveReschedule) ...[
                        OutlinedButton.icon(
                          onPressed: _actionBusy ? null : () => _action('reschedule-reject', (k) => _repo.resolveReschedule(r.id, false, idempotencyKey: k)),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text('Reddet'),
                        ),
                        FilledButton.icon(
                          onPressed: _actionBusy ? null : () => _action('reschedule-accept', (k) => _repo.resolveReschedule(r.id, true, idempotencyKey: k)),
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Kabul Et'),
                        ),
                      ],
                    ]),
                  ],

                  // ── Durum Zaman Çizelgesi ──
                  const SizedBox(height: 28),
                  const Text('Durum Geçmişi', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.2)),
                  const SizedBox(height: 12),
                  if (_timeline == null)
                    const LoadingSkeleton(height: 80)
                  else if (_timeline!.isEmpty)
                    const _EmptyTimeline()
                  else
                    ..._timeline!.asMap().entries.map((e) => _TimelineRow(
                      entry: e.value, isFirst: e.key == 0, isLast: e.key == _timeline!.length - 1,
                    )),
                ],
              ),
            ),
    );
  }

  Widget _buildLoadingError() => Center(
    child: _state == RequestDetailState.loading
        ? const CircularProgressIndicator()
        : Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 72, height: 72, decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: const Icon(Icons.error_outline, color: AppColors.error, size: 32)),
            const SizedBox(height: 16),
            Text(_error ?? 'Talep yüklenemedi.', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _refresh, child: const Text('Tekrar Dene')),
          ])),
  );

  IconData _statusIcon(String s) => switch (s) {
    'Pending' => Icons.hourglass_bottom_rounded,
    'Accepted' => Icons.check_circle_rounded,
    'Completed' => Icons.verified_rounded,
    'Cancelled' => Icons.cancel_rounded,
    'Rejected' => Icons.block_rounded,
    _ => Icons.schedule_rounded,
  };

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

class _DetailActionChip extends StatelessWidget {
  const _DetailActionChip({required this.icon, required this.label, required this.color, this.onTap});
  final IconData icon; final String label; final Color color; final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: color.withValues(alpha: 0.08),
    borderRadius: BorderRadius.circular(22),
    child: InkWell(borderRadius: BorderRadius.circular(22), onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color), const SizedBox(width: 6),
          Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: color)),
        ]),
      ),
    ),
  );
}

class _HeroInfo extends StatelessWidget {
  const _HeroInfo({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.45), fontWeight: FontWeight.w500)),
    const SizedBox(height: 2),
    Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
  ]);
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.label, required this.value});
  final IconData icon; final String label, value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFECECEF))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: AppColors.primary, size: 20)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, height: 1.35)),
      ])),
    ]),
  );
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.entry, required this.isFirst, required this.isLast});
  final RequestTimelineEntry entry;
  final bool isFirst, isLast;
  @override
  Widget build(BuildContext context) {
    final e = entry;
    final toLabel = requestStatusLabel(e.toStatus);
    final isCompleted = e.toStatus == 'Completed';
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 32, child: Column(children: [
          Container(width: 2, height: 14, color: isFirst ? Colors.transparent : AppColors.border),
          Expanded(child: Container(width: 2, color: isCompleted ? AppColors.success : (isLast ? Colors.transparent : AppColors.border))),
        ])),
        Container(
          width: 12, height: 12, margin: const EdgeInsets.only(top: 20),
          decoration: BoxDecoration(
            color: isCompleted ? AppColors.success : AppColors.border,
            shape: BoxShape.circle,
            border: Border.all(color: isCompleted ? AppColors.success : AppColors.textSecondary, width: 2),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFECECEF))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(toLabel, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: isCompleted ? AppColors.success : AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text('${formatDateTime(e.createdAt)} • ${e.changedByRole == 'Musteri' ? 'Müşteri' : 'İşletme'}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              if (e.reasonText?.isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(8)),
                  child: Text(e.reasonText!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFECECEF))),
    child: const Center(child: Text('Henüz durum geçmişi yok.', style: TextStyle(color: AppColors.textSecondary))),
  );
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 72, height: 72, decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), shape: BoxShape.circle),
        child: const Icon(Icons.error_outline, color: AppColors.error, size: 32)),
      const SizedBox(height: 16),
      Text(message, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      FilledButton.tonal(onPressed: retry, child: const Text('Tekrar Dene')),
    ])),
  );
}
