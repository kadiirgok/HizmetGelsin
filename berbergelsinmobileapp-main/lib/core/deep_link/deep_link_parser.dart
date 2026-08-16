import '../config.dart';
import 'app_deep_link.dart';

class DeepLinkParser {
  DeepLinkParser({List<String>? trustedHosts})
    : trustedHosts = (trustedHosts ?? AppConfig.deepLinkHosts)
          .map((host) => host.toLowerCase())
          .toSet();

  static const maxUriLength = 2048;
  static final _id = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static const _allowedQueryKeys = {'ref', 'notificationId'};
  final Set<String> trustedHosts;

  AppDeepLink parse(String raw, {required DeepLinkSource source}) {
    final fallback = Uri(path: '/');
    if (raw.isEmpty || raw.length > maxUriLength || raw.contains('\\')) {
      return AppDeepLink(
        type: AppDeepLinkType.unknown,
        originalUri: Uri.tryParse(raw) ?? fallback,
        source: source,
      );
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.hasFragment || uri.userInfo.isNotEmpty) {
      return _unknown(uri ?? fallback, source);
    }
    if (uri.hasScheme) {
      if (uri.scheme.toLowerCase() != 'https' ||
          (uri.hasPort && uri.port != 443) ||
          !trustedHosts.contains(uri.host.toLowerCase())) {
        return _unknown(uri, source);
      }
    } else if (!raw.startsWith('/') || uri.hasAuthority) {
      return _unknown(uri, source);
    }
    if (uri.queryParameters.keys.any(
          (key) => !_allowedQueryKeys.contains(key),
        ) ||
        uri.queryParametersAll.values.any((values) => values.length != 1)) {
      return _unknown(uri, source);
    }
    final segments = uri.pathSegments;
    if (segments.any((part) => part == '.' || part == '..' || part.isEmpty)) {
      return _unknown(uri, source);
    }
    if (segments.length == 1) {
      final type = switch (segments.single) {
        'bildirimler' => AppDeepLinkType.notifications,
        'favoriler' || 'favorilerim' => AppDeepLinkType.favorites,
        'yorumlarim' => AppDeepLinkType.ratings,
        'adreslerim' => AppDeepLinkType.addresses,
        _ => AppDeepLinkType.unknown,
      };
      return AppDeepLink(type: type, originalUri: uri, source: source);
    }
    if (segments.length != 2 || !_id.hasMatch(segments[1])) {
      return _unknown(uri, source);
    }
    final type = switch (segments[0]) {
      'isletme' => AppDeepLinkType.businessDetail,
      'talepler' || 'talep' => AppDeepLinkType.requestDetail,
      'teklifler' => AppDeepLinkType.offerDetail,
      'randevular' => AppDeepLinkType.appointmentDetail,
      _ => AppDeepLinkType.unknown,
    };
    return AppDeepLink(
      type: type,
      entityId: type == AppDeepLinkType.unknown ? null : segments[1],
      originalUri: uri,
      source: source,
    );
  }

  AppDeepLink _unknown(Uri uri, DeepLinkSource source) => AppDeepLink(
    type: AppDeepLinkType.unknown,
    originalUri: uri,
    source: source,
  );
}
