import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/barbers_repo.dart';
import 'barber_sheet_image_metadata.dart';

const barberGalleryCardHeight = 140.0;

BoxFit barberGalleryFitForRatio(double? ratio) =>
    ratio != null && ratio.isFinite && ratio >= 1.15 && ratio <= 2.4
    ? BoxFit.cover
    : BoxFit.contain;

double barberGalleryWidthForRatio(double? ratio) =>
    ratio == null || !ratio.isFinite || ratio <= 0
    ? 160
    : (barberGalleryCardHeight * ratio).clamp(120, 220).toDouble();

class BarberPhotoGallery extends StatefulWidget {
  const BarberPhotoGallery({
    super.key,
    required this.photos,
    required this.coverPhotoUrl,
    required this.businessName,
    required this.absoluteUrlBuilder,
    this.imageSizeResolver,
  });
  final List<BusinessPhoto> photos;
  final String? coverPhotoUrl;
  final String businessName;
  final String Function(String path) absoluteUrlBuilder;
  final BarberImageSizeResolver? imageSizeResolver;
  @override
  State<BarberPhotoGallery> createState() => _BarberPhotoGalleryState();
}

class _BarberPhotoGalleryState extends State<BarberPhotoGallery> {
  Map<String, Size?> _sizes = const {};
  String? _key;
  int _generation = 0;

  List<_GalleryPhoto> get _photos {
    final cover = widget.coverPhotoUrl == null
        ? null
        : _normalize(widget.coverPhotoUrl!);
    final seen = <String>{};
    final result = <_GalleryPhoto>[];
    for (final photo in widget.photos) {
      final url = widget.absoluteUrlBuilder(photo.url);
      final normalized = _normalize(url);
      if (normalized.isEmpty || normalized == cover || !seen.add(normalized)) {
        continue;
      }
      result.add(_GalleryPhoto(photo, url));
    }
    return result;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveIfNeeded();
  }

  @override
  void didUpdateWidget(covariant BarberPhotoGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolveIfNeeded();
  }

  void _resolveIfNeeded() {
    final photos = _photos;
    final key = photos.map((e) => _normalize(e.url)).join('\u0000');
    if (_key == key) return;
    _key = key;
    _sizes = const {};
    unawaited(_resolve(photos, ++_generation));
  }

  Future<void> _resolve(List<_GalleryPhoto> photos, int generation) async {
    final sizes = <String, Size?>{};
    for (final photo in photos) {
      sizes[photo.url] =
          await (widget.imageSizeResolver?.call(photo.url) ??
              BarberImageMetadataCache.resolve(context, photo.url));
      if (!mounted || generation != _generation) return;
    }
    if (mounted && generation == _generation) {
      setState(() => _sizes = Map.unmodifiable(sizes));
    }
  }

  String _normalize(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      return trimmed.replaceAll(RegExp(r'/+$'), '').toLowerCase();
    }
    return uri
        .replace(
          scheme: uri.scheme.toLowerCase(),
          host: uri.host.toLowerCase(),
          path: uri.path.replaceAll(RegExp(r'/+$'), ''),
          fragment: '',
        )
        .toString();
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos;
    if (photos.isEmpty) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label:
          'Fotoğraf galerisi, yatay kaydırılabilir, ${photos.length} fotoğraf',
      child: Column(
        key: const ValueKey('barber-photo-gallery'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Fotoğraflar',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${photos.length} fotoğraf',
                key: const ValueKey('barber-gallery-count'),
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: barberGalleryCardHeight,
            child: ListView.separated(
              key: const ValueKey('barber-gallery-list'),
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 9),
              itemBuilder: (context, index) {
                final item = photos[index];
                final size = _sizes[item.url];
                final ratio = size == null || size.height <= 0
                    ? null
                    : size.width / size.height;
                return _GalleryCard(
                  key: ValueKey('barber-gallery-photo-${item.photo.id}'),
                  item: item,
                  index: index,
                  total: photos.length,
                  businessName: widget.businessName,
                  width: barberGalleryWidthForRatio(ratio),
                  fit: barberGalleryFitForRatio(ratio),
                  onTap: () => showDialog<void>(
                    context: context,
                    barrierColor: Colors.black,
                    builder: (_) => _GalleryViewer(
                      photos: photos,
                      initialIndex: index,
                      businessName: widget.businessName,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 22),
        ],
      ),
    );
  }
}

class _GalleryCard extends StatelessWidget {
  const _GalleryCard({
    super.key,
    required this.item,
    required this.index,
    required this.total,
    required this.businessName,
    required this.width,
    required this.fit,
    required this.onTap,
  });
  final _GalleryPhoto item;
  final int index, total;
  final String businessName;
  final double width;
  final BoxFit fit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final neutral = Theme.of(context).colorScheme.surfaceContainerHighest;
    final caption = item.photo.caption?.trim();
    final label =
        '$businessName işletmesi fotoğrafı, ${index + 1} / $total. Büyütmek için dokunun.'
        '${caption?.isNotEmpty == true ? ' $caption' : ''}';
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: neutral,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: width,
              height: barberGalleryCardHeight,
              child: Padding(
                padding: fit == BoxFit.contain
                    ? const EdgeInsets.all(6)
                    : EdgeInsets.zero,
                child: Image.network(
                  item.url,
                  fit: fit,
                  excludeFromSemantics: true,
                  cacheWidth: (width * ratio).round().clamp(120, 880),
                  cacheHeight: (barberGalleryCardHeight * ratio).round().clamp(
                    140,
                    560,
                  ),
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                  frameBuilder: (context, child, frame, sync) {
                    if (sync || frame != null) return child;
                    final isTest = Platform.environment.containsKey(
                      'FLUTTER_TEST',
                    );
                    return ColoredBox(
                      color: neutral,
                      child: Center(
                        child: SizedBox.square(
                          dimension: 20,
                          child: isTest
                              ? const SizedBox()
                              : const CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => ColoredBox(
                    key: ValueKey('barber-gallery-error-$index'),
                    color: neutral,
                    child: const Center(
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryViewer extends StatefulWidget {
  const _GalleryViewer({
    required this.photos,
    required this.initialIndex,
    required this.businessName,
  });
  final List<_GalleryPhoto> photos;
  final int initialIndex;
  final String businessName;
  @override
  State<_GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<_GalleryViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    backgroundColor: Colors.black,
    child: SafeArea(
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.photos.length,
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (context, index) => Semantics(
              image: true,
              label:
                  '${widget.businessName} işletmesi fotoğrafı, ${index + 1} / ${widget.photos.length}',
              child: ExcludeSemantics(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Image.network(
                      widget.photos[index].url,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.image_not_supported_outlined,
                        size: 48,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Kapat',
              color: Colors.white,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
          Positioned(
            left: 16,
            top: 14,
            child: Semantics(
              liveRegion: true,
              child: Text(
                'Fotoğraf ${_index + 1} / ${widget.photos.length}',
                key: const ValueKey('barber-gallery-viewer-position'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _GalleryPhoto {
  const _GalleryPhoto(this.photo, this.url);
  final BusinessPhoto photo;
  final String url;
}
