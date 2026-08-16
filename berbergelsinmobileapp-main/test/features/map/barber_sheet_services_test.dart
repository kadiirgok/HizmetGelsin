import 'package:berbergelsin/features/map/data/barbers_repo.dart';
import 'package:berbergelsin/features/map/widgets/barber_sheet/barber_sheet_services.dart';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BarberServiceItem service(
    String id, {
    String? name,
    double price = 6000,
    int? duration = 45,
    String? description,
    bool popular = false,
  }) => BarberServiceItem(
    id: id,
    name: name ?? 'Saç Kesimi',
    price: price,
    durationMinutes: duration,
    description: description,
    isPopular: popular,
  );

  Future<void> pumpSection(
    WidgetTester tester, {
    required List<BarberServiceItem> services,
    bool previewOnly = true,
    Set<String> selected = const {},
    void Function(String, bool)? onChanged,
    double width = 390,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: BarberServicesSection(
                services: services,
                previewOnly: previewOnly,
                selectedServiceIds: selected,
                onSelectionChanged: onChanged ?? (_, __) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('BarberServices preview', () {
    testWidgets('shows compact information without selection controls', (
      tester,
    ) async {
      var callbackCount = 0;
      await pumpSection(
        tester,
        services: [service('one', popular: true, description: 'Kısa açıklama')],
        onChanged: (_, __) => callbackCount++,
      );
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(
        find.byKey(const ValueKey('barber-service-selection-indicator')),
        findsNothing,
      );
      expect(find.text('Saç Kesimi'), findsOneWidget);
      expect(find.text('6.000 TL'), findsOneWidget);
      expect(find.text('45 dk'), findsOneWidget);
      expect(find.text('Popüler'), findsOneWidget);
      final info = find.bySemanticsLabel(RegExp('Saç Kesimi.*6\\.000 TL'));
      expect(info, findsOneWidget);
      expect(
        tester.getSemantics(info).flagsCollection.isButton,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('barber-service-one')));
      expect(callbackCount, 0);
    });

    testWidgets('empty, durationless and descriptionless data are safe', (
      tester,
    ) async {
      await pumpSection(tester, services: const []);
      expect(find.text('Henüz hizmet eklenmemiş.'), findsOneWidget);
      await pumpSection(
        tester,
        services: [service('one', duration: null, price: 250)],
      );
      expect(find.text('250 TL'), findsOneWidget);
      expect(find.textContaining('dk'), findsNothing);
    });

    testWidgets('three rows stay compact', (tester) async {
      await pumpSection(
        tester,
        services: [
          service('one'),
          service('two', name: 'Sakal Tıraşı', price: 700),
          service('three', name: 'Cam Temizliği', price: 250),
        ],
      );
      final height = tester
          .getSize(find.byKey(const ValueKey('barber-services-section')))
          .height;
      expect(height, lessThanOrEqualTo(310));
    });

    testWidgets('popular badge does not inflate the service row', (
      tester,
    ) async {
      await pumpSection(
        tester,
        services: [service('popular', popular: true), service('regular')],
      );
      final popularHeight = tester
          .getSize(find.byKey(const ValueKey('barber-service-popular')))
          .height;
      final regularHeight = tester
          .getSize(find.byKey(const ValueKey('barber-service-regular')))
          .height;
      expect((popularHeight - regularHeight).abs(), lessThanOrEqualTo(2));
      expect(tester.takeException(), isNull);
    });
  });

  group('BarberServices customer selection', () {
    testWidgets('one tap emits one toggle and semantics exposes selection', (
      tester,
    ) async {
      var calls = 0;
      String? id;
      bool? value;
      await pumpSection(
        tester,
        previewOnly: false,
        services: [service('one')],
        onChanged: (nextId, nextValue) {
          calls++;
          id = nextId;
          value = nextValue;
        },
      );
      final control = find.byKey(const ValueKey('barber-service-control-one'));
      expect(
        tester.getSemantics(control).flagsCollection.isSelected,
        Tristate.isFalse,
      );
      expect(
        find.byKey(const ValueKey('barber-service-selection-indicator')),
        findsOneWidget,
      );
      await tester.tap(control);
      expect(calls, 1);
      expect(id, 'one');
      expect(value, isTrue);
    });

    testWidgets('multiple selection and removal retain correct ids', (
      tester,
    ) async {
      final selected = <String>{};
      late StateSetter setHarnessState;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              setHarnessState = setState;
              return Scaffold(
                body: BarberServicesSection(
                  services: [service('one'), service('two')],
                  previewOnly: false,
                  selectedServiceIds: selected,
                  onSelectionChanged: (id, value) {
                    setHarnessState(
                      () => value ? selected.add(id) : selected.remove(id),
                    );
                  },
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('barber-service-control-one')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('barber-service-control-two')),
      );
      await tester.pump();
      expect(selected, {'one', 'two'});
      await tester.tap(
        find.byKey(const ValueKey('barber-service-control-one')),
      );
      await tester.pump();
      expect(selected, {'two'});
    });
  });

  group('BarberServices responsive', () {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      testWidgets('${width.toInt()} px and text scale 1.3 do not overflow', (
        tester,
      ) async {
        await pumpSection(
          tester,
          width: width,
          textScale: 1.3,
          previewOnly: false,
          services: [
            service(
              'long',
              name: 'Çok uzun kapsamlı yerinde bakım ve onarım hizmeti',
              price: 6000000.5,
              description:
                  'Bu çok uzun açıklama yalnız tek satırda kontrollü görünmelidir.',
              popular: true,
            ),
          ],
        );
        expect(find.text('6.000.000,5 TL'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
