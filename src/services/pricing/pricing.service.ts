import type { PricingPlan, PricingRule } from "@/features/pricing/types";

/**
 * The pricing boundary the UI codes against. A facility's rules are always
 * saved as a full replacement of its active plan's rule set (see
 * save_pricing_rules in 0005_pricing.sql), so callers pass the complete
 * desired rule list rather than diffing themselves.
 */
export interface PricingService {
  getPricingPlan(facilityId: string): Promise<PricingPlan | null>;
  savePricingRules(facilityId: string, rules: PricingRule[]): Promise<PricingPlan>;
  deletePricingRule(ruleId: string): Promise<void>;
  /**
   * Priority: playing-area rule > sport rule > none. Reused later by
   * Bookings/Memberships/Guest/Reports — see resolvePrice() in validation.ts
   * for the pure resolution logic this wraps.
   */
  resolvePrice(
    facilityId: string,
    facilitySportId: string,
    playingAreaId: string | null,
    date: Date,
    time: string,
  ): Promise<PricingRule | null>;
}