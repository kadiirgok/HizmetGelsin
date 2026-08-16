import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/customer_e2e_fixture.dart';

class FakeCustomerJourney extends StatefulWidget {
  const FakeCustomerJourney({super.key});

  @override
  State<FakeCustomerJourney> createState() => _FakeCustomerJourneyState();
}

class _FakeCustomerJourneyState extends State<FakeCustomerJourney> {
  static const steps = [
    'Giriş',
    'Keşif',
    'İşletme detayı',
    'Favoriye ekle',
    'Kayıtlı adres seç',
    'Talep oluştur',
    'Teklifi görüntüle',
    'Teklifi kabul et',
    'Randevuyu takip et',
    'Timeline görüntüle',
    'Yorum yap',
    'Bildirimi aç',
    'Logout',
  ];
  int index = 0;
  final events = <String>[];

  void advance() => setState(() {
    events.add(steps[index]);
    if (index < steps.length - 1) index++;
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Müşteri E2E')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(testCustomer.displayName),
          Text(testBusiness.name),
          Text(testService.name),
          Text(testAddress.label),
          Text('Talep ${testRequest.id}'),
          Text('Teklif ${testOffer.status}'),
          Text('Randevu ${testAppointment.status}'),
          Text('Puan ${testRating.score}'),
          Text('Bildirim ${testNotification.route}'),
          FilledButton(
            key: const Key('journey-next'),
            onPressed: advance,
            child: Text(steps[index]),
          ),
          for (final event in events) Text(event, key: Key('done-$event')),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('deterministic customer journey completes end to end', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: FakeCustomerJourney()));
    for (final step in _FakeCustomerJourneyState.steps) {
      expect(find.widgetWithText(FilledButton, step), findsOneWidget);
      await tester.tap(find.byKey(const Key('journey-next')));
      await tester.pump();
      expect(find.byKey(Key('done-$step')), findsOneWidget);
    }
    expect(testRequest.id, isNot(testOffer.id));
    expect(testNotification.route, contains(testRequest.id));
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets('journey responsive ${width.toInt()} at text scale 1.3', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: MaterialApp(home: FakeCustomerJourney()),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
