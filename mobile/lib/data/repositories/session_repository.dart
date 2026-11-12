import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/facility.dart';
import '../models/plan.dart';

/// Everything the app needs right after sign-in, from ONE database call (get_session_bundle, migration 0164): the profile row, the
/// person's facility, their role there, their permissions, the facility's plan and whether they are the platform admin. Before, the
/// app made six requests one after another (profile, facility, role, permissions, login stamp, plan).
class SessionBundle {
  const SessionBundle({
    required this.profile,
    required this.facility,
    required this.baseRole,
    required this.permissions,
    required this.plan,
    required this.isPlatformAdmin,
  });

  /// The `profiles` row as JSON, or null when the person has none yet.
  final Map<String, dynamic>? profile;
  final Facility? facility;
  final String? baseRole;
  final Set<String> permissions;
  final PlanSnapshot? plan;
  final bool isPlatformAdmin;

  factory SessionBundle.fromJson(Map<String, dynamic> j) {
    final facility = j['facility'];
    final plan = j['plan'];
    final profile = j['profile'];
    return SessionBundle(
      profile: profile is Map ? profile.cast<String, dynamic>() : null,
      facility: facility is Map ? Facility.fromJson(facility.cast<String, dynamic>()) : null,
      baseRole: j['baseRole'] as String?,
      permissions: ((j['permissions'] as List<dynamic>?) ?? const []).map((e) => '$e').toSet(),
      plan: plan is Map ? PlanSnapshot.fromJson(plan.cast<String, dynamic>()) : null,
      isPlatformAdmin: j['isPlatformAdmin'] == true,
    );
  }
}

class SessionRepository {
  SessionRepository(this._client);

  final SupabaseClient _client;

  /// The bundle, or null when it cannot be had (signed out, a network error, or the function is not deployed yet). The caller then
  /// falls back to the individual requests, so an older database keeps working.
  Future<SessionBundle?> fetch() async {
    try {
      final data = await _client.rpc('get_session_bundle').timeout(const Duration(seconds: 8));
      if (data is! Map) return null;
      final json = data.cast<String, dynamic>();
      _remember(json);
      return SessionBundle.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static const _cacheKey = 'session_bundle_v1';

  /// Keeps the last bundle on the phone, so the next app start can open straight onto the right screen while the fresh one loads.
  void _remember(Map<String, dynamic> json) {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    SharedPreferences.getInstance().then((p) => p.setString(_cacheKey, jsonEncode({'uid': uid, 'data': json}))).catchError((Object _) => false);
  }

  /// The bundle saved at the last start, for this person only; null when there is none (first start, other person, signed out).
  Future<SessionBundle?> cached() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return null;
      final raw = (await SharedPreferences.getInstance()).getString(_cacheKey);
      if (raw == null) return null;
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      if (saved['uid'] != uid) return null;
      return SessionBundle.fromJson((saved['data'] as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  /// Forgets the saved bundle (sign-out), so the next person on this phone never sees it.
  Future<void> forget() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_cacheKey);
    } catch (_) {}
  }
}
