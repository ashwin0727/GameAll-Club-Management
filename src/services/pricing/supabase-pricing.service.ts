"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import { resolvePrice as resolvePriceUtil, validatePricingRules } from "@/features/pricing/validation";
import type { PricingPlan, PricingRule } from "@/features/pricing/types";
import type { PricingService } from "@/services/pricing/pricing.service";
import { ServiceError, mapSupabaseError } from "@/services/shared/service-error";
import type { Database } from "@/types/database.types";

type PlanRow = Database["public"]["Tables"]["pricing_plans"]["Row"];
type RuleRow = Database["public"]["Tables"]["pricing_rules"]["Row"];

function toRule(row: RuleRow): PricingRule {
  return {
    id: row.id,
    facilitySportId: row.facility_sport_id,
    playingAreaId: row.playing_area_id ?? undefined,
    dayType: row.day_type,
    coversFullDay: row.covers_full_day,
    startTime: row.start_time?.slice(0, 5) ?? undefined,
    endTime: row.end_time?.slice(0, 5) ?? undefined,
    amountMinor: row.amount_minor,
    currency: row.currency,
    pricingUnit: row.pricing_unit,
    priority: row.priority,
  };
}

function toRulePayload(rule: PricingRule) {
  return {
    facilitySportId: rule.facilitySportId,
    playingAreaId: rule.playingAreaId ?? "",
    dayType: rule.dayType,
    coversFullDay: rule.coversFullDay,
    startTime: rule.coversFullDay ? "" : rule.startTime,
    endTime: rule.coversFullDay ? "" : rule.endTime,
    amountMinor: rule.amountMinor,
    currency: rule.currency,
    pricingUnit: rule.pricingUnit,
    priority: rule.priority,
  };
}

export class SupabasePricingService implements PricingService {
  private readonly supabase: SupabaseClient<Database>;

  constructor(client?: SupabaseClient<Database>) {
    this.supabase = client ?? createClient();
  }

  async getPricingPlan(facilityId: string): Promise<PricingPlan | null> {
    const { data: plan, error: planError } = await this.supabase
      .from("pricing_plans")
      .select("*")
      .eq("facility_id", facilityId)
      .eq("status", "ACTIVE")
      .maybeSingle();

    if (planError) throw mapSupabaseError(planError);
    if (!plan) return null;

    const { data: rules, error: rulesError } = await this.supabase
      .from("pricing_rules")
      .select("*")
      .eq("pricing_plan_id", plan.id)
      .eq("is_active", true);

    if (rulesError) throw mapSupabaseError(rulesError);

    return this.toPlan(plan, (rules ?? []).map(toRule));
  }

  async savePricingRules(facilityId: string, rules: PricingRule[]): Promise<PricingPlan> {
    const result = validatePricingRules(rules);
    if (!result.isValid) {
      throw new ServiceError("INVALID_PLAYING_AREA", result.overlapError ?? result.ruleErrors[0] ?? "Invalid pricing.");
    }

    const { data, error } = await this.supabase.rpc("save_pricing_rules", {
      p_facility_id: facilityId,
      p_plan_name: "Standard Pricing",
      p_rules: rules.map(toRulePayload),
    });

    if (error) throw mapSupabaseError(error, { invalid: "INVALID_PLAYING_AREA" });
    if (!data) throw new ServiceError("DATABASE_ERROR");

    const plan = await this.getPricingPlan(facilityId);
    if (!plan) throw new ServiceError("DATABASE_ERROR");
    return plan;
  }

  async deletePricingRule(ruleId: string): Promise<void> {
    const { error } = await this.supabase.from("pricing_rules").update({ is_active: false }).eq("id", ruleId);
    if (error) throw mapSupabaseError(error);
  }

  async resolvePrice(
    facilityId: string,
    facilitySportId: string,
    playingAreaId: string | null,
    date: Date,
    time: string,
  ): Promise<PricingRule | null> {
    const plan = await this.getPricingPlan(facilityId);
    if (!plan) return null;
    return resolvePriceUtil(plan.rules, facilitySportId, playingAreaId, date, time);
  }

  private toPlan(row: PlanRow, rules: PricingRule[]): PricingPlan {
    return {
      id: row.id,
      facilityId: row.facility_id,
      name: row.name,
      currency: row.currency,
      status: row.status,
      rules,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }
}