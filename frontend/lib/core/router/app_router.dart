import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/user.dart';
import '../../core/utils/slug.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/forced_password_reset_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/auth/screens/otp_verify_screen.dart';
import '../../features/auth/screens/sign_up_step1_screen.dart';
import '../../features/auth/screens/verify_success_screen.dart';
import '../../features/auth/screens/welcome_back_screen.dart';
import '../../features/patient/screens/patient_main_navigation_wrapper.dart';
import '../../features/doctor/presentation/doctor_main_shell.dart';
import '../../features/nurse/presentation/nurse_main_shell.dart';
import '../../features/admin/screens/admin_overview_screen.dart';
import '../../features/auth/auth_provider.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authTokenProvider);
  final user = ref.watch(currentUserProvider);
  final requiresReset = ref.watch(requiresPasswordResetProvider);

  String initialLocation() {
    return authState.maybeWhen(
      data: (token) {
        if (token == null) return '/login';
        if (requiresReset) return '/forced-password-reset';
        return routeForUser(user);
      },
      orElse: () => '/login',
    );
  }

  return GoRouter(
    initialLocation: initialLocation(),
    redirect: (context, state) {
      final isAuthenticated = authState.maybeWhen(
        data: (token) => token != null,
        orElse: () => false,
      );

      // Routes that are reachable WITHOUT being signed in. The new
      // sign-up / OTP / success screens belong here so an anonymous
      // visitor can complete onboarding before the token exists.
      const publicRoutes = {
        '/login',
        '/legacy-login',
        '/welcome-back',
        '/sign-up',
        '/otp-verify',
        '/verify-success',
        '/forgot-password',
      };

      if (!isAuthenticated && !publicRoutes.contains(state.matchedLocation)) {
        return '/login';
      }

      // Forced-reset gate. An admin-provisioned doctor / nurse signed
      // in with a temporary password must clear the latch before they
      // can reach any other authenticated surface.
      if (isAuthenticated &&
          requiresReset &&
          state.matchedLocation != '/forced-password-reset') {
        return '/forced-password-reset';
      }
      // Conversely, once the latch is cleared the screen is no longer
      // reachable — bounce back to the role-specific home.
      if (isAuthenticated &&
          !requiresReset &&
          state.matchedLocation == '/forced-password-reset') {
        return routeForUser(user);
      }

      if (isAuthenticated && state.matchedLocation == '/login') {
        return routeForUser(user);
      }

      return null;
    },
    routes: [
      // `/login` now renders the new Welcome Back (phone + role-picker
      // + Sign Up button). Every existing redirect / bookmark / sign-out
      // path that points at /login keeps working without code changes.
      GoRoute(
        path: '/login',
        builder: (context, state) => const WelcomeBackScreen(),
      ),
      // Same screen reachable at its canonical path.
      GoRoute(
        path: '/welcome-back',
        builder: (context, state) => const WelcomeBackScreen(),
      ),
      // Legacy email + role-picker demo (seeded admin/doctor creds).
      // Kept for QA / back-office sign-in until phone-based equivalents
      // exist for the admin and doctor demo accounts.
      GoRoute(
        path: '/legacy-login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/sign-up',
        builder: (context, state) => const SignUpStep1Screen(),
      ),
      GoRoute(
        path: '/otp-verify',
        builder: (context, state) => const OtpVerifyScreen(),
      ),
      // Forgot password — single-screen reset that takes phone +
      // 6-digit OTP + new password. `extra` carries the phone the
      // user already typed on Welcome Back so they don't retype it.
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => ForgotPasswordScreen(
          initialPhone: state.extra is String ? state.extra as String : null,
        ),
      ),
      // Authenticated profile settings (doctor + patient). NOT in the
      // public-routes whitelist — anonymous visitors get bounced to
      // /login by the redirect.
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/verify-success',
        builder: (context, state) => const VerifySuccessScreen(),
      ),
      // Forced-reset gate for admin-provisioned doctors / nurses. The
      // redirect above ensures only sessions with the latch set can
      // reach this surface, and that they can't reach anything else.
      GoRoute(
        path: '/forced-password-reset',
        builder: (context, state) => const ForcedPasswordResetScreen(),
      ),
      GoRoute(
        path: '/patient/:name',
        builder: (context, state) => const PatientMainNavigationWrapper(),
      ),
      GoRoute(
        path: '/doctor/:name',
        builder: (context, state) => const DoctorMainShell(),
      ),
      GoRoute(
        path: '/nurse/:name',
        builder: (context, state) => const NurseMainShell(),
      ),
      GoRoute(
        path: '/admin/:name',
        builder: (context, state) => const AdminOverviewScreen(),
      ),
    ],
  );
});

/// Builds the canonical destination route for a signed-in user, e.g.
/// `/patient/rumi-ahmed`. Falls back to `/login` if no user is loaded yet.
String routeForUser(User? user) {
  if (user == null) return '/login';
  final slug = slugify(user.name);
  switch (user.role) {
    case UserRole.doctor:
      return '/doctor/$slug';
    case UserRole.nurse:
      return '/nurse/$slug';
    case UserRole.admin:
      return '/admin/$slug';
    case UserRole.patient:
      return '/patient/$slug';
  }
}
