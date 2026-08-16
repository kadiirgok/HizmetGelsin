import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config.dart';
import '../../../core/theme/app_theme.dart';
import '../../requests/data/requests_repo.dart';
import '../../requests/controllers/request_submission.dart';
import '../../addresses/data/client_addresses_repo.dart';
import '../data/barbers_repo.dart';
import 'barber_sheet/barber_sheet_gallery.dart';
import 'barber_sheet/barber_sheet_hero.dart';
import 'barber_sheet/barber_sheet_reviews.dart';
import 'barber_sheet/barber_sheet_services.dart';

Future<void> showBarberSheet(
  BuildContext context,
  String barberProfileId,
  double clientLat,
  double clientLng, {
  bool previewOnly = false,
  BarberDetail? initialDetail,
  Uint8List? initialLogoBytes,
  ServiceRequestCreator? requestCreator,
  ClientAddressesRepository? addressesRepository,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _BarberSheet(
      barberProfileId: barberProfileId,
      clientLat: clientLat,
      clientLng: clientLng,
      previewOnly: previewOnly,
      initialDetail: initialDetail,
      initialLogoBytes: initialLogoBytes,
      requestCreator: requestCreator,
      addressesRepository: addressesRepository,
    ),
  );
}

class _BarberSheet extends StatefulWidget {
  const _BarberSheet({
    required this.barberProfileId,
    required this.clientLat,
    required this.clientLng,
    required this.previewOnly,
    this.initialDetail,
    this.initialLogoBytes,
    this.requestCreator,
    this.addressesRepository,
  });

  final String barberProfileId;
  final double clientLat;
  final double clientLng;
  final bool previewOnly;
  final BarberDetail? initialDetail;
  final Uint8List? initialLogoBytes;
  final ServiceRequestCreator? requestCreator;
  final ClientAddressesRepository? addressesRepository;

  @override
  State<_BarberSheet> createState() => _BarberSheetState();
}

class _BarberSheetState extends State<_BarberSheet> {
  BarberDetail? _detail;
  Uint8List? _logoBytes;
  String? _error;

  // Talep formu
  final _selectedServiceIds = <String>{};
  DateTime _requestedTime = DateTime.now(); // Her zaman şimdi — Tag tarzı anlık eşleşme

  bool _busy = false;
  final RequestSubmissionSession _submission = RequestSubmissionSession();
  ServiceRequestModel? _createdRequest;
  String? _resolvedAddress;
  bool _resolvingAddress = false;

