import 'package:berbergelsin/core/deep_link/app_deep_link.dart';
import 'package:berbergelsin/core/deep_link/deep_link_coordinator.dart';
import 'package:berbergelsin/core/deep_link/deep_link_parser.dart';
import 'package:berbergelsin/features/auth/bloc/auth_cubit.dart';
import 'package:berbergelsin/features/auth/models/app_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

class MemoryStorage implements Storage {
  final data = <String, dynamic>{};
  @override
  dynamic read(String key) => data[key];
  @override
  Future<void> write(String key, dynamic value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
  @override
  Future<void> clear() async => data.clear();
  @override
  Future<void> close() async {}
}

class TestAuthCubit extends AuthCubit {
  void setState(AuthState value) => emit(value);
}

const customer = AppUser(
  id: 'customer-1',
  phone: '5000000000',
  role: 'Musteri',
  onboardingCompleted: true,
);
const business = AppUser(
  id: 'business-1',
  phone: '5000000001',
  role: 'Berber',
  onboardingCompleted: true,
  barberStatus: 'Approved',
);

void main() {
  const id = '11111111-1111-1111-1111-111111111111';
  late TestAuthCubit auth;
  late GoRouter router;
  late DeepLinkCoordinator coordinator;
  late String currentLocation;

  setUp(() {
    HydratedBloc.storage = MemoryStorage();
    auth = TestAuthCubit();
    currentLocation = '/';
    router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SizedBox()),
        GoRoute(path: '/talep/:id', builder: (_, __) => const SizedBox()),
        GoRoute(path: '/isletme/:id', builder: (_, __) => const SizedBox()),
        GoRoute(path: '/favorilerim', builder: (_, __) => const SizedBox()),
        GoRoute(path: '/taleplerim', builder: (_, __) => const SizedBox()),
        GoRoute(path: '/berber', builder: (_, __) => const SizedBox()),
        GoRoute(path: '/baglanti-hatasi', builder: (_, __) => const SizedBox()),
      ],
    );
    coordinator = DeepLinkCoordinator(
      authCubit: auth,
      router: router,
      parser: DeepLinkParser(trustedHosts: const ['links.test']),
      navigate: (location, _) => currentLocation = location,
      currentLocation: () => currentLocation,
    );
  });

  tearDown(() async {
    coordinator.dispose();
    router.dispose();
    await auth.close();
  });

  test('rol matrisi müşteri-only routeu işletmede reddeder', () {
    final businessLink = coordinator.parser.parse(
      '/isletme/$id',
      source: DeepLinkSource.internal,
    );
    final requestLink = coordinator.parser.parse(
      '/talepler/$id',
      source: DeepLinkSource.internal,
    );
    final favoriteLink = coordinator.parser.parse(
      '/favoriler',
      source: DeepLinkSource.internal,
    );
    expect(
      coordinator.targetFor(businessLink, isCustomer: true),
      '/isletme/$id',
    );
    expect(coordinator.targetFor(businessLink, isCustomer: false), isNull);
    expect(coordinator.targetFor(favoriteLink, isCustomer: false), isNull);
    expect(coordinator.targetFor(requestLink, isCustomer: true), '/talep/$id');
    expect(coordinator.targetFor(requestLink, isCustomer: false), '/talep/$id');
  });

  testWidgets(
    'oturum kapalı link pending kalır ve login sonrası bir kez tüketilir',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      auth.setState(const AuthState(status: AuthStatus.unauthenticated));
      expect(
        await coordinator.open(
          '/talepler/$id',
          source: DeepLinkSource.coldStart,
        ),
        isFalse,
      );
      expect(coordinator.pending, isNotNull);
      auth.setState(
        const AuthState(status: AuthStatus.authenticated, user: customer),
      );
      await tester.pumpAndSettle();
      expect(coordinator.pending, isNull);
      expect(coordinator.state, DeepLinkState.completed);
      expect(currentLocation, '/talep/$id');
      expect(
        await coordinator.open(
          '/talepler/$id',
          source: DeepLinkSource.warmStart,
        ),
        isFalse,
      );
    },
  );

  test('logout ve kullanıcı değişimi eski pending linki temizler', () async {
    auth.setState(
      const AuthState(status: AuthStatus.authenticated, user: customer),
    );
    await Future<void>.delayed(Duration.zero);
    auth.setState(const AuthState(status: AuthStatus.unknown, user: customer));
    await Future<void>.delayed(Duration.zero);
    await coordinator.open('/talepler/$id', source: DeepLinkSource.internal);
    expect(coordinator.pending, isNotNull);
    auth.setState(const AuthState(status: AuthStatus.unauthenticated));
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.pending, isNull);

    auth.setState(
      const AuthState(status: AuthStatus.authenticated, user: customer),
    );
    await Future<void>.delayed(Duration.zero);
    auth.setState(const AuthState(status: AuthStatus.unknown, user: customer));
    await Future<void>.delayed(Duration.zero);
    await coordinator.open('/talepler/$id', source: DeepLinkSource.internal);
    auth.setState(
      const AuthState(status: AuthStatus.authenticated, user: business),
    );
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.pending, isNull);
  });
}
