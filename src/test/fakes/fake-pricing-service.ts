import type { PricingPlan, PricingRule } from "@/features/pricing/types";
import { resolvePrice } from "@/features/pricing/validation";
import { setPricingService } from "@/services/pricing";
import type { PricingService } from "@/services/pricing/pricing.service";

/** In-memory stand-in for SupabasePricingService. */
export class FakePricingService implements PricingService {
  plans = new Map<string, PricingPlan>();
  saved: PricingRule[][] = [];

  async getPricingPlan(facilityId: string) {
    return this.plans.get(facilityId) ?? null;
  }

  async savePricingRules(facilityId: string, rules: PricingRule[]) {
    const now = new Date().toISOString();
    const plan: PricingPlan = {
      id: crypto.randomUUID(),
      facilityId,
      name: "Standard Pricing",
      currency: "INR",
      status: "ACTIVE",
      rules: rules.map((r) => ({ ...r, id: crypto.randomUUID(), audience: r.audience ?? "GENERAL" })),
      createdAt: now,
      updatedAt: now,
    };
    this.plans.set(facilityId, plan);
    this.saved.push(rules);
    return plan;
  }

  async deletePricingRule() {}

  async resolvePrice(facilityId: string, facilitySportId: string, playingAreaId: string | null, date: Date, time: string) {
    const plan = this.plans.get(facilityId);
    return plan ? resolvePrice(plan.rules, facilitySportId, playingAreaId, date, time) : null;
  }
}

/** Test seam: builds a fake, injects it via setPricingService, returns it for assertions. */
export function installFakePricingService(): FakePricingService {
  const service = new FakePricingService();
  setPricingService(service);
  return service;
}
