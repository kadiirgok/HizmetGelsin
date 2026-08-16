import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';

import '../signalr/signalr_service.dart';
import 'app_deep_link.dart';
import 'deep_link_coordinator.dart';

class DeepLinkIngress extends StatefulWidget {
  const DeepLinkIngress({
    super.key,
    required this.coordinator,
    required this.child,
  });
  final DeepLinkCoordinator coordinator;
  final Widget child;

  @override
  State<DeepLinkIngress> createState() => _DeepLinkIngressState();
}

class _DeepLinkIngressState extends State<DeepLinkIngress> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _links;
  void Function()? _signalRUnsubscribe;

  @override
  void initState() {
    super.initState();
    _listen();
    _signalRUnsubscribe = SignalRService.instance.on('NotificationCreated', (
      args,
    ) {
      final payload = args?.firstOrNull;
      final route = payload is Map ? payload['route'] : null;
      if (route is String) {
        unawaited(
          widget.coordinator.open(route, source: DeepLinkSource.signalR),
        );
      }
    });
  }

  Future<void> _listen() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (!mounted) return;
      if (initial != null) {
        await widget.coordinator.open(
          initial.toString(),
          source: DeepLinkSource.coldStart,
        );
      }
      _links = _appLinks.uriLinkStream.listen((uri) {
        if (mounted) {
          unawaited(
            widget.coordinator.open(
              uri.toString(),
              source: DeepLinkSource.warmStart,
            ),
          );
        }
      });
    } catch (_) {
      // Platform link kanalı kullanılamıyorsa normal uygulama akışı sürer.
    }
  }

  @override
  void dispose() {
    _links?.cancel();
    _signalRUnsubscribe?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
