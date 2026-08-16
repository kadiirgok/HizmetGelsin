import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/barbers_repo.dart';
import 'barber_sheet_image_metadata.dart';

typedef HeroImageSizeResolver = BarberImageSizeResolver;

class HeroImageCandidate {
  const HeroImageCandidate({
    required this.url,
    required this.width,
    required this.height,
    required this.isCover,
    required this.order,
    this.hasBlackBarRisk = false,
  });

  final String url;
  final int width;
  final int height;
  final bool isCover;
  final int order;
  final bool hasBlackBarRisk;

  double get aspectRatio => width > 0 && height > 0 ? width / height : 0;
}

HeroImageCandidate? selectHeroImageCandidate(
  Iterable<HeroImageCandidate> candidates,
) {
  final safe = candidates
      .where((candidate) {
        final ratio = candidate.aspectRatio;
        return candidate.url.trim().isNotEmpty &&
            candidate.width > 0 &&
            candidate.height > 0 &&
            !candidate.hasBlackBarRisk &&
            (candidate.isCover || (ratio >= 1.2 && ratio <= 3.2));
      })
      .toList(growable: false);
  for (final candidate in safe) {
    if (candidate.isCover) return candidate;
  }
  if (safe.isEmpty) return null;
  const preferredRatio = 16 / 9;
  return safe.reduce((best, candidate) {
    final bestDistance = (best.aspectRatio - preferredRatio).abs();
    final candidateDistance = (candidate.aspectRatio - preferredRatio).abs();
    if (candidateDistance < bestDistance) return candidate;
    if (candidateDistance == bestDistance && candidate.order < best.order) {
      return candidate;
    }
    return best;
  });
}

class BarberSheetHero extends StatefulWidget {
  const BarberSheetHero({
    super.key,
    required this.detail,
    required this.logoBytes,
    required this.coverUrl,
    this.galleryUrls = const [],
    required this.onCall,
    this.imageSizeResolver,
  });

  final BarberDetail detail;
  final Uint8List? logoBytes;
  final String? coverUrl;
  final List<String> galleryUrls;
  final VoidCallback? onCall;
  final HeroImageSizeResolver? imageSizeResolver;

  @override
  State<BarberSheetHero> createState() => _BarberSheetHeroState();
}

