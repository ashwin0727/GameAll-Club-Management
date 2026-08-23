import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/app_exception.dart';
import '../models/app_user.dart';

/// Mirrors src/services/auth/supabase-auth.service.ts — same Supabase Auth
/// configuration and `profiles` trigger the web app relies on, so an
/// account created on either client works identically on the other.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signUp(
        email: email,
        password: password,
        // Consumed by the handle_new_user trigger to seed the profile row —
        // identical metadata shape to the web signup form.
        data: {'full_name': name, 'account_type': 'owner'},
      );
    } on AuthException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> login({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> logout() async {
    await _client.auth.signOut();
  }

  Future<void> resendVerificationEmail(String email) async {
    try {
      await _client.auth.resend(type: OtpType.signup, email: email);
    } on AuthException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  bool get isEmailVerified =>
      _client.auth.currentUser?.emailConfirmedAt != null;

  /// Re-fetches the current session's user + profile from the server —
  /// call after a resend/refresh to check verification status, not a
  /// locally-cached guess.
  Future<AppUser?> getCurrentUser() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) return null;

    final profile = await _client
        .from('profiles')
        .select('id, full_name, email, role, onboarding_completed')
        .eq('id', authUser.id)
        .maybeSingle();

    if (profile == null) {
      return AppUser(
        id: authUser.id,
        fullName: (authUser.userMetadata?['full_name'] as String?) ?? '',
        email: authUser.email ?? '',
        role: 'member',
        onboardingCompleted: false,
      );
    }
    return AppUser.fromJson(profile);
  }
}