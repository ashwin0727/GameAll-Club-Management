import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/app_exception.dart';
import '../models/pricing.dart';

/// Mirrors src/services/pricing/supabase-pricing.service.ts — same
/// `save_pricing_rules` RPC (get-or-create plan, replace rules, reject
/// overlapping time-bounded rules server-side).
class PricingRepository {
  PricingRepository(this._client);

  final SupabaseClient _client;

  Future<PricingPlan?> getPricingPlan(String facilityId) async {
    try {
      final plan = await _client
          .from('pricing_plans')
          .select()
          .eq('facility_id', facilityId)
          .eq('status', 'ACTIVE')
          .maybeSingle();
      if (plan == null) return null;

      final rules = await _client
          .from('pricing_rules')
          .select()
          .eq('pricing_plan_id', plan['id'] as String)
          .eq('is_active', true);

      return PricingPlan.fromJson(plan, (rules as List<dynamic>).cast<Map<String, dynamic>>());
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> savePricingRules(String facilityId, List<PricingRule> rules) async {
    try {
      await _client.rpc(
        'save_pricing_rules',
        params: {
          'p_facility_id': facilityId,
          'p_plan_name': 'Standard Pricing',
          'p_rules': rules.map((r) => r.toPayload()).toList(),
        },
      );
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e, invalid: AppErrorCode.invalidPlayingArea);
    }
  }
}