class _BarberSheetHeroState extends State<BarberSheetHero> {
  String? _selectedUrl;
  List<String> _eligibleUrls = const [];
  int _selectedIndex = -1;
  String? _resolutionKey;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _startResolutionIfNeeded();
  }

  @override
  void didUpdateWidget(covariant BarberSheetHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    _startResolutionIfNeeded();
  }

  void _startResolutionIfNeeded() {
    final key = [widget.coverUrl ?? '', ...widget.galleryUrls].join('\u0000');
    if (_resolutionKey == key) return;
    _resolutionKey = key;
    _selectedUrl = null;
    _eligibleUrls = const [];
    _selectedIndex = -1;
    final generation = ++_generation;
    unawaited(_resolveCandidates(generation));
  }

  Future<void> _resolveCandidates(int generation) async {
    final seen = <String>{};
    final inputs = <({String url, bool isCover, int order})>[];
    void add(String? raw, bool isCover, int order) {
      final url = raw?.trim() ?? '';
      final key = _normalizeUrl(url);
      if (url.isEmpty || !seen.add(key)) return;
      inputs.add((url: url, isCover: isCover, order: order));
    }

    add(widget.coverUrl, true, -1);
    for (var index = 0; index < widget.galleryUrls.length; index++) {
      add(widget.galleryUrls[index], false, index);
    }

    final resolved = <HeroImageCandidate>[];
    for (final input in inputs) {
      final size = await _resolveSize(input.url);
      if (!mounted || generation != _generation) return;
      if (size == null) continue;
      final candidate = HeroImageCandidate(
        url: input.url,
        width: size.width.round(),
        height: size.height.round(),
        isCover: input.isCover,
        order: input.order,
        hasBlackBarRisk: await _hasHorizontalBlackBars(input.url),
      );
      if (!mounted || generation != _generation) return;
      assert(() {
        debugPrint(
          'Hero metadata ${input.isCover ? 'cover' : 'gallery'}: '
          '${candidate.width}x${candidate.height}, '
          'ratio=${candidate.aspectRatio.toStringAsFixed(3)}, '
          'blackBars=${candidate.hasBlackBarRisk}',
        );
        return true;
      }());
      resolved.add(candidate);
    }
    final selected = selectHeroImageCandidate(resolved);
    if (!mounted || generation != _generation) return;
    assert(() {
      debugPrint(
        'Hero selected: ${selected == null
            ? 'gradient fallback'
            : selected.isCover
            ? 'cover'
            : 'gallery'}',
      );
      return true;
    }());
    final safeGallery =
        resolved
            .where(
              (candidate) =>
                  !candidate.isCover &&
                  !candidate.hasBlackBarRisk &&
                  candidate.aspectRatio >= 1.2 &&
                  candidate.aspectRatio <= 3.2,
            )
            .toList()
          ..sort((a, b) {
            const preferredRatio = 16 / 9;
            final ratioOrder = (a.aspectRatio - preferredRatio).abs().compareTo(
              (b.aspectRatio - preferredRatio).abs(),
            );
            return ratioOrder != 0 ? ratioOrder : a.order.compareTo(b.order);
          });
    final eligible = <String>[
      if (selected?.isCover == true) selected!.url,
      ...safeGallery.map((candidate) => candidate.url),
    ];
    if (selected != null && !eligible.contains(selected.url)) {
      eligible.insert(0, selected.url);
    }
    setState(() {
      _eligibleUrls = eligible;
      _selectedIndex = eligible.isEmpty ? -1 : 0;
      _selectedUrl = eligible.firstOrNull;
    });
  }

  void _handleImageError() {
    if (!mounted || _selectedIndex < 0) return;
    final next = _selectedIndex + 1;
    if (next >= _eligibleUrls.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || next >= _eligibleUrls.length) return;
      setState(() {
        _selectedIndex = next;
        _selectedUrl = _eligibleUrls[next];
      });
    });
  }

  Future<Size?> _resolveSize(String url) {
    final override = widget.imageSizeResolver;
    if (override != null) return override(url);
    return BarberImageMetadataCache.resolve(context, url);
  }

  Future<bool> _hasHorizontalBlackBars(String url) {
    // Test/custom metadata resolvers do not expose pixels; selection tests pass
    // the risk directly to HeroImageCandidate.
    if (widget.imageSizeResolver != null) return Future.value(false);
    return BarberImageMetadataCache.hasHorizontalBlackBars(context, url);
  }

  String _normalizeUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme) return value.trim().toLowerCase();
    return uri
        .replace(
          scheme: uri.scheme.toLowerCase(),
          host: uri.host.toLowerCase(),
          fragment: '',
        )
        .toString();
  }

  @override
  Widget build(BuildContext context) => _BarberSheetHeroContent(
    detail: widget.detail,
    logoBytes: widget.logoBytes,
    coverUrl: _selectedUrl,
    onImageError: _handleImageError,
    onCall: widget.onCall,
  );
}

class _BarberSheetHeroContent extends StatelessWidget {
  const _BarberSheetHeroContent({
    required this.detail,
    required this.logoBytes,
    required this.coverUrl,
    required this.onImageError,
    required this.onCall,
  });