  Future<void> _resolveAddress() async {
    if (_resolvingAddress) return;
    _resolvingAddress = true;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=${widget.clientLat}&lon=${widget.clientLng}&zoom=18&accept-language=tr',
      ));
      request.headers.set('User-Agent', 'HizmetGelsin/1.0');
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final displayName = data['display_name'] as String?;
        if (displayName != null && mounted) {
          setState(() => _resolvedAddress = displayName);
        }
      }
      client.close();
    } catch (_) {
      if (mounted) {
        setState(() => _resolvedAddress = 'GPS: ${widget.clientLat.toStringAsFixed(4)}, ${widget.clientLng.toStringAsFixed(4)}');
      }
    } finally {
      _resolvingAddress = false;
    }
  }

  void _handleServiceSelection(String serviceId, bool selected) {
    if (_busy) return;
    setState(() {
      if (selected) {
        _selectedServiceIds.add(serviceId);
      } else {
        _selectedServiceIds.remove(serviceId);
      }
      _submission.formChanged();
    });
  }

  @override
  void initState() {
    super.initState();
    _detail = widget.initialDetail;
    _logoBytes = widget.initialLogoBytes;
    if (_detail == null) _load();
    _resolveAddress();
  }

  Future<void> _load() async {
    try {
      final detail = await BarbersRepo.instance.detail(widget.barberProfileId);
      if (mounted) {
        setState(() {
          _detail = detail;
        });
      }
      if (detail.hasLogo) {
        try {
          final bytes = await BarbersRepo.instance.logoBytes(
            widget.barberProfileId,
          );
          if (mounted) setState(() => _logoBytes = Uint8List.fromList(bytes));
        } catch (_) {}
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  void dispose() {
    super.dispose();
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

  // Tag tarzı anlık eşleşme — zaman seçimi yok, her zaman "şimdi"

  Future<void> _createRequest() async {
    if (_busy) return;
    if (_selectedServiceIds.isEmpty) {
      _snack('En az bir hizmet seçin.', error: true);
      return;
    }
    final detail = _detail!;
    final basePrice = detail.services
        .where((s) => _selectedServiceIds.contains(s.id))
        .fold<double>(0, (sum, s) => sum + s.price);

    // Fiyat pazarlık dialog'u — ±%10
    final proposedPrice = await _showPriceDialog(basePrice);
    if (proposedPrice == null || !mounted) return; // kullanıcı vazgeçti

    final idempotencyKey = _submission.begin();
    setState(() => _busy = true);
    try {
      final created = await (widget.requestCreator ?? RequestsRepo.instance)
          .create(
            barberProfileId: widget.barberProfileId,
            serviceIds: _selectedServiceIds.toSet().toList(),
            requestedTime: _requestedTime,
            lat: widget.clientLat,
            lng: widget.clientLng,
            addressNote: _resolvedAddress,
            addressId: null,
            serviceLocationType: 'customerAddress',
            proposedPrice: proposedPrice,
            idempotencyKey: idempotencyKey,
          );
      if (!mounted) return;
      _submission.succeeded();
      setState(() => _createdRequest = created);
    } on ApiException catch (e) {
      final mapped = mapRequestError(e);
      if (e.code == 'request_idempotency_conflict') _submission.formChanged();
      _submission.failed(mapped.state);
      if (mounted) _snack(mapped.message, error: true);
    } catch (e) {
      if (mounted) _snack('Talep gönderilemedi: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// ±%10 fiyat ayarlama dialog'u. null = vazgeçti.
  Future<double?> _showPriceDialog(double basePrice) async {
    final minPrice = (basePrice * 0.9).roundToDouble();
    final maxPrice = (basePrice * 1.1).roundToDouble();
    var currentPrice = basePrice.roundToDouble();
    final step = ((basePrice * 0.02) / 10).ceil() * 10.0;
    if (step <= 0) return basePrice;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Fiyat Teklifi'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Hizmet bedeli: ${basePrice.toStringAsFixed(0)} TL\nTeklifiniz ±%10 aralığında olmalı.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PriceButton(
                    icon: Icons.remove,
                    onTap: currentPrice > minPrice
                        ? () => setDialogState(() => currentPrice = (currentPrice - step).clamp(minPrice, maxPrice))
                        : null,
                  ),
                  const SizedBox(width: 20),
                  Column(
                    children: [
                      Text('${currentPrice.toStringAsFixed(0)} TL',
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(
                        currentPrice < basePrice
                            ? '%${(((basePrice - currentPrice) / basePrice) * 100).toStringAsFixed(0)} indirim'
                            : currentPrice > basePrice
                            ? '%${(((currentPrice - basePrice) / basePrice) * 100).toStringAsFixed(0)} fark'
                            : 'Standart fiyat',
                        style: TextStyle(
                          fontSize: 12,
                          color: currentPrice == basePrice ? Colors.grey : currentPrice < basePrice ? Colors.green.shade600 : Colors.orange.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 20),
                  _PriceButton(
                    icon: Icons.add,
                    onTap: currentPrice < maxPrice
                        ? () => setDialogState(() => currentPrice = (currentPrice + step).clamp(minPrice, maxPrice))
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Min: ${minPrice.toStringAsFixed(0)} TL — Max: ${maxPrice.toStringAsFixed(0)} TL',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('${currentPrice.toStringAsFixed(0)} TL Gönder'),
            ),
          ],
        ),
      ),
    );
    return confirmed == true ? currentPrice : null;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        if (_error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(_error!),
            ),
          );
        }
        final detail = _detail;
        if (detail == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_createdRequest != null) {
          return _RequestSuccess(
            requestId: _createdRequest!.id,
            onRequests: () {
              final router = GoRouter.of(context);
              Navigator.pop(context);
              router.go('/taleplerim');
            },
            onClose: () => Navigator.pop(context),
          );
        }
        final coverPhoto = detail.photos.where((p) => p.isCover).firstOrNull;
        return Stack(
          children: [
            IgnorePointer(
              ignoring: _busy,
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  MediaQuery.paddingOf(context).bottom + 32,
                ),
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (widget.previewOnly) ...[
                    Container(
                      key: const ValueKey('barber-preview-banner'),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF1A1A1C), Color(0xFF2D2D30)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.visibility_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Müşteri Önizlemesi',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Profiliniz müşterilere böyle görünüyor',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.phone_iphone_rounded,
                                    color: Colors.white70, size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'Canlı',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  BarberSheetHero(
                    detail: detail,
                    logoBytes: _logoBytes,
                    coverUrl: coverPhoto == null
                        ? null
                        : _absolutePhotoUrl(coverPhoto.url),
                    galleryUrls: detail.photos
                        .map((photo) => _absolutePhotoUrl(photo.url))
                        .toList(growable: false),
                    onCall: widget.previewOnly || detail.phoneNumber == null
                        ? null
                        : () => launchUrl(
                            Uri.parse('tel:+${detail.phoneNumber}'),
                          ),
                  ),
                  const SizedBox(height: 20),
                  BarberPhotoGallery(
                    photos: detail.photos,
                    coverPhotoUrl: coverPhoto == null
                        ? null
                        : _absolutePhotoUrl(coverPhoto.url),
                    businessName: detail.displayName,
                    absoluteUrlBuilder: _absolutePhotoUrl,
                  ),
                  if (detail.description?.isNotEmpty == true ||
                      detail.badges.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.fieldFill,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (detail.description?.isNotEmpty == true)
                            Text(
                              detail.description!,
                              style: const TextStyle(height: 1.35),
                            ),
                          if (detail.badges.isNotEmpty) ...[
                            if (detail.description?.isNotEmpty == true)
                              const SizedBox(height: 8),
                            Wrap(
                              spacing: 10,
                              runSpacing: 6,
                              children: detail.badges
                                  .map(
                                    (badge) => _PreviewInfoBadge(label: badge),
                                  )
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],
                  BarberServicesSection(
                    services: detail.services,
                    previewOnly: widget.previewOnly,
                    selectedServiceIds: _selectedServiceIds,
                    onSelectionChanged: _handleServiceSelection,
                  ),
                  const SizedBox(height: 22),
                  BarberReviewsSection(reviews: detail.reviews),
                  if (!widget.previewOnly) ...[
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _createRequest,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.bolt),
                        label: Text(
                          _busy ? 'Gönderiliyor…' : 'Talep Et${_selectedServiceIds.isNotEmpty ? ' • ₺${detail.services.where((s) => _selectedServiceIds.contains(s.id)).fold<double>(0, (sum, item) => sum + item.price).toStringAsFixed(0)}' : ''}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _absolutePhotoUrl(String path) =>
      path.startsWith('http') ? path : '${AppConfig.baseUrl}$path';
}

class _RequestSuccess extends StatelessWidget {
  const _RequestSuccess({
    required this.requestId,
    required this.onRequests,
    required this.onClose,
  });

  final String requestId;
  final VoidCallback onRequests;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Column(
      key: const Key('request-success-state'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 32),
        const Icon(Icons.check_circle, size: 72, color: Colors.green),
        const SizedBox(height: 16),
        const Text(
          'Talebiniz alındı',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'İşletmenin yanıtını Taleplerim ekranından takip edebilirsiniz.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Talep: ${requestId.substring(0, requestId.length.clamp(0, 8))}',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('go-to-my-requests'),
            onPressed: onRequests,
            child: const Text('Talebi Görüntüle'),
          ),
        ),
        TextButton(onPressed: onClose, child: const Text('Ana Sayfaya Dön')),
      ],
    ),
  );
}

class _PreviewInfoBadge extends StatelessWidget {
  const _PreviewInfoBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final displayLabel = switch (label) {
      'Telefonla Ulaşılabilir' => 'Telefon müşterilere görünür',
      'Telefon Gizli' => 'Telefon müşterilere gizli',
      _ => label,
    };
    final isPhoneStatus =
        label == 'Telefonla Ulaşılabilir' || label == 'Telefon Gizli';
    return Semantics(
      label: displayLabel,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPhoneStatus
                  ? Icons.phone_in_talk_outlined
                  : Icons.local_activity_outlined,
              color: AppTheme.textSecondary,
              size: 17,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                displayLabel,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceButton extends StatelessWidget {
  const _PriceButton({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: onTap != null ? AppColors.primary : Colors.grey.shade300,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    ),
  );
}

