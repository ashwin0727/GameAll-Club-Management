import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../models/plan.dart';

/// Plans (migration 0157) — mirrors src/features/plans/service.ts.
class PlanRepository {
  PlanRepository(this._client);

  final SupabaseClient _client;

  Future<List<PlanOption>> listPlans() async {
    try {
      final rows = await _client.rpc('list_plans') as List<dynamic>;
      return rows.map((r) => PlanOption.fromJson((r as Map).cast<String, dynamic>())).toList();
    } catch (_) {
      throw AppException(AppErrorCode.databaseError, 'Unable to load the plans.');
    }
  }

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

  /// Step 1 of choosing a plan: the server checks the choice and creates the Razorpay subscription to authorise.
  Future<PlanCheckoutInfo> startPlan(String facilityId, String planCode, String interval) async {
    final data = await _call({'action': 'start', 'facilityId': facilityId, 'planCode': planCode, 'interval': interval}, 'Could not start the plan payment.');
    if (data['subscriptionId'] == null) throw AppException(AppErrorCode.databaseError, 'Could not start the plan payment.');
    return PlanCheckoutInfo.fromJson(data);
  }

  /// Step 2: after Razorpay returns, the server verifies the signature and switches the plan on.
  Future<void> confirmPlan({required String subscriptionId, required String paymentId, required String signature}) async {
    await _call(
      {'action': 'confirm', 'subscriptionId': subscriptionId, 'paymentId': paymentId, 'signature': signature},
      'Your payment went through, but we could not switch the plan on. Please contact support.',
    );
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body, String fallback) async {
    try {
      final res = await _client.functions.invoke('create-plan-subscription', body: body);
      final data = res.data;
      if (data is Map) return data.cast<String, dynamic>();
    } on FunctionException catch (e) {
      final d = e.details;
      throw AppException(AppErrorCode.databaseError, d is Map ? (d['error'] as String? ?? fallback) : fallback);
    }
    throw AppException(AppErrorCode.databaseError, fallback);
  }
}
