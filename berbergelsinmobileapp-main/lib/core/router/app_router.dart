import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/screens/admin_barber_detail_screen.dart';
import '../../features/admin/screens/admin_panel_screen.dart';
import '../../features/auth/bloc/auth_cubit.dart';
import '../../features/auth/screens/phone_login_screen.dart';
import '../../features/auth/screens/otp_login_screen.dart' hide GoogleLoginRunner;
import '../../features/auth/screens/google_phone_verification_screen.dart';
import '../../features/auth/screens/client_profile_screen.dart';
import '../../features/auth/screens/role_select_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/account_blocked_screen.dart';
import '../../features/auth/screens/password_login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/barber/screens/barber_panel_screen.dart';
import '../../features/barber/screens/barber_profile_screen.dart';
import '../../features/map/screens/client_home_screen.dart';
import '../../features/map/screens/client_barber_detail_screen.dart';
import '../../features/map/screens/client_map_screen.dart';
import '../../features/onboarding/screens/barber_onboarding_screen.dart';
import '../../features/onboarding/screens/client_onboarding_screen.dart';
import '../../features/onboarding/screens/pending_approval_screen.dart';
import '../../features/requests/screens/my_requests_screen.dart';
import '../../features/ratings/screens/client_ratings_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/requests/screens/request_detail_screen.dart';
import '../deep_link/deep_link_error_screen.dart';

GoRouter buildRouter(AuthCubit authCubit) {
  final refreshNotifier = ValueNotifier<int>(0);
  authCubit.stream.listen((_) => refreshNotifier.value++);
  return GoRouter(
    initialLocation: '/acilis',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final auth = authCubit.state;
      final loc = state.matchedLocation;

      if (auth.sessionStatus == SessionStatus.blocked) {
        return loc == '/hesap-durumu' ? null : '/hesap-durumu';
      }

      if (auth.status == AuthStatus.unknown) {
        return loc == '/acilis' ? null : '/acilis';
      }

      final publicRoutes = {'/', '/giris', '/giris-sifre', '/kayit-ol', '/email-giris', '/google-telefon-dogrulama', '/baglanti-hatasi', '/hesap-durumu'};
      if (auth.status == AuthStatus.unauthenticated) {
        return publicRoutes.contains(loc) ? null : '/';
      }

      // authenticated
      final user = auth.user;
      if (user == null) return '/';
      final customerSession = auth.selectedRole == 'Musteri';
      if (user.isAdmin) {
        if (loc == '/baglanti-hatasi') return null;
        return loc.startsWith('/admin') ? null : '/admin';
      }
      if (user.isMusteri || customerSession) {
        if (!user.onboardingCompleted) {
          return loc == '/onboarding/musteri' ? null : '/onboarding/musteri';
        }
        final allowed =
            loc == '/harita' ||
            loc == '/kesfet' ||
            loc == '/harita/tam' ||
            loc == '/taleplerim' ||
            loc == '/profil' ||
            loc == '/yorumlarim' ||
            loc == '/bildirimler' ||
            loc == '/baglanti-hatasi' ||
            loc.startsWith('/talep/') ||
            loc.startsWith('/isletme/');
        return allowed ? null : '/harita';
      }
      // İşletme
      if (user.barberStatus == 'Onboarding') {
        return loc == '/onboarding/berber' ? null : '/onboarding/berber';
      }
      if (user.barberStatus == 'PendingApproval' ||
          user.barberStatus == 'Rejected') {
        return loc == '/onay-bekliyor' ? null : '/onay-bekliyor';
      }
      // Approved
      final barberAllowed =
          loc == '/berber' ||
          loc == '/berber/profil' ||
          loc == '/bildirimler' ||
          loc == '/baglanti-hatasi' ||
          loc.startsWith('/talep/');
      return barberAllowed ? null : '/berber';
    },
    routes: [
      GoRoute(path: '/acilis', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/', builder: (_, __) => const RoleSelectScreen()),
      GoRoute(
        path: '/hesap-durumu',
        builder: (_, __) => const AccountBlockedScreen(),
      ),
      GoRoute(
        path: '/baglanti-hatasi',
        builder: (_, state) => DeepLinkErrorScreen(
          reason: state.uri.queryParameters['reason'] ?? 'invalid',
        ),
      ),
      GoRoute(path: '/giris-sifre', builder: (_, __) => const PasswordLoginScreen()),
      GoRoute(path: '/kayit-ol', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/giris', builder: (_, __) => const PhoneLoginScreen()),
      GoRoute(
        path: '/email-giris',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return OtpLoginScreen(
            googleLogin: extra?['googleLogin'] as GoogleLoginRunner?,
          );
        },
      ),
      GoRoute(
        path: '/google-telefon-dogrulama',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return GooglePhoneVerificationScreen(
            emailForVerification: extra?['email'] as String?,
            codeForVerification: extra?['code'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/onboarding/musteri',
        builder: (_, __) => const ClientOnboardingScreen(),
      ),
      GoRoute(
        path: '/onboarding/berber',
        builder: (_, __) => const BarberOnboardingScreen(),
      ),
      GoRoute(
        path: '/onay-bekliyor',
        builder: (_, __) => const PendingApprovalScreen(),
      ),
      GoRoute(path: '/harita', builder: (_, __) => const ClientHomeScreen()),
      GoRoute(path: '/kesfet', builder: (_, __) => const ClientMapScreen()),
      GoRoute(path: '/harita/tam', builder: (_, __) => const ClientMapScreen()),
      GoRoute(
        path: '/isletme/:id',
        builder: (_, state) => ClientBarberDetailScreen(
          barberProfileId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/taleplerim',
        builder: (_, __) => const MyRequestsScreen(),
      ),
      GoRoute(path: '/profil', builder: (_, __) => const ClientProfileScreen()),
      GoRoute(
        path: '/yorumlarim',
        builder: (_, __) => const ClientRatingsScreen(),
      ),
      GoRoute(
        path: '/bildirimler',
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/talep/:id',
        builder: (_, state) =>
            RequestDetailScreen(requestId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/berber', builder: (_, __) => const BarberPanelScreen()),
      GoRoute(
        path: '/berber/profil',
        builder: (_, __) => const BarberProfileScreen(),
      ),
      GoRoute(path: '/admin', builder: (_, __) => const AdminPanelScreen()),
      GoRoute(
        path: '/admin/berber/:id',
        builder: (_, state) => AdminBarberDetailScreen(
          barberProfileId: state.pathParameters['id']!,
        ),
      ),
      // 404 catch-all: bilinmeyen rotalar için
      GoRoute(
        path: '/:any',
        builder: (_, state) => DeepLinkErrorScreen(
          reason: state.uri.path,
        ),
      ),
    ],
  );
}
