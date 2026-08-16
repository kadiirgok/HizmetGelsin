import 'package:berbergelsin/core/widgets/osm_attribution.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget testApp({required OsmLinkLauncher launcher, double width = 320}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 640),
          textScaler: const TextScaler.linear(1.3),
        ),
        child: Scaffold(
          body: Stack(children: [OsmAttribution(launcher: launcher)]),
        ),
      ),
    );
  }

  testWidgets('shows exact OSM attribution with link semantics', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(launcher: (_) async => true));
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    final semantics = tester
        .widgetList<Semantics>(
          find.descendant(
            of: find.byType(OsmAttribution),
            matching: find.byType(Semantics),
          ),
        )
        .singleWhere((widget) => widget.properties.label != null);
    expect(
      semantics.properties.label,
      'OpenStreetMap katkıda bulunanlar telif hakkı bağlantısı',
    );
    expect(semantics.properties.link, isTrue);
    expect(semantics.properties.button, isTrue);
  });

  testWidgets('tap launches official copyright URL', (tester) async {
    Uri? launched;
    await tester.pumpWidget(
      testApp(
        launcher: (uri) async {
          launched = uri;
          return true;
        },
      ),
    );
    await tester.tap(find.byKey(const Key('osm-attribution-link')));
    await tester.pump();
    expect(launched, Uri.parse(osmCopyrightUrl));
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets('does not overflow at ${width.toInt()}px and 1.3 text scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(width: width, launcher: (_) async => true),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    });
  }
}
