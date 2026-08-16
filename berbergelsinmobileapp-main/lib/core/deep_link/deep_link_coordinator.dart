import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/bloc/auth_cubit.dart';
import 'app_deep_link.dart';
import 'deep_link_parser.dart';

enum DeepLinkState {
  idle,
  pending,
  resolvingAuth,
  resolvingEntity,
  navigating,
  completed,
  rejected,
  error,
}

class DeepLinkCoordinator extends ChangeNotifier {
  DeepLinkCoordinator({
    required this.authCubit,
    required this.router,
    DeepLinkParser? parser,
    DateTime Function()? now,
    void Function(String location, bool replace)? navigate,
    String Function()? currentLocation,
  }) : parser = parser ?? DeepLinkParser(),
       _now = now ?? DateTime.now,
       _navigateOverride = navigate,
       _currentLocationOverride = currentLocation {
    _lastAuth = authCubit.state;
    _authSubscription = authCubit.stream.listen(_onAuthChanged);
  }

  final AuthCubit authCubit;
  final GoRouter router;
  final DeepLinkParser parser;
  final DateTime Function() _now;
  final void Function(String location, bool replace)? _navigateOverride;
  final String Function()? _currentLocationOverride;
  late final StreamSubscription<AuthState> _authSubscription;
  late AuthState _lastAuth;
  final Map<String, DateTime> _recent = {};
  AppDeepLink? _pending;
  String? _pendingOwnerId;
  bool _processing = false;
  DeepLinkState state = DeepLinkState.idle;

  AppDeepLink? get pending => _pending;

  Future<bool> open(String raw, {required DeepLinkSource source}) async {
    final link = parser.parse(raw, source: source);
    if (!link.isKnown) {
      _setState(DeepLinkState.rejected);
      _safeGo('/baglanti-hatasi?reason=unsupported');
      return false;
    }
    final key = '${link.type.name}:${link.entityId ?? ''}';
    final now = _now();
    _recent.removeWhere(
      (_, at) => now.difference(at) > const Duration(seconds: 3),
    );
    if (_recent.containsKey(key) || _processing) return false;
    _recent[key] = now;
    _pending = link;
    _pendingOwnerId = authCubit.state.status == AuthStatus.authenticated
        ? authCubit.state.user?.id
        : null;
    _setState(DeepLinkState.pending);
    return _consume();
  }

  Future<bool> _consume() async {
    final link = _pending;
    if (link == null || _processing) return false;
    final auth = authCubit.state;
    if (auth.status == AuthStatus.unknown) {
      _setState(DeepLinkState.resolvingAuth);
      return false;
    }
    if (auth.status != AuthStatus.authenticated) {
      _setState(DeepLinkState.resolvingAuth);
      _safeGo('/');
      return false;
    }
    if (_pendingOwnerId != null && _pendingOwnerId != auth.user?.id) {
      clearPending();
      return false;
    }
    final customer = auth.user!.isMusteri || auth.selectedRole == 'Musteri';
    final target = targetFor(link, isCustomer: customer);
    if (target == null) {
      _pending = null;
      _setState(DeepLinkState.rejected);
      _safeGo('/baglanti-hatasi?reason=unauthorized');
      return false;
    }
    _processing = true;
    _pending = null;
    _setState(DeepLinkState.resolvingEntity);
    try {
      _setState(DeepLinkState.navigating);
      final current =
          _currentLocationOverride?.call() ??
          router.routeInformationProvider.value.uri.path;
      if (current != target) {
        final navigate = _navigateOverride;
        if (navigate != null) {
          navigate(target, false);
        } else {
          router.push(target);
        }
      }
      _setState(DeepLinkState.completed);
      return true;
    } catch (_) {
      _setState(DeepLinkState.error);
      _safeGo('/baglanti-hatasi?reason=network');
      return false;
    } finally {
      _processing = false;
    }
  }

  @visibleForTesting
  String? targetFor(AppDeepLink link, {required bool isCustomer}) =>
      switch (link.type) {
        AppDeepLinkType.businessDetail =>
          isCustomer ? '/isletme/${link.entityId}' : null,
        AppDeepLinkType.requestDetail ||
        AppDeepLinkType.appointmentDetail => '/talep/${link.entityId}',
        AppDeepLinkType.offerDetail => isCustomer ? '/taleplerim' : '/berber',
        AppDeepLinkType.notifications => '/bildirimler',
        AppDeepLinkType.favorites => isCustomer ? '/favorilerim' : null,
        AppDeepLinkType.ratings => isCustomer ? '/yorumlarim' : null,
        AppDeepLinkType.addresses => isCustomer ? '/adreslerim' : null,
        AppDeepLinkType.unknown => null,
      };

  void _onAuthChanged(AuthState auth) {
    final wasAuthenticated = _lastAuth.status == AuthStatus.authenticated;
    final wasKnownAccount = _lastAuth.user != null;
    final accountChanged =
        wasAuthenticated &&
        auth.status == AuthStatus.authenticated &&
        _lastAuth.user?.id != auth.user?.id;
    if ((auth.status == AuthStatus.unauthenticated &&
            (_pendingOwnerId != null || wasKnownAccount)) ||
        (wasAuthenticated && auth.status == AuthStatus.unauthenticated) ||
        accountChanged) {
      clearPending();
      _recent.clear();
    } else if (_pending != null && auth.status != AuthStatus.unknown) {
      unawaited(_consume());
    }
    _lastAuth = auth;
  }

  void clearPending() {
    _pending = null;
    _pendingOwnerId = null;
    _setState(DeepLinkState.idle);
  }

  void _safeGo(String location) {
    try {
      final navigate = _navigateOverride;
      if (navigate != null) {
        navigate(location, true);
      } else {
        router.go(location);
      }
    } catch (_) {}
  }

  void _setState(DeepLinkState value) {
    state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }
}