  final BarberDetail detail;
  final Uint8List? logoBytes;
  final String? coverUrl;
  final VoidCallback onImageError;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final location = [
      detail.neighborhood,
      detail.district,
      detail.city,
    ].whereType<String>().where((e) => e.trim().isNotEmpty).join(' / ');
    const coverHeight = 140.0;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final coverCacheWidth = (MediaQuery.sizeOf(context).width * pixelRatio)
        .round()
        .clamp(320, 1200);
    final identityLine = [
      if (detail.category?.trim().isNotEmpty == true) detail.category!.trim(),
      if (location.isNotEmpty) location,
    ].join(' · ');

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFECECEF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            key: const ValueKey('barber-hero-cover-clip'),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(23)),
            child: SizedBox(
              key: const ValueKey('barber-hero-cover'),
              height: coverHeight,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (coverUrl == null)
                    DecoratedBox(
                      key: const ValueKey('barber-hero-fallback'),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Theme.of(context).colorScheme.primaryContainer,
                            Theme.of(context).colorScheme.secondaryContainer,
                          ],
                        ),
                      ),
                    )
                  else
                    Image.network(
                      key: const ValueKey('barber-hero-cover-image'),
                      coverUrl!,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      excludeFromSemantics: true,
                      cacheWidth: coverCacheWidth,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) {
                        onImageError();
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Theme.of(context).colorScheme.primaryContainer,
                                Theme.of(
                                  context,
                                ).colorScheme.secondaryContainer,
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  Positioned(
                    left: 16,
                    bottom: 12,
                    child: ExcludeSemantics(
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(17),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 12,
                              offset: const Offset(0, 5),
                            ),
                          ],
                          image: logoBytes == null
                              ? null
                              : DecorationImage(
                                  image: MemoryImage(logoBytes!),
                                  fit: BoxFit.cover,
                                ),
                        ),
                        child: logoBytes == null
                            ? Container(
                                color: _catColor(detail.category),
                                child: Center(
                                  child: Icon(
                                    _catIco(detail.category),
                                    color: Colors.white,
                                    size: 26,
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    detail.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                      letterSpacing: -0.35,
                    ),
                  ),
                ),
                if (identityLine.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    identityLine,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 7,
                        children: [
                          if (detail.ratingCount > 0)
                            Semantics(
                              label:
                                  '5 üzerinden ${detail.avgRating?.toStringAsFixed(1)}, ${detail.ratingCount} yorum',
                              child: ExcludeSemantics(
                                child: _HeroInfoPill(
                                  icon: Icons.star_rounded,
                                  text:
                                      '${detail.avgRating?.toStringAsFixed(1)} · ${detail.ratingCount} yorum',
                                ),
                              ),
                            ),
                          _HeroInfoPill(
                            icon: Icons.design_services_outlined,
                            text: '${detail.services.length} hizmet',
                          ),
                        ],
                      ),
                    ),
                    if (onCall != null) ...[
                      const SizedBox(width: 10),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: onCall,
                        tooltip: 'Ara',
                        icon: const Icon(Icons.call_rounded),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroInfoPill extends StatelessWidget {
  const _HeroInfoPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.fieldFill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.primary, size: 14),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _catColor(String? c) {
  final l = (c ?? '').toLowerCase();
  if (l.contains('tesisat') || l.contains('su')) return const Color(0xFF1565C0);
  if (l.contains('elektrik')) return const Color(0xFFFF8F00);
  if (l.contains('temiz')) return const Color(0xFF00ACC1);
  if (l.contains('oto') || l.contains('ara')) return const Color(0xFFC62828);
  if (l.contains('ders') || l.contains('eğitim')) return const Color(0xFF7B1FA2);
  if (l.contains('kuaf') || l.contains('berber') || l.contains('güzellik')) return const Color(0xFF37474F);
  if (l.contains('nakliye') || l.contains('taşı')) return const Color(0xFF2E7D32);
  if (l.contains('sağlık') || l.contains('bakım')) return const Color(0xFFAD1457);
  if (l.contains('organizasyon')) return const Color(0xFF6A1B9A);
  if (l.contains('hayvan')) return const Color(0xFF8D6E63);
  if (l.contains('bahçe') || l.contains('peyzaj')) return const Color(0xFF43A047);
  if (l.contains('bilgisayar') || l.contains('teknik')) return const Color(0xFF455A64);
  if (l.contains('beyaz')) return const Color(0xFF795548);
  if (l.contains('inşaat') || l.contains('tadilat')) return const Color(0xFFBF360C);
  return const Color(0xFF546E7A);
}

IconData _catIco(String? c) {
  final l = (c ?? '').toLowerCase();
  if (l.contains('tesisat') || l.contains('su')) return Icons.plumbing_rounded;
  if (l.contains('elektrik')) return Icons.bolt_rounded;
  if (l.contains('temiz')) return Icons.cleaning_services_rounded;
  if (l.contains('oto') || l.contains('ara')) return Icons.car_repair_rounded;
  if (l.contains('ders') || l.contains('eğitim')) return Icons.school_rounded;
  if (l.contains('kuaf') || l.contains('berber') || l.contains('güzellik')) return Icons.content_cut_rounded;
  if (l.contains('nakliye') || l.contains('taşı')) return Icons.local_shipping_rounded;
  if (l.contains('sağlık') || l.contains('bakım')) return Icons.medical_services_rounded;
  if (l.contains('organizasyon')) return Icons.celebration_rounded;
  if (l.contains('hayvan')) return Icons.pets_rounded;
  if (l.contains('bahçe') || l.contains('peyzaj')) return Icons.yard_rounded;
  if (l.contains('bilgisayar') || l.contains('teknik')) return Icons.computer_rounded;
  if (l.contains('beyaz')) return Icons.devices_rounded;
  if (l.contains('inşaat') || l.contains('tadilat')) return Icons.construction_rounded;
  return Icons.handyman_rounded;
}
