import 'package:berbergelsin/core/deep_link/app_deep_link.dart';
import 'package:berbergelsin/core/deep_link/deep_link_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = '11111111-1111-1111-1111-111111111111';
  late DeepLinkParser parser;

  setUp(() => parser = DeepLinkParser(trustedHosts: const ['links.test']));

  AppDeepLink parse(String value) =>
      parser.parse(value, source: DeepLinkSource.notification);

  test('allowlistteki entity linklerini typed modele çevirir', () {
    expect(
      parse('https://links.test/isletme/$id').type,
      AppDeepLinkType.businessDetail,
    );
    expect(
      parse('https://links.test/talepler/$id').type,
      AppDeepLinkType.requestDetail,
    );
    expect(
      parse('https://links.test/teklifler/$id').type,
      AppDeepLinkType.offerDetail,
    );
    expect(
      parse('https://links.test/randevular/$id').type,
      AppDeepLinkType.appointmentDetail,
    );
    expect(parse('/talepler/$id').entityId, id);
  });

  test('bağımsız route ve izinli query kabul edilir', () {
    expect(parse('/bildirimler').type, AppDeepLinkType.notifications);
    expect(parse('/favoriler').type, AppDeepLinkType.favorites);
    expect(parse('/yorumlarim?ref=push').type, AppDeepLinkType.ratings);
    expect(
      parse('/adreslerim?notificationId=n1').type,
      AppDeepLinkType.addresses,
    );
  });

  test('bilinmeyen route, domain, http ve arbitrary scheme reddedilir', () {
    for (final value in [
      '/admin',
      'https://evil.test/isletme/$id',
      'http://links.test/isletme/$id',
      'javascript:alert(1)',
      'file:///tmp/x',
      'custom://links.test/isletme/$id',
    ]) {
      expect(parse(value).type, AppDeepLinkType.unknown, reason: value);
    }
  });

  test('traversal, invalid id, unknown query ve uzun URI reddedilir', () {
    for (final value in [
      '/isletme/../admin',
      '/isletme/%2E%2E',
      '/isletme/not-a-guid',
      '/isletme/$id?redirect=https://evil.test',
      '/isletme/$id?ref=a&ref=b',
      '/${'x' * 2049}',
    ]) {
      expect(parse(value).type, AppDeepLinkType.unknown, reason: value);
    }
  });
}
