import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/theme/app_theme.dart';

/// Uygulama içi fotoğraf seçici bottom sheet.
/// Cihazdaki fotoğrafları grid olarak gösterir, seçilen fotoğrafın
/// bytes'ını [PlatformFileResult] ile döner.
class PhotoPickerSheet extends StatefulWidget {
  const PhotoPickerSheet({
    super.key,
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  State<PhotoPickerSheet> createState() => _PhotoPickerSheetState();
}

class _PhotoPickerSheetState extends State<PhotoPickerSheet> {
  List<AssetEntity> _photos = [];
  bool _loading = true;
  String? _error;
  int? _selectedIndex;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    try {
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.isAuth && !perm.hasAccess) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Fotoğraflara erişim izni gerekli.';
          });
        }
        return;
      }
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
      );
      if (albums.isEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Cihazda fotoğraf bulunamadı.';
          });
        }
        return;
      }
      final count = await albums.first.assetCountAsync;
      final assets = await albums.first.getAssetListRange(
        start: 0,
        end: (count > 60 ? 60 : count),
      );
      if (mounted) {
        setState(() {
          _photos = assets;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Fotoğraflar yüklenemedi.';
        });
      }
    }
  }

  Future<void> _selectPhoto(int index) async {
    if (_uploading) return;
    setState(() {
      _selectedIndex = index;
      _uploading = true;
    });
    try {
      final asset = _photos[index];
      final file = await asset.file;
      if (file == null) {
        if (mounted) setState(() => _uploading = false);
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      Navigator.pop(
        context,
        PlatformFileResult(
          name: file.uri.pathSegments.last,
          bytes: bytes,
          size: bytes.length,
          path: file.path,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fotoğraf yüklenemedi.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final height = MediaQuery.of(context).size.height * 0.75;

    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (widget.subtitle != null)
                            Text(
                              widget.subtitle!,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: _buildBody(),
          ),
          // Cancel button
          Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, bottom + 12),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('İptal'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_library_outlined,
                size: 48, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _loadPhotos();
              },
              child: const Text('Tekrar Dene'),
            ),
          ],
        ),
      );
    }
    if (_photos.isEmpty) {
      return const Center(
        child: Text('Fotoğraf bulunamadı.',
            style: TextStyle(color: AppTheme.textSecondary)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: _photos.length,
      itemBuilder: (context, index) {
        final isSelected = _selectedIndex == index;
        return GestureDetector(
          onTap: () => _selectPhoto(index),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _PhotoThumbnail(asset: _photos[index]),
              if (isSelected)
                Container(
                  color: AppTheme.primary.withValues(alpha: 0.3),
                  child: const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PhotoThumbnail extends StatelessWidget {
  const _PhotoThumbnail({required this.asset});
  final AssetEntity asset;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(const ThumbnailSize(200, 200)),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallback(),
          );
        }
        return _fallback();
      },
    );
  }

  Widget _fallback() => Container(
        color: AppTheme.fieldFill,
        child: const Icon(Icons.image_outlined, color: AppTheme.textSecondary),
      );
}

/// FilePickerResult benzeri basit sonuç sınıfı
class PlatformFileResult {
  final String name;
  final Uint8List bytes;
  final int size;
  final String? path;

  const PlatformFileResult({
    required this.name,
    required this.bytes,
    required this.size,
    this.path,
  });

  /// FilePicker'ın PlatformFile'ına uyumlu hale getir
  PlatformFile toPlatformFile() => PlatformFile(
        name: name,
        bytes: bytes,
        size: size,
        path: path,
      );
}

/// FilePicker PlatformFile'ına benzer basit sınıf
class PlatformFile {
  final String name;
  final Uint8List bytes;
  final int size;
  final String? path;

  const PlatformFile({
    required this.name,
    required this.bytes,
    required this.size,
    this.path,
  });
}
