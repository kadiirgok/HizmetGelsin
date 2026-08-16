import 'dart:async';

import 'package:berbergelsin/core/api/api_client.dart';
import 'package:berbergelsin/features/barber/controllers/address_search_controller.dart';
import 'package:berbergelsin/features/barber/data/address_search_repository.dart';
import 'package:berbergelsin/features/barber/widgets/profile/address_search_field.dart';
import 'package:berbergelsin/features/barber/widgets/profile/resolved_address_form.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loading ve sonuç listesi görünür, seçim alanları doldurur', (
    tester,
  ) async {
    final completer = _Repo();
    final controller = AddressSearchController(
      repository: completer,
      debounce: Duration.zero,
      tokenFactory: () => 'session',
    );
    ResolvedAddress? selected;
    await tester.pumpWidget(
      _app(
        AddressSearchField(
          controller: controller,
          onSelected: (value) => selected = value,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('address-search-field')),
      'Bağdat',
    );
    await tester.pump();
    expect(find.byKey(const Key('address-loading')), findsOneWidget);
    completer.completeSuggestions();
    await tester.pump();
    expect(find.byKey(const Key('address-suggestions')), findsOneWidget);
    await tester.tap(find.text('Bağdat Caddesi'));
    await tester.pump();
    completer.completeDetails();
    await tester.pump();
    expect(selected?.province, 'İstanbul');
    expect(selected?.neighborhood, isNull);
    expect(find.byKey(const Key('address-selected')), findsOneWidget);
    controller.dispose();
  });

  testWidgets(
    'empty, rate limit ve provider unavailable ham hata göstermeden görünür',
    (tester) async {
      for (final entry in [
        (const <AddressSuggestion>[], null, const Key('address-empty')),
        (
          null,
          ApiException('Google secret', statusCode: 429),
          const Key('address-rate-limit'),
        ),
        (
          null,
          ApiException('provider raw', statusCode: 503),
          const Key('address-provider-unavailable'),
        ),
      ]) {
        final repo = _ImmediateRepo(result: entry.$1, error: entry.$2);
        final controller = AddressSearchController(
          repository: repo,
          debounce: Duration.zero,
        );
        await tester.pumpWidget(
          _app(
            AddressSearchField(
              key: ValueKey(entry.$3),
              controller: controller,
              onSelected: (_) {},
            ),
          ),
        );
        await tester.enterText(
          find.byKey(const Key('address-search-field')),
          'adres',
        );
        await tester.pump();
        await tester.pump();
        expect(find.byKey(entry.$3), findsOneWidget);
        expect(find.textContaining('Google'), findsNothing);
        expect(find.textContaining('raw'), findsNothing);
        controller.dispose();
      }
    },
  );

  testWidgets(
    'manuel form 320-430 px ve textScale 1.3 altında taşmaz, eksik mahalle düzenlenebilir',
    (tester) async {
      for (final width in [320.0, 360.0, 390.0, 430.0]) {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        final controllers = List.generate(6, (_) => TextEditingController());
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: const TextScaler.linear(1.3),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: ResolvedAddressForm(
                    province: controllers[0],
                    district: controllers[1],
                    neighborhood: controllers[2],
                    street: controllers[3],
                    streetNumber: controllers[4],
                    addressLine: controllers[5],
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.enterText(
          find.widgetWithText(TextField, 'Mahalle'),
          'Caferağa',
        );
        expect(controllers[2].text, 'Caferağa');
        for (final c in controllers) {
          c.dispose();
        }
      }
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    },
  );
}

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: child,
    ),
  ),
);

class _Repo implements AddressSearchRepository {
  final suggestionsCompleter = Completer<List<AddressSuggestion>>();
  final detailsCompleter = Completer<ResolvedAddress>();
  void completeSuggestions() => suggestionsCompleter.complete(const [
    AddressSuggestion(
      placeId: 'p1',
      primaryText: 'Bağdat Caddesi',
      secondaryText: 'Kadıköy/İstanbul',
      displayText: 'Bağdat Caddesi, Kadıköy/İstanbul',
    ),
  ]);
  void completeDetails() => detailsCompleter.complete(
    const ResolvedAddress(
      placeId: 'p1',
      formattedAddress: 'Uzun Türkçe adres, Kadıköy/İstanbul',
      province: 'İstanbul',
      district: 'Kadıköy',
      latitude: 41,
      longitude: 29,
      countryCode: 'TR',
    ),
  );
  @override
  Future<List<AddressSuggestion>> suggestions(
    String query,
    String sessionToken,
    CancelToken cancelToken,
  ) => suggestionsCompleter.future;
  @override
  Future<ResolvedAddress> details(
    String placeId,
    String sessionToken,
    CancelToken cancelToken,
  ) => detailsCompleter.future;
}

class _ImmediateRepo implements AddressSearchRepository {
  _ImmediateRepo({this.result, this.error});
  final List<AddressSuggestion>? result;
  final Object? error;
  @override
  Future<List<AddressSuggestion>> suggestions(
    String query,
    String sessionToken,
    CancelToken cancelToken,
  ) async {
    if (error != null) throw error!;
    return result ?? const [];
  }

  @override
  Future<ResolvedAddress> details(
    String placeId,
    String sessionToken,
    CancelToken cancelToken,
  ) => throw UnimplementedError();
}
