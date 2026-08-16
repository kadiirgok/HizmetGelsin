import 'package:berbergelsin/features/barber/controllers/address_search_controller.dart';
import 'package:berbergelsin/features/barber/data/address_search_repository.dart';
import 'package:berbergelsin/core/api/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const suggestion = AddressSuggestion(
    placeId: 'tr-1',
    primaryText: 'Bağdat Caddesi',
    secondaryText: 'Kadıköy/İstanbul',
    displayText: 'Bağdat Caddesi, Kadıköy/İstanbul',
  );
  const resolved = ResolvedAddress(
    placeId: 'tr-1',
    formattedAddress: 'Caferağa Mah. Bağdat Cad. No: 10, Kadıköy/İstanbul',
    province: 'İstanbul',
    district: 'Kadıköy',
    neighborhood: 'Caferağa',
    street: 'Bağdat Caddesi',
    streetNumber: '10',
    latitude: 40.99,
    longitude: 29.03,
    countryCode: 'TR',
  );

  test(
    '3 karakterden kısa sorguda istek yok ve session token oluşur',
    () async {
      final repo = _FakeRepository();
      final controller = AddressSearchController(
        repository: repo,
        debounce: Duration.zero,
        tokenFactory: () => 'token-1',
      );
      controller.focus();
      controller.queryChanged('ab');
      await Future<void>.delayed(Duration.zero);
      expect(repo.queries, isEmpty);
      expect(controller.sessionToken, 'token-1');
      expect(controller.status, AddressSearchStatus.typing);
      controller.dispose();
    },
  );

  test(
    'debounce sonrası yalnız son sorgu istenir ve eski istek iptal edilir',
    () async {
      final repo = _FakeRepository(delay: const Duration(milliseconds: 30));
      final controller = AddressSearchController(
        repository: repo,
        debounce: const Duration(milliseconds: 5),
        tokenFactory: () => 'token-1',
      );
      controller.queryChanged('Bağ');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      controller.queryChanged('Bağdat');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(repo.queries, ['Bağ', 'Bağdat']);
      expect(repo.tokens, ['token-1', 'token-1']);
      expect(repo.cancelled.first, isTrue);
      expect(controller.suggestions, [suggestion]);
      controller.dispose();
    },
  );

  test(
    'autocomplete ve details aynı tokenı kullanır, seçimden sonra token kapanır',
    () async {
      final repo = _FakeRepository();
      final controller = AddressSearchController(
        repository: repo,
        debounce: Duration.zero,
        tokenFactory: () => 'same-token',
      );
      controller.queryChanged('Bağdat');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final value = await controller.select(suggestion);
      expect(value, resolved);
      expect(repo.tokens, ['same-token', 'same-token']);
      expect(controller.sessionToken, isNull);
      expect(controller.status, AddressSearchStatus.selected);
      controller.dispose();
    },
  );

  test('temizleme sonrası yeni aramada yeni token oluşur', () {
    var index = 0;
    final controller = AddressSearchController(
      repository: _FakeRepository(),
      tokenFactory: () => 'token-${++index}',
    );
    controller.focus();
    expect(controller.sessionToken, 'token-1');
    controller.queryChanged('');
    expect(controller.status, AddressSearchStatus.cleared);
    controller.queryChanged('yen');
    expect(controller.sessionToken, 'token-2');
    controller.dispose();
  });

  test(
    'empty, rate limit ve provider unavailable güvenli durumlara çevrilir',
    () async {
      final empty = AddressSearchController(
        repository: _FakeRepository(result: const []),
        debounce: Duration.zero,
      );
      empty.queryChanged('abc');
      await _settle();
      expect(empty.status, AddressSearchStatus.empty);
      empty.dispose();
      final limited = AddressSearchController(
        repository: _FakeRepository(error: _api(429, 'raw provider secret')),
        debounce: Duration.zero,
      );
      limited.queryChanged('abc');
      await _settle();
      expect(limited.status, AddressSearchStatus.rateLimited);
      limited.dispose();
      final unavailable = AddressSearchController(
        repository: _FakeRepository(error: _api(503, 'Google raw error')),
        debounce: Duration.zero,
      );
      unavailable.queryChanged('abc');
      await _settle();
      expect(unavailable.status, AddressSearchStatus.providerUnavailable);
      unavailable.dispose();
    },
  );

  test('eksik mahalle null kalır ve koordinatlar doğru taşınır', () async {
    final incomplete = ResolvedAddress(
      placeId: 'tr-1',
      province: 'İstanbul',
      district: 'Kadıköy',
      latitude: 41.1,
      longitude: 29.2,
      countryCode: 'TR',
    );
    final repo = _FakeRepository(detailsResult: incomplete);
    final controller = AddressSearchController(
      repository: repo,
      debounce: Duration.zero,
    );
    controller.queryChanged('adres');
    await _settle();
    final result = await controller.select(suggestion);
    expect(result?.neighborhood, isNull);
    expect(result?.latitude, 41.1);
    expect(result?.longitude, 29.2);
    expect(controller.status, AddressSearchStatus.selected);
    controller.dispose();
  });

  test('dispose sonrası tamamlanan istek state update üretmez', () async {
    final repo = _FakeRepository(delay: const Duration(milliseconds: 20));
    final controller = AddressSearchController(
      repository: repo,
      debounce: Duration.zero,
    );
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.queryChanged('adres');
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    final before = notifications;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(notifications, before);
  });
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

ApiException _api(int code, String message) =>
    ApiException(message, statusCode: code);

class _FakeRepository implements AddressSearchRepository {
  _FakeRepository({
    this.delay = Duration.zero,
    this.result = const [
      AddressSuggestion(
        placeId: 'tr-1',
        primaryText: 'Bağdat Caddesi',
        secondaryText: 'Kadıköy/İstanbul',
        displayText: 'Bağdat Caddesi, Kadıköy/İstanbul',
      ),
    ],
    this.detailsResult = const ResolvedAddress(
      placeId: 'tr-1',
      formattedAddress: 'Caferağa Mah. Bağdat Cad. No: 10, Kadıköy/İstanbul',
      province: 'İstanbul',
      district: 'Kadıköy',
      neighborhood: 'Caferağa',
      street: 'Bağdat Caddesi',
      streetNumber: '10',
      latitude: 40.99,
      longitude: 29.03,
      countryCode: 'TR',
    ),
    this.error,
  });
  final Duration delay;
  final List<AddressSuggestion> result;
  final ResolvedAddress detailsResult;
  final Object? error;
  final queries = <String>[];
  final tokens = <String>[];
  final cancelled = <bool>[];
  @override
  Future<List<AddressSuggestion>> suggestions(
    String query,
    String sessionToken,
    CancelToken cancelToken,
  ) async {
    queries.add(query);
    tokens.add(sessionToken);
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    cancelled.add(cancelToken.isCancelled);
    if (cancelToken.isCancelled) {
      throw DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.cancel,
      );
    }
    if (error != null) throw error!;
    return result;
  }

  @override
  Future<ResolvedAddress> details(
    String placeId,
    String sessionToken,
    CancelToken cancelToken,
  ) async {
    tokens.add(sessionToken);
    if (error != null) throw error!;
    return detailsResult;
  }
}
