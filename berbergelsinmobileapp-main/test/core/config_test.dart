import 'package:berbergelsin/core/config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'varsayılan debug/flavor base URL fiziksel cihazda erişilebilir HTTPS hostudur',
    () {
      expect(AppConfig.baseUrl, 'https://api.tivigo.online');
      expect(Uri.parse(AppConfig.baseUrl).scheme, 'https');
      expect(AppConfig.baseUrl, isNot(contains('10.0.2.2')));
    },
  );
}
