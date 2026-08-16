import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/customer_ui.dart';
import '../../../core/widgets/osm_attribution.dart';
import '../data/barbers_repo.dart';
import '../widgets/barber_sheet.dart';
import '../widgets/barber_sheet/barber_sheet_gallery.dart';
import '../widgets/barber_sheet/barber_sheet_hero.dart';
import '../../ratings/data/client_ratings_repo.dart';

class ClientBarberDetailScreen extends StatefulWidget {
  const ClientBarberDetailScreen({
    super.key,
    required this.barberProfileId,
    this.repository,
    this.ratingsRepository,
    this.initialAvailabilityDate,
  });
  final String barberProfileId;
  final BarberDetailRepository? repository;
  final ClientRatingsRepository? ratingsRepository;
  final DateTime? initialAvailabilityDate;

  @override
  State<ClientBarberDetailScreen> createState() =>
      _ClientBarberDetailScreenState();
}

class _ClientBarberDetailScreenState extends State<ClientBarberDetailScreen> {
  late final BarberDetailRepository _repo =
      widget.repository ?? BarbersRepo.instance;
  late final ClientRatingsRepository _ratingsRepo =
      widget.ratingsRepository ?? ClientRatingsRepo.instance;
  BarberDetail? _detail;
  Uint8List? _logoBytes;
  String? _error;
  final _reviews = <BarberReview>[];
  int _reviewPage = 0;
  bool _reviewsLoading = false,
      _reviewsLoadingMore = false,
      _hasMoreReviews = true;
  String? _reviewsError;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _error = null;
      _detail = null;
    });
    try {
      final detail = await _repo.detail(widget.barberProfileId);
      if (!mounted) return;
      setState(() => _detail = detail);
      if (detail.hasLogo) {
        try {
          final bytes = await _repo.logoBytes(widget.barberProfileId);
          if (mounted) setState(() => _logoBytes = Uint8List.fromList(bytes));
        } catch (_) {}
      }
      await _loadReviews(reset: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _error = switch (e.statusCode) {
          401 || 403 => 'Bu işletmeyi görüntüleme yetkiniz yok.',
          404 => 'Bu işletme artık görüntülenemiyor.',
          _ => 'İşletme bilgileri yüklenemedi. Lütfen tekrar deneyin.',
        },
      );
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'İşletme bilgileri yüklenemedi. Lütfen tekrar deneyin.',
        );
      }
    }
  }

  Future<void> _loadReviews({bool reset = false}) async {
    if (_reviewsLoading ||
        _reviewsLoadingMore ||
        (!reset && !_hasMoreReviews)) {
      return;
    }
    setState(() {
      _reviewsError = null;
      if (reset) {
        _reviewsLoading = true;
      } else {
        _reviewsLoadingMore = true;
      }
    });
    try {
      final page = await _repo.reviews(
        widget.barberProfileId,
        page: reset ? 1 : _reviewPage + 1,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _reviews.clear();
        final existing = _reviews.map(_reviewKey).toSet();
        _reviews.addAll(
          page.items.where((item) => existing.add(_reviewKey(item))),
        );
        _reviewPage = page.page;
        _hasMoreReviews = page.hasNextPage;
      });
    } catch (_) {
      if (mounted) setState(() => _reviewsError = 'Yorumlar yüklenemedi.');
    } finally {
      if (mounted) {
        setState(() {
          _reviewsLoading = false;
          _reviewsLoadingMore = false;
        });
      }
    }
  }

  String _reviewKey(BarberReview r) =>
      r.id ??
      '${r.createdAt.toUtc().toIso8601String()}|${r.clientName}|${r.score}|${r.comment}';

  Future<void> _report(BarberReview review) async {
    if (review.id == null || review.isOwn) return;
    String? reason;
    var description = '';
    var submitting = false;
    String? validation;
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Yorumu raporla',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('rating-report-reason'),
                  initialValue: reason,
                  decoration: InputDecoration(
                    labelText: 'Neden',
                    errorText: validation,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'spam', child: Text('Spam')),
                    DropdownMenuItem(
                      value: 'abuse',
                      child: Text('Hakaret veya taciz'),
                    ),
                    DropdownMenuItem(
                      value: 'personal_data',
                      child: Text('Kişisel bilgi'),
                    ),
                    DropdownMenuItem(
                      value: 'false_information',
                      child: Text('Yanlış bilgi'),
                    ),
                    DropdownMenuItem(value: 'other', child: Text('Diğer')),
                  ],
                  onChanged: submitting
                      ? null
                      : (v) => setSheetState(() {
                          reason = v;
                          validation = null;
                        }),
                ),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (value) => description = value,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Açıklama'),
                ),
                FilledButton(
                  key: const Key('rating-report-submit'),
                  onPressed: submitting
                      ? null
                      : () async {
                          if (reason == null ||
                              (reason == 'other' &&
                                  description.trim().isEmpty)) {
                            setSheetState(
                              () => validation = reason == null
                                  ? 'Bir neden seçin.'
                                  : 'Diğer nedeni için açıklama yazın.',
                            );
                            return;
                          }
                          setSheetState(() => submitting = true);
                          try {
                            await _ratingsRepo.report(
                              review.id!,
                              reasonCode: reason!,
                              description: description.trim().isEmpty
                                  ? null
                                  : description.trim(),
                            );
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext, true);
                            }
                          } on ApiException catch (e) {
                            if (!sheetContext.mounted) return;
                            setSheetState(() {
                              submitting = false;
                              validation = ratingErrorMessage(
                                mapRatingError(e),
                              );
                            });
                          } catch (_) {
                            if (!sheetContext.mounted) return;
                            setSheetState(() {
                              submitting = false;
                              validation = ratingErrorMessage(
                                RatingError.network,
                              );
                            });
                          }
                        },
                  child: Text(submitting ? 'Gönderiliyor…' : 'Raporla'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (submitted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yorum inceleme için bildirildi.')),
      );
    }
  }

  Future<void> _openRequest() async {
    final detail = _detail;
    if (detail == null) return;
    try {
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      await showBarberSheet(
        context,
        widget.barberProfileId,
        position.latitude,
        position.longitude,
        initialDetail: detail,
        initialLogoBytes: _logoBytes,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Talep oluşturmak için cihaz konumunu etkinleştirin.'),
        ),
      );
    }
  }

  String _url(String value) =>
      value.startsWith('http') ? value : '${AppConfig.baseUrl}$value';

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final phone = detail?.phoneNumber;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('İşletme', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -0.2)),
        actions: [
          if (phone?.isNotEmpty == true)
            IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white),
              onPressed: () => _call(phone!),
              icon: const Icon(Icons.call_rounded, size: 20),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _body(),
      bottomNavigationBar: detail == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: PrimaryButton(
                  key: const Key('create-service-request'),
                  onPressed: _openRequest,
                  icon: Icons.send_outlined,
                  label: 'Hizmet Talebi Oluştur',
                ),
              ),
            ),
    );
  }

  static const _cardBorder = Color(0xFFECECEF);

  Widget _body() {
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _loadDetail);
    }
    final detail = _detail;
    if (detail == null) {
      return const CustomerListSkeleton(itemCount: 2, cardHeight: 180, withImage: true);
    }
    final cover = detail.coverImageUrl ?? detail.photos.where((p) => p.isCover).firstOrNull?.url;
    final galleryUrls = detail.photos.map((p) => _url(p.url)).toList(growable: false);
    final nonCoverPhotos = detail.photos.where((p) => !p.isCover).toList();
    final address = [detail.neighborhood, detail.district, detail.city].whereType<String>().where((e) => e.isNotEmpty).join(', ');

    return ListView(
      key: const Key('client-barber-detail'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // ── Hero ──
        BarberSheetHero(
          detail: detail,
          logoBytes: _logoBytes,
          coverUrl: cover == null ? null : _url(cover),
          galleryUrls: galleryUrls,
          onCall: null, // call is in AppBar
        ),
        const SizedBox(height: 14),

        // ── Hakkında + Adres + Badge Kartı ──
        _premiumCard(children: [
          // Açıklama
          if (detail.description?.trim().isNotEmpty == true) ...[
            Text(detail.description!, style: const TextStyle(fontSize: 13.5, height: 1.45, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
          ],
          // Durum
          Wrap(spacing: 6, runSpacing: 6, children: [
            _badge(
              icon: Icons.circle_rounded,
              label: detail.isOpenNow ? 'Açık' : 'Kapalı',
              color: detail.isOpenNow ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
            ),
          ]),
          const SizedBox(height: 10),
          // Adres + servis modu + radius
          _infoRow(icon: Icons.location_on_outlined, text: address.isNotEmpty ? address : 'Konum bilgisi yok'),
          const SizedBox(height: 4),
          _infoRow(icon: Icons.directions_car_outlined, text: '${_serviceMode(detail.serviceMode)} · ${detail.serviceRadiusKm} km hizmet alanı'),
        ]),

        // ── Fotoğraf Galerisi ──
        if (nonCoverPhotos.isNotEmpty) ...[
          const SizedBox(height: 14),
          BarberPhotoGallery(photos: nonCoverPhotos, coverPhotoUrl: null, businessName: detail.displayName, absoluteUrlBuilder: _url),
        ],

        // ── Hizmetler ──
        const SizedBox(height: 14),
        _premiumCard(children: [
          const Text('Hizmetler', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 10),
          ...detail.services.map((s) => _serviceRow(s)),
        ]),

        // ── Konum Haritası ──
        if (detail.lat != null && detail.lng != null) ...[
          const SizedBox(height: 14),
          _locationMap(detail.lat!, detail.lng!),
        ],

        // ── Yorumlar ──
        const SizedBox(height: 14),
        _reviewsSection(),
      ],
    );
  }

  // ── Premium UI yardımcıları ──

  Widget _premiumCard({required List<Widget> children}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _cardBorder),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 8))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );

  Widget _badge({required IconData icon, required String label, required Color color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: color)),
    ]),
  );

  Widget _infoRow({required IconData icon, required String text}) => Row(children: [
    Icon(icon, size: 14, color: AppColors.textSecondary),
    const SizedBox(width: 6),
    Flexible(child: Text(text, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontWeight: FontWeight.w500))),
  ]);

  Widget _serviceRow(BarberServiceItem s) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Container(
        width: 38, height: 38,
        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.design_services_outlined, size: 18, color: AppColors.primary),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
          if (s.isPopular) ...[
            const SizedBox(width: 6),
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(5)), child: const Text('Popüler', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10, color: AppColors.warning))),
          ],
        ]),
        if (s.description?.isNotEmpty == true) ...[
          const SizedBox(height: 2),
          Text(s.description!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ])),
      const SizedBox(width: 8),
      Text('₺${s.price.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.primary)),
    ]),
  );

  String _serviceMode(String value) => switch (value.toLowerCase()) {
    'atbusiness' || 'shop' => 'İşletmede',
    'atcustomerlocation' || 'mobile' => 'Adresinize gelir',
    'both' => 'İşletmede ve adreste',
    _ => value,
  };

  void _call(String phone) {
    // Telefon uygulamasını aç — gerçek numara backend'de sharePhone kontrolüyle döner
  }

  Widget _locationMap(double lat, double lng) => _premiumCard(children: [
    const Text('Konum', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
    const SizedBox(height: 10),
    ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 160,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(lat, lng),
            initialZoom: 15,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
          ),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.berbergelsin.berbergelsin'),
            MarkerLayer(markers: [
              Marker(point: LatLng(lat, lng), width: 36, height: 36, child: const Icon(Icons.location_pin, color: AppTheme.primary, size: 36)),
            ]),
            const OsmAttribution(),
          ],
        ),
      ),
    ),
  ]);

  Widget _reviewsSection() => Column(
    key: const Key('reviews-section'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text('Yorumlar (${_detail!.ratingCount})', style: AppTypography.titleMedium),
          ),
          if (_detail!.avgRating != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded, color: AppColors.warning, size: 16),
                  const SizedBox(width: 3),
                  Text(_detail!.avgRating!.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.warning)),
                ],
              ),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      if (_reviewsLoading)
        const LoadingSkeleton(height: 88, radius: AppRadius.lg)
      else if (_reviewsError != null)
        Row(children: [
          Expanded(child: Text(_reviewsError!)),
          TextButton(onPressed: () => _loadReviews(reset: true), child: const Text('Tekrar dene')),
        ])
      else if (_reviews.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFECECEF)),
          ),
          child: const Column(children: [
            Icon(Icons.rate_review_outlined, size: 36, color: AppColors.textSecondary),
            SizedBox(height: 8),
            Text('Henüz yorum yok', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          ]),
        )
      else
        ..._reviews.map((r) => _PremiumReviewCard(
          review: r,
          onReport: r.id == null || r.isOwn ? null : () => _report(r),
          onEdit: r.isOwn && r.id != null ? () => _editReview(r) : null,
          onDelete: r.isOwn && r.id != null ? () => _deleteReview(r) : null,
        )),
      if (_hasMoreReviews && !_reviewsLoading)
        Center(
          child: TextButton(
            key: const Key('reviews-load-more'),
            onPressed: _reviewsLoadingMore ? null : _loadReviews,
            child: Text(_reviewsLoadingMore ? 'Yükleniyor…' : 'Daha fazla yorum'),
          ),
        ),
    ],
  );

  Future<void> _editReview(BarberReview review) async {
    if (review.id == null) return;
    final scoreController = TextEditingController(text: '${review.score}');
    final commentController = TextEditingController(text: review.comment ?? '');
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(ctx).bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Yorumu Düzenle', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          Row(children: List.generate(5, (i) => IconButton(
            icon: Icon(i < (int.tryParse(scoreController.text) ?? review.score) ? Icons.star_rounded : Icons.star_border_rounded, color: AppColors.warning, size: 28),
            onPressed: () => scoreController.text = '${i + 1}',
          ))),
          const SizedBox(height: 8),
          TextField(controller: commentController, maxLines: 3, decoration: const InputDecoration(labelText: 'Yorumunuz')),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Güncelle'),
          )),
        ]),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ClientRatingsRepo.instance.update(review.id!, score: int.parse(scoreController.text), comment: commentController.text.trim(), version: review.version ?? '');
      if (mounted) await _loadReviews(reset: true);
    } on ApiException catch (e) { if (mounted) _snack('Güncellenemedi: ${e.message}'); }
  }

  Future<void> _deleteReview(BarberReview review) async {
    if (review.id == null) return;
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Yorumu Sil'),
      content: const Text('Bu yorumu silmek istediğinize emin misiniz?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Sil')),
      ],
    ));
    if (confirmed != true || !mounted) return;
    try {
      await ClientRatingsRepo.instance.delete(review.id!);
      if (mounted) await _loadReviews(reset: true);
    } on ApiException catch (e) { if (mounted) _snack('Silinemedi: ${e.message}'); }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

