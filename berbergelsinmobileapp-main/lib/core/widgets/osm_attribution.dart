import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const osmCopyrightUrl = 'https://www.openstreetmap.org/copyright';

typedef OsmLinkLauncher = Future<bool> Function(Uri uri);

class OsmAttribution extends StatelessWidget {
  const OsmAttribution({super.key, this.launcher = _launchOsmCopyright});

  final OsmLinkLauncher launcher;

  static Future<bool> _launchOsmCopyright(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.all(6),
      child: Align(
        alignment: Alignment.topLeft,
        child: Semantics(
          button: true,
          link: true,
          label: 'OpenStreetMap katkıda bulunanlar telif hakkı bağlantısı',
          child: Material(
            color: Colors.black.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(5),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const Key('osm-attribution-link'),
              onTap: () => launcher(Uri.parse(osmCopyrightUrl)),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                child: Text(
                  '© OpenStreetMap contributors',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white,
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
