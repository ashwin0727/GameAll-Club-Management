import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/plan.dart';

/// Plans (migration 0157) — read-only on mobile. Plans are chosen and paid for on the web (see models/plan.dart).
class PlanRepository {
  PlanRepository(this._client);

  final SupabaseClient _client;

  /// The club's plan, or null when none has been chosen (an unrestricted club). A failure also reads as "none" so a
  /// missing migration never locks a club out.
  Future<PlanSnapshot?> myPlan(String facilityId) async {
    try {
      final data = await _client.rpc('my_facility_plan', params: {'p_facility_id': facilityId});
      if (data == null) return null;
      return PlanSnapshot.fromJson((data as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  /// A club created in the app gets the free trial directly, with no payment step. Only the owner, only once; failing is harmless
  /// (the club simply stays unrestricted), so errors are not raised.
  Future<void> startFreeTrial(String facilityId) async {
    try {
      await _client.rpc('start_free_trial', params: {'p_facility_id': facilityId});
    } catch (_) {
      // Not fatal: setup must still finish.
    }
  }
}