class _PremiumReviewCard extends StatelessWidget {
  const _PremiumReviewCard({required this.review, this.onReport, this.onEdit, this.onDelete});
  final BarberReview review;
  final VoidCallback? onReport, onEdit, onDelete;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFECECEF)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.warning.withValues(alpha: 0.12),
          child: Text('${review.score}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.warning, fontSize: 15)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(review.clientName ?? 'Müşteri', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
                Text(_timeAgo(review.createdAt), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ]),
              if (review.comment?.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(review.comment!, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ],
              if (review.isOwn && (onEdit != null || onDelete != null)) ...[
                const SizedBox(height: 8),
                Row(children: [
                  if (onEdit != null) TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit, size: 16), label: const Text('Düzenle', style: TextStyle(fontSize: 12)), style: TextButton.styleFrom(visualDensity: VisualDensity.compact)),
                  if (onDelete != null) TextButton.icon(onPressed: onDelete, icon: const Icon(Icons.delete_outline, size: 16), label: const Text('Sil', style: TextStyle(fontSize: 12)), style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: Colors.red)),
                ]),
              ],
            ],
          ),
        ),
        if (onReport != null)
          IconButton(tooltip: 'Raporla', onPressed: onReport, icon: const Icon(Icons.flag_outlined, size: 18), visualDensity: VisualDensity.compact),
      ],
    ),
  );
}

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inDays > 30) return '${diff.inDays ~/ 30} ay önce';
  if (diff.inDays > 0) return '${diff.inDays} gün önce';
  if (diff.inHours > 0) return '${diff.inHours} saat önce';
  return '${diff.inMinutes} dk önce';
}
