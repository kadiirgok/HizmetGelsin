import 'package:berbergelsin/customer_smoke/customer_smoke_app.dart';
import 'package:berbergelsin/customer_smoke/customer_smoke_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('all isolated customer UI smoke steps are reachable', (
    tester,
  ) async {
    final dependencies = CustomerSmokeDependencies.isolated();
    await tester.pumpWidget(CustomerSmokeApp(dependencies: dependencies));
    await tester.pumpAndSettle();

    for (var index = 0; index < CustomerSmokeStep.values.length; index++) {
      final step = CustomerSmokeStep.values[index];
      expect(find.byKey(ValueKey('smoke-step-${step.name}')), findsOneWidget);
      expect(find.text(step.title), findsWidgets);
      expect(tester.takeException(), isNull);

      if (index < CustomerSmokeStep.values.length - 1) {
        await tester.tap(find.byKey(const Key('smoke-next')));
        await tester.pumpAndSettle();
      }
    }

    expect(find.text('Güvenli müşteri UI turu tamamlandı'), findsOneWidget);
    expect(dependencies.repository.networkAttemptCount, 0);
    expect(dependencies.repository.signalRAttemptCount, 0);
    expect(dependencies.repository.pushRegistrationAttemptCount, 0);
  });

  testWidgets('saved/manual address, marker and back controls mutate locally', (
    tester,
  ) async {
    final dependencies = CustomerSmokeDependencies.isolated();
    await tester.pumpWidget(CustomerSmokeApp(dependencies: dependencies));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('smoke-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('İş'));
    await tester.pump();
    expect(dependencies.repository.selectedAddressId, 'smoke-address-work');

    await tester.tap(find.byKey(const Key('smoke-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('use-manual-address')));
    await tester.pump();
    expect(dependencies.repository.manualAddress, isNotEmpty);

    for (var index = 0; index < 4; index++) {
      await tester.tap(find.byKey(const Key('smoke-next')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('offline-smoke-map')), findsOneWidget);
    await tester.tap(find.byKey(const Key('smoke-map-marker')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Fixture marker seçildi'), findsOneWidget);

    await tester.tap(find.byKey(const Key('smoke-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('smoke-step-discovery')), findsOneWidget);
    expect(dependencies.repository.networkAttemptCount, 0);
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets(
      'customersmoke is responsive at ${width.toInt()} and 1.3x text',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: CustomerSmokeApp(
              dependencies: CustomerSmokeDependencies.isolated(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        for (
          var index = 0;
          index < CustomerSmokeStep.values.length - 1;
          index++
        ) {
          await tester.tap(find.byKey(const Key('smoke-next')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets('critical accessibility labels are exposed', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      CustomerSmokeApp(dependencies: CustomerSmokeDependencies.isolated()),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(RegExp('İzole müşteri smoke modu')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('smoke-next')));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        RegExp('Ev, Beşiktaş, İstanbul, varsayılan adres, seçili'),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
