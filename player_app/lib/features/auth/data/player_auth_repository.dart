import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../domain/player_profile.dart';

/// Signing in and out, and the player's own profile. The Supabase version is the real one; tests supply a fake.
///
/// A player signs in with a phone number and a one-time code sent by SMS. The first time, they also give a name and an email address,
/// which creates their player profile (database function `register_player`, migration 0169). The profile's phone number is the one that
/// was verified by the code: it is never typed into the profile form.
abstract class PlayerAuthRepository {
  /// False in a build made without env.json: there is no backend to sign in to.
  bool get isConfigured;

  bool get isSignedIn;

  /// Emits whenever the signed-in state changes (signed in, signed out, session restored).
  Stream<void> get changes;

  /// Sends a six-digit code to [phone] (international format, "+919876543210").
  Future<void> sendCode(String phone);

  /// Checks the code. Signs the player in when it is right.
  Future<void> verifyCode(String phone, String code);

  /// The signed-in player's profile; null when they have signed in but not yet given their name and email.
  Future<PlayerProfile?> myProfile();

  Future<PlayerProfile> register({required String fullName, required String email});

  Future<void> signOut();
}

/// Something the player can be told in plain words.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

class SupabasePlayerAuthRepository implements PlayerAuthRepository {
  SupabasePlayerAuthRepository([SupabaseClient? client]) : _injected = client;

  final SupabaseClient? _injected;

  SupabaseClient? get _client {
    if (_injected != null) return _injected;
    if (!AppConfig.isConfigured) return null;
    return Supabase.instance.client;
  }

  SupabaseClient get _need {
    final c = _client;
    if (c == null) throw const AuthFailure('Sign in is not available in this build.');
    return c;
  }

  @override
  bool get isConfigured => _client != null;

  @override
  bool get isSignedIn => _client?.auth.currentUser != null;

  @override
  Stream<void> get changes => _client?.auth.onAuthStateChange.map((_) {}) ?? const Stream.empty();

  @override
  Future<void> sendCode(String phone) async {
    try {
      await _need.auth.signInWithOtp(phone: phone, shouldCreateUser: true);
    } on AuthException catch (e) {
      throw AuthFailure(_sendMessage(e));
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure("We couldn't reach GameAll. Check your connection and try again.");
    }
  }

  @override
  Future<void> verifyCode(String phone, String code) async {
    try {
      await _need.auth.verifyOTP(phone: phone, token: code, type: OtpType.sms);
    } on AuthException catch (e) {
      throw AuthFailure(_verifyMessage(e));
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure("We couldn't reach GameAll. Check your connection and try again.");
    }
  }

  @override
  Future<PlayerProfile?> myProfile() async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) return null;
    try {
      final result = await client.rpc('get_my_player');
      if (result == null) return null;
      return PlayerProfile.fromJson((result as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      // The database function is not installed yet (migration 0169): treat as "no profile yet" so the app does not crash.
      if (e.code == 'PGRST202' || e.code == '42883') return null;
      rethrow;
    }
  }

  @override
  Future<PlayerProfile> register({required String fullName, required String email}) async {
    try {
      final result = await _need.rpc('register_player', params: {'p_full_name': fullName.trim(), 'p_email': email.trim()});
      return PlayerProfile.fromJson((result as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      if (e.code == '23505') throw const AuthFailure('This phone number already belongs to another player.');
      if (e.code == '23514') throw AuthFailure(e.message);
      if (e.code == 'PGRST202' || e.code == '42883') throw const AuthFailure('Player accounts are not switched on yet. Please try again soon.');
      throw const AuthFailure("We couldn't save your details. Please try again.");
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure("We couldn't reach GameAll. Check your connection and try again.");
    }
  }

  @override
  Future<void> signOut() async {
    await _client?.auth.signOut();
  }

  static String _sendMessage(AuthException e) {
    final m = e.message.toLowerCase();
    // Phone sign-in has not been switched on (Supabase Auth > Phone) yet.
    if (e.code == 'phone_provider_disabled' || m.contains('unsupported phone provider')) return 'Phone sign-in is not available yet. Please try again later.';
    if (m.contains('rate') || m.contains('seconds') || e.statusCode == '429') return 'Too many attempts. Please wait a minute and try again.';
    if (m.contains('invalid') && m.contains('phone')) return 'That phone number does not look right.';
    // An SMS provider that is not switched on yet, or any other send failure.
    return "We couldn't send the code right now. Please try again in a moment.";
  }

  static String _verifyMessage(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('rate') || e.statusCode == '429') return 'Too many attempts. Please wait a minute and try again.';
    return "That code isn't right, or it has expired. Check it or ask for a new one.";
  }
}
