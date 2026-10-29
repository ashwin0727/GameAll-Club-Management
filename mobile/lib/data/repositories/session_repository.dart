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
      final data = await _client.rpc('get_session_bundle');
      if (data is! Map) return null;
      return SessionBundle.fromJson(data.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }
}
