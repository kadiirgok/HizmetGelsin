import 'package:berbergelsin/core/data/selection_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServiceSelectionOptions.coordinateFor', () {
    test(
      'il seçimi koordinatı güncelliyor (il seviyesinde koordinat buluyor)',
      () {
        final coord = ServiceSelectionOptions.coordinateFor(
          'İstanbul',
          null,
          null,
        );
        expect(coord, isNotNull);
        expect(coord!.lat, 40.9877);
        expect(coord.lng, 29.0277);
      },
    );

    test(
      'ilçe seçimi koordinatı güncelliyor (il ve ilçe seviyesinde koordinat buluyor)',
      () {
        final coord = ServiceSelectionOptions.coordinateFor(
          'İstanbul',
          'Beşiktaş',
          null,
        );
        expect(coord, isNotNull);
        expect(coord!.lat, 41.0818);
        expect(coord.lng, 29.0124);
      },
    );

    test(
      'mahalle seçimi koordinatı güncelliyor (il, ilçe ve mahalle seviyesinde koordinat buluyor)',
      () {
        final coord = ServiceSelectionOptions.coordinateFor(
          'İstanbul',
          'Beşiktaş',
          'Ortaköy',
        );
        expect(coord, isNotNull);
        expect(coord!.lat, 41.0474);
        expect(coord.lng, 29.0256);
      },
    );

    test(
      'helper null dönerse eski koordinat korunuyor (gecersiz bolge null doner)',
      () {
        final coord = ServiceSelectionOptions.coordinateFor(
          'Geçersizİl',
          null,
          null,
        );
        expect(coord, isNull);
      },
    );
  });
}
