import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

typedef BarberImageSizeResolver = Future<Size?> Function(String url);

class BarberImageMetadataCache {
  BarberImageMetadataCache._();

  static final Map<String, Future<Size?>> _sizes = {};

  static Future<Size?> resolve(BuildContext context, String url) {
    final key = _normalize(url);
    if (key.isEmpty) return Future<Size?>.value();
    if (_sizes.length >= 32 && !_sizes.containsKey(key)) {
      _sizes.remove(_sizes.keys.first);
    }
    return _sizes.putIfAbsent(key, () => _read(context, url));
  }

  static Future<Size?> _read(BuildContext context, String url) {
    final completer = Completer<Size?>();
    final stream = NetworkImage(
      url,
    ).resolve(createLocalImageConfiguration(context));
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) {
          completer.complete(
            Size(info.image.width.toDouble(), info.image.height.toDouble()),
          );
        }
      },
      onError: (_, __) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  /// Conservatively detects black letterbox bands baked into a source image.
  /// This is consumed only by the hero; gallery eligibility is unchanged.
  static Future<bool> hasHorizontalBlackBars(
    BuildContext context,
    String url,
  ) async {
    final image = await _readImage(context, url);
    if (image == null || image.width < 8 || image.height < 8) return true;
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) return true;
    final bandDepth = (image.height * 0.1).round().clamp(1, 40);
    final stepX = (image.width / 48).ceil().clamp(1, image.width);

    ({double darkShare, double luminance}) sample(int startY, int endY) {
      var count = 0;
      var dark = 0;
      var luminance = 0.0;
      final stepY = ((endY - startY) / 4).ceil().clamp(1, image.height);
      for (var y = startY; y < endY; y += stepY) {
        for (var x = 0; x < image.width; x += stepX) {
          final offset = (y * image.width + x) * 4;
          final value =
              0.2126 * bytes.getUint8(offset) +
              0.7152 * bytes.getUint8(offset + 1) +
              0.0722 * bytes.getUint8(offset + 2);
          if (value < 6) dark++;
          luminance += value;
          count++;
        }
      }
      return (
        darkShare: count == 0 ? 0 : dark / count,
        luminance: count == 0 ? 0 : luminance / count,
      );
    }

    final top = sample(0, bandDepth);
    final bottom = sample(image.height - bandDepth, image.height);
    final center = sample(image.height ~/ 2, image.height ~/ 2 + 1);
    return top.darkShare >= 0.985 &&
        bottom.darkShare >= 0.985 &&
        top.luminance <= 5 &&
        bottom.luminance <= 5 &&
        center.luminance >= 32;
  }

  static Future<ui.Image?> _readImage(BuildContext context, String url) {
    final completer = Completer<ui.Image?>();
    final stream = NetworkImage(
      url,
    ).resolve(createLocalImageConfiguration(context));
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(info.image);
      },
      onError: (_, __) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  static String _normalize(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return trimmed.toLowerCase();
    return uri
        .replace(
          scheme: uri.scheme.toLowerCase(),
          host: uri.host.toLowerCase(),
          fragment: '',
        )
        .toString();
  }
}
