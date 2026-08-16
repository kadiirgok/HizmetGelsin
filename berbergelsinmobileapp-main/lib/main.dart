import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'core/router/app_router.dart';
import 'core/deep_link/deep_link_coordinator.dart';
import 'core/deep_link/deep_link_ingress.dart';
import 'core/theme/app_theme.dart';
import 'core/push/push_service.dart';
import 'features/auth/bloc/auth_cubit.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Play Integrity ile cihaz doğrulama (reCAPTCHA Chrome yönlendirmesini engeller)
  // Debug build'lerde native BerbergelsinApp sınıfı debug App Check provider'ı kurar.
  // Debug secret token'ı Firebase Console > App Check > "Manage debug tokens" kısmına ekleyin.
  if (!kDebugMode) {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: AndroidPlayIntegrityProvider(),
    );
  } else {
    // Debug build: App Check native tarafta (BerbergelsinApp.kt) kuruldu.
    // Debug token: adb logcat -d | grep "DebugAppCheckProvider"
  }

  HydratedBloc.storage = await HydratedStorage.build(
    storageDirectory: HydratedStorageDirectory(
      (await getApplicationDocumentsDirectory()).path,
    ),
  );
  runApp(const BerbergelsinApp());
}

class BerbergelsinApp extends StatefulWidget {
  const BerbergelsinApp({super.key});

  @override
  State<BerbergelsinApp> createState() => _BerbergelsinAppState();
}

class _BerbergelsinAppState extends State<BerbergelsinApp> {
  late final AuthCubit _authCubit;
  late final router = buildRouter(_authCubit);
  late final DeepLinkCoordinator _deepLinks;
  late final PushService _push;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authCubit = AuthCubit();
    _deepLinks = DeepLinkCoordinator(authCubit: _authCubit, router: router);
    _push = PushService();
    _authCubit.beforeLogout = _push.unregister;
    _authSubscription = _authCubit.stream.listen((state) {
      final user = state.user;
      if (state.status == AuthStatus.authenticated && user != null) {
        _push.bindUser(user.id);
      }
    });
    _push.initialize(_deepLinks);
    _authCubit.bootstrap();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _push.dispose();
    _deepLinks.dispose();
    router.dispose();
    _authCubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DeepLinkCoordinator>.value(
      value: _deepLinks,
      child: BlocProvider.value(
        value: _authCubit,
        child: DeepLinkIngress(
          coordinator: _deepLinks,
          child: MaterialApp.router(
            title: 'HizmetGelsin',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            locale: const Locale('tr', 'TR'),
            supportedLocales: const [Locale('tr', 'TR')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            routerConfig: router,
          ),
        ),
      ),
    );
  }
}
