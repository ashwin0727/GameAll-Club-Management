import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../models/app_user.dart';

/// Mirrors src/services/auth/supabase-auth.service.ts — same Supabase Auth
/// configuration and `profiles` trigger the web app relies on, so an
/// account created on either client works identically on the other.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  /// Calls the `signup-otp` edge function — same one the web uses. It creates the account unconfirmed and emails a
  /// 6-digit code (Resend); no Supabase confirmation link is involved.
  Future<void> _signupOtp(Map<String, dynamic> body) => _signupOtpFunction('signup-otp', body);

  Future<void> _signupOtpFunction(String function, Map<String, dynamic> body) async {
    try {
      await _client.functions.invoke(function, body: body);
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map ? details['message'] : null;
      throw AppException(
        AppErrorCode.databaseError,
        message is String && message.isNotEmpty ? message : null,
      );
    } on AuthException catch (e) {
      throw mapSupabaseError(e);
    } on AppException {
      rethrow;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) =>
      _signupOtp({'action': 'start', 'name': name, 'email': email, 'password': password});

  /// Checks the code the owner received by email; on success the address is confirmed server-side.
  Future<void> verifySignupCode({required String email, required String code}) =>
      _signupOtp({'action': 'verify', 'email': email, 'code': code});

  /// Texts a 6-digit code to [phone] (10-digit Indian mobile) — the `mobile-otp` edge function, same as the web.
  Future<void> sendMobileOtp(String phone) =>
      _signupOtpFunction('mobile-otp', {'action': 'send', 'purpose': 'signup', 'phone': phone});

  /// Checks the SMS code; on success the number is recorded against the signed-in account server-side.
  Future<void> verifyMobileOtp({required String phone, required String code}) =>
      _signupOtpFunction('mobile-otp', {'action': 'verify', 'purpose': 'signup', 'phone': phone, 'code': code});

  Future<void> login({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> logout() async {
    try {
      // Local scope only — clears this device's session without a network
      // round-trip that can fail (expired token, offline) and surface as an
      // unhandled error on the sign-out tap.
      await _client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // The session is being torn down regardless.
    }
  }

  Future<void> resendVerificationEmail(String email) => _signupOtp({'action': 'resend', 'email': email});

  /// Mirrors src/services/auth/supabase-auth.service.ts's `resetPassword` —
  /// a missing account must look identical to a real one, so only genuine
  /// infra failures surface here, never "user not found". The reset link
  /// opens the web app's existing `/reset-password` page rather than a
  /// mobile deep link.
  Future<void> resetPassword(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email,
        redirectTo: AppConfig.webAppUrl.isNotEmpty ? '${AppConfig.webAppUrl}/reset-password' : null,
      );
    } on AuthException catch (e) {
      if (RegExp('user not found', caseSensitive: false).hasMatch(e.message)) return;
      throw mapSupabaseError(e);
    }
  }

  bool get isEmailVerified =>
      _client.auth.currentUser?.emailConfirmedAt != null;

  /// Re-fetches the current session's user + profile from the server —
  /// call after a resend/refresh to check verification status, not a
  /// locally-cached guess.
  ///
  /// [profileRow] is the person's profile when the caller already has it (from the session bundle), which saves a request.
  Future<AppUser?> getCurrentUser({Map<String, dynamic>? profileRow}) async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) return null;

    final profile = profileRow ??
        await _client
            .from('profiles')
            .select('id, full_name, email, role, onboarding_completed, must_reset_password')
            .eq('id', authUser.id)
            .maybeSingle();

    // New owners (signup-otp sets require_mobile) must verify a mobile number before onboarding.
    var pending = false;
    if (authUser.userMetadata?['require_mobile'] == true) {
      final verified = await _client
          .from('user_verified_phones')
          .select('user_id')
          .eq('user_id', authUser.id)
          .maybeSingle();
      pending = verified == null;
    }

    if (profile == null) {
      return AppUser(
        id: authUser.id,
        fullName: (authUser.userMetadata?['full_name'] as String?) ?? '',
        email: authUser.email ?? '',
        role: 'member',
        onboardingCompleted: false,
        mobileVerificationPending: pending,
      );
    }
    return AppUser.fromJson(profile).withMobileVerificationPending(pending);
  }
}