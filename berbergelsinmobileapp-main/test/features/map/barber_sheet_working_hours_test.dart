import 'dart:ui';
import 'package:berbergelsin/features/barber/data/business_working_hours.dart';
import 'package:berbergelsin/features/map/widgets/barber_sheet/barber_sheet_working_hours.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<BusinessWorkingDay> week({
    int openDay = DateTime.monday,
    bool allOpen = false,
    bool allClosed = false,
  }) {
    return [
      for (var day = DateTime.monday; day <= DateTime.sunday; day++)
        BusinessWorkingDay(
          day: day,
          open: day == openDay ? '09:00' : '10:00',
          close: day == openDay ? '20:00' : '18:00',
          closed: allClosed || (!allOpen && day != openDay),
        ),
    ];
  }

  Future<void> pumpSection(
    WidgetTester tester, {
    List<BusinessWorkingDay>? workingDays,
    DateTime? now,
    double width = 390,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: BarberWorkingHoursSection(
                key: ObjectKey(workingDays),
                workingDays: workingDays ?? week(),
                nowProvider: () => now ?? DateTime(2026, 7, 13, 12),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Barber working hours today summary', () {
    testWidgets('open local weekday shows hours and hides weekly rows', (
      tester,
    ) async {
      await pumpSection(tester);

      expect(find.text('Bugün Açık'), findsOneWidget);
      expect(find.text('09:00–20:00'), findsOneWidget);
      expect(find.text('Pazartesi'), findsNothing);
      expect(find.byKey(const ValueKey('weekly-working-hours')), findsNothing);
      expect(
        find.bySemanticsLabel(
          'Çalışma saatleri, bugün açık, 09:00 ile 20:00 arası, haftalık saatleri göster',
        ),
        findsOneWidget,
      );
    });

    testWidgets('closed local weekday does not show a fake time', (
      tester,
    ) async {
      await pumpSection(tester, now: DateTime(2026, 7, 14, 12));

      expect(find.text('Bugün Kapalı'), findsOneWidget);
      expect(find.text('09:00–20:00'), findsNothing);
      expect(
        find.bySemanticsLabel(
          'Çalışma saatleri, bugün kapalı, haftalık saatleri göster',
        ),
        findsOneWidget,
      );
    });

    testWidgets('missing today is reported as unspecified', (tester) async {
      await pumpSection(
        tester,
        workingDays: [
          const BusinessWorkingDay(
            day: DateTime.monday,
            open: '09:00',
            close: '20:00',
            closed: false,
          ),
        ],
        now: DateTime(2026, 7, 14),
      );

      expect(find.text('Bugün Belirtilmemiş'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('working-hours-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Belirtilmemiş'), findsNWidgets(6));
    });

    testWidgets('empty data has no toggle or fabricated today state', (
      tester,
    ) async {
      await pumpSection(tester, workingDays: const []);

      expect(
        find.text('Çalışma saatleri henüz paylaşılmamış.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('working-hours-toggle')), findsNothing);
      expect(find.textContaining('Bugün'), findsNothing);
    });

    testWidgets('open day with missing time is safe', (tester) async {
      await pumpSection(
        tester,
        workingDays: const [
          BusinessWorkingDay(
            day: DateTime.monday,
            open: '',
            close: '',
            closed: false,
          ),
        ],
      );

      expect(find.text('Bugün Açık'), findsOneWidget);
      expect(find.text('Belirtilmemiş'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Barber working hours expansion', () {
    testWidgets('one control reveals seven ordered days and hides them again', (
      tester,
    ) async {
      await pumpSection(tester);
      final toggle = find.byKey(const ValueKey('working-hours-toggle'));

      expect(find.text('Haftalık saatleri göster'), findsOneWidget);
      expect(find.text('Pazartesi'), findsNothing);

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(find.text('Haftalık saatleri gizle'), findsOneWidget);
      for (final day in const [
        'Pazartesi',
        'Salı',
        'Çarşamba',
        'Perşembe',
        'Cuma',
        'Cumartesi',
        'Pazar',
      ]) {
        expect(find.text(day), findsOneWidget);
      }
      expect(
        tester.getTopLeft(find.text('Pazartesi')).dy,
        lessThan(tester.getTopLeft(find.text('Pazar')).dy),
      );
      expect(
        find.bySemanticsLabel('Pazartesi, bugün, 09:00–20:00'),
        findsOneWidget,
      );

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('Pazartesi'), findsNothing);
      expect(find.text('Haftalık saatleri göster'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('toggle semantics exposes collapsed and expanded state', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpSection(tester);
      final toggle = find.bySemanticsLabel(
        'Çalışma saatleri, bugün açık, 09:00 ile 20:00 arası, haftalık saatleri göster',
      );

      expect(
        tester.getSemantics(toggle).flagsCollection.isExpanded,
        Tristate.isFalse,
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      final expanded = find.bySemanticsLabel(
        'Çalışma saatleri, bugün açık, 09:00 ile 20:00 arası, haftalık saatleri gizle',
      );
      expect(
        tester.getSemantics(expanded).flagsCollection.isExpanded,
        Tristate.isTrue,
      );
      semantics.dispose();
    });

    testWidgets('all closed and all open weeks render safely', (tester) async {
      await pumpSection(tester, workingDays: week(allClosed: true));
      expect(find.text('Bugün Kapalı'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('working-hours-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Kapalı'), findsNWidgets(7));

      await pumpSection(tester, workingDays: week(allOpen: true));
      expect(find.text('Bugün Açık'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('working-hours-toggle')));
      await tester.pumpAndSettle();
      expect(find.textContaining('–'), findsNWidgets(8));
      expect(tester.takeException(), isNull);
    });
  });

  group('Barber working hours responsive', () {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      testWidgets(
        '${width.toInt()} px expanded week is safe at 1.3 text scale',
        (tester) async {
          await pumpSection(
            tester,
            width: width,
            textScale: 1.3,
            workingDays: week(allOpen: true),
          );
          await tester.tap(find.byKey(const ValueKey('working-hours-toggle')));
          await tester.pumpAndSettle();

          expect(find.text('Çarşamba'), findsOneWidget);
          expect(find.text('Haftalık saatleri gizle'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
