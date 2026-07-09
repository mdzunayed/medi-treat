import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/dio_client.dart';
import '../../core/models/user.dart';

final dioClientProvider = Provider<DioClient>((ref) {
  return DioClient();
});

final authTokenProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<AuthToken?>>((ref) {
  final dioClient = ref.watch(dioClientProvider);
  return AuthNotifier(dioClient);
});

class AuthNotifier extends StateNotifier<AsyncValue<AuthToken?>> {
  final DioClient _dioClient;

  AuthNotifier(this._dioClient) : super(const AsyncValue.data(null)) {
    _loadStoredToken();
  }

  /// Cold-start hydration. Asks [DioClient] for the most recently saved
  /// `{token, refreshToken, user}` and pushes it into state so the
  /// router redirect picks the user's home immediately — no flash of
  /// the /login screen on a returning user.
  Future<void> _loadStoredToken() async {
    try {
      final restored = await _dioClient.restoreSession();
      if (restored != null) state = AsyncValue.data(restored);
    } catch (_) {
      // Failure to read prefs is fatal-er than a login miss: just stay
      // on the signed-out default so the user can sign in manually.
    }
  }

  /// Role-aware sign-in. [identifier] is interpreted as a phone when
  /// it contains no `@`, otherwise an email — the email path keeps
  /// the legacy `/login` screen's seeded admin/doctor demos working.
  /// [role] is mandatory now; the backend rejects role mismatches
  /// with a 403 (see DioClient._handleError for the message it
  /// surfaces).
  Future<void> login(
    String identifier,
    String password, {
    required UserRole role,
  }) async {
    state = const AsyncValue.loading();
    try {
      final isEmail = identifier.contains('@');
      final token = await _dioClient.login(
        phone: isEmail ? null : identifier,
        email: isEmail ? identifier : null,
        password: password,
        role: role,
      );
      state = AsyncValue.data(token);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  /// Promotes a freshly-issued [AuthToken] into the notifier state.
  /// Used by the OTP flow: `DioClient.verifyOtp` already persisted the
  /// session to SharedPreferences, this just wakes up the router
  /// redirect by pushing the token into Riverpod state.
  void hydrate(AuthToken token) {
    state = AsyncValue.data(token);
  }

  /// Google OAuth sign-in. Hands the profile lifted by `google_sign_in`
  /// (email, googleId, fullName, photoUrl) to the backend bridge at
  /// `/auth/google`, which find-or-creates an Account and returns a
  /// JWT. The session is then persisted via DioClient + SharedPreferences
  /// like any other login.
  Future<void> loginWithGoogle({
    required String email,
    required String googleId,
    required String fullName,
    String photoUrl = '',
    UserRole role = UserRole.patient,
  }) async {
    state = const AsyncValue.loading();
    try {
      final token = await _dioClient.loginWithGoogle(
        email: email,
        googleId: googleId,
        fullName: fullName,
        photoUrl: photoUrl,
        role: role,
      );
      state = AsyncValue.data(token);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  /// Submits the new password chosen on `ForcedPasswordResetScreen`.
  /// Mints a fresh session (the server clears the `requires_password_reset`
  /// latch + re-issues a clean token) and pushes it into state so the
  /// router redirect lands the user on their dashboard immediately.
  Future<void> completeForcedPasswordReset(String newPassword) async {
    state = const AsyncValue.loading();
    try {
      final token = await _dioClient.completePasswordReset(
        newPassword: newPassword,
      );
      state = AsyncValue.data(token);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<void> logout() async {
    await _dioClient.clearTokens();
    state = const AsyncValue.data(null);
  }
}

// Helper providers
final currentUserProvider = Provider<User?>(
  (ref) {
    final authToken = ref.watch(authTokenProvider);
    return authToken.maybeWhen(
      data: (token) => token?.user,
      orElse: () => null,
    );
  },
);

final isAuthenticatedProvider = Provider<bool>(
  (ref) {
    final user = ref.watch(currentUserProvider);
    return user != null;
  },
);

final userRoleProvider = Provider<UserRole?>(
  (ref) {
    final user = ref.watch(currentUserProvider);
    return user?.role;
  },
);

/// True only when the signed-in account is admin-provisioned and is
/// still carrying a single-use temporary password. The router
/// redirect detours these sessions into `/forced-password-reset`
/// instead of the role-specific dashboard.
final requiresPasswordResetProvider = Provider<bool>(
  (ref) {
    final authToken = ref.watch(authTokenProvider);
    return authToken.maybeWhen(
      data: (token) {
        if (token == null) return false;
        return token.requiresReset || token.user.requiresPasswordReset;
      },
      orElse: () => false,
    );
  },
);
