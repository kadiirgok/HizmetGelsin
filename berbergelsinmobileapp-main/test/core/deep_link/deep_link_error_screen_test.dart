import 'package:berbergelsin/core/deep_link/deep_link_error_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final entry in {
    'invalid': 'Geçersiz bağlantı',
    'unauthorized': 'Yetkisiz erişim',
    'notFound': 'İçerik bulunamadı',
  }.entries) {
    testWidgets('${entry.key} güvenli mesajı gösterir', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: DeepLinkErrorScreen(reason: entry.key)),
      );
      expect(find.text(entry.value), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ağ hatası retry ve uzun Türkçe metin 320px/1.3 ölçekte taşmaz', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    var retries = 0;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: MaterialApp(
          home: DeepLinkErrorScreen(
            reason: 'network',
            onRetry: () => retries++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Tekrar Dene'));
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });
}
