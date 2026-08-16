enum AppDeepLinkType {
  businessDetail,
  requestDetail,
  offerDetail,
  appointmentDetail,
  notifications,
  favorites,
  ratings,
  addresses,
  unknown,
}

enum DeepLinkSource { notification, signalR, coldStart, warmStart, internal }

class AppDeepLink {
  const AppDeepLink({
    required this.type,
    required this.originalUri,
    required this.source,
    this.entityId,
  });

  final AppDeepLinkType type;
  final String? entityId;
  final Uri originalUri;
  final DeepLinkSource source;

  bool get isKnown => type != AppDeepLinkType.unknown;
}

enum DeepLinkRejection { invalid, unsupported, unauthorized, notFound, network }
