import { addDays, format, parseISO } from "date-fns";
import type { MembershipListRow, MembershipPlan } from "@/features/memberships/types";

export type PlanBand = "Monthly" | "3 Months" | "6 Months" | "1 Year" | "Others";

export const PLAN_BAND_ORDER: PlanBand[] = ["Monthly", "3 Months", "6 Months", "1 Year", "Others"];

/** Bands a plan by how long it runs, so cards and pills can colour-code consistently. */
export function planBand(durationDays: number): PlanBand {
  if (durationDays <= 35) return "Monthly";
  if (durationDays <= 100) return "3 Months";
  if (durationDays <= 200) return "6 Months";
  if (durationDays <= 400) return "1 Year";
  return "Others";
}

/** "1 Month" / "3 Months" / "12 Months" — the plan's length in whole months, as the table shows it. */
export function durationLabel(durationDays: number): string {
  const months = Math.max(1, Math.round(durationDays / 30));
  return months === 1 ? "1 Month" : `${months} Months`;
}

/** What a plan works out to per month, for comparing a yearly price against a monthly one. */
export function monthlyEquivalentInr(priceInr: number, durationDays: number): number {
  const months = Math.max(1, Math.round(durationDays / 30));
  return Math.round(priceInr / months);
}

const TAGLINES: Record<PlanBand, string> = {
  Monthly: "Perfect for regular players",
  "3 Months": "Great for consistent players",
  "6 Months": "Ideal for committed players",
  "1 Year": "Best for long-term players",
  Others: "Flexible membership",
};

export function planTagline(durationDays: number): string {
  return TAGLINES[planBand(durationDays)];
}

/** "every month" / "every 3 months" — how a RECURRING plan's billing interval reads inline. */
export function billingIntervalLabel(durationDays: number): string {
  const months = Math.max(1, Math.round(durationDays / 30));
  return months === 1 ? "every month" : `every ${months} months`;
}

/**
 * What a plan card lists. A plan's own saved features win; otherwise the default describes what
 * that plan TYPE means for the member — different for a fixed-length plan than for one that
 * bills on a recurring cycle, since "Valid for 3 months" would be actively wrong on a plan that
 * has no final expiry while it's active.
 */
export function planFeatures(plan: MembershipPlan): string[] {
  if (plan.features.length > 0) return plan.features;
  if (plan.planType === "RECURRING") {
    return [`Auto-renews ${billingIntervalLabel(plan.durationDays)}`, "Recurring payment", "Continuous membership", "Cancel anytime"];
  }
  return ["Fixed membership period", "One-time payment", "Valid until expiry", "Manual renewal required"];
}

/**
 * Splits a trailing bracketed qualifier off a plan's name, so a name like
 * "Batch 1(5 A.M to 6 A.M)" can be shown as "Batch 1" with "(5 A.M to 6 A.M)" on its own line
 * rather than being squashed or clipped on one.
 */
export function splitPlanName(name: string): { main: string; detail: string | null } {
  const match = name.trim().match(/^(.*\S)\s*(\([^()]*\))$/);
  if (!match) return { main: name.trim(), detail: null };
  return { main: match[1]!.trim(), detail: match[2]! };
}

/** How many memberships are on each plan, keyed by plan id. */
export function memberCountByPlan(rows: MembershipListRow[]): Map<string, number> {
  const counts = new Map<string, number>();
  for (const row of rows) counts.set(row.planId, (counts.get(row.planId) ?? 0) + 1);
  return counts;
}

export interface PlanStats {
  totalPlans: number;
  activePlans: number;
  totalMembers: number;
  /** What the current roster bills per month, each plan's price spread over its length. */
  monthlyRevenueEstInr: number;
}

export function planStats(plans: MembershipPlan[], rows: MembershipListRow[]): PlanStats {
  const counts = memberCountByPlan(rows);
  const monthlyRevenueEstInr = plans.reduce(
    (sum, p) => sum + monthlyEquivalentInr(p.priceInr, p.durationDays) * (counts.get(p.id) ?? 0),
    0,
  );
  return {
    totalPlans: plans.length,
    activePlans: plans.filter((p) => p.isActive).length,
    totalMembers: new Set(rows.map((r) => r.memberId)).size,
    monthlyRevenueEstInr,
  };
}

export type PlanBadge = "Most Popular" | "Best Value";

/**
 * The two call-outs in the design: "Most Popular" goes to the plan the most members are on,
 * and "Best Value" to the plan with the lowest cost per month — skipping that one if it's
 * already the most popular, so a single plan never carries both. A plan's own `badgeText` (set
 * via the Create Plan wizard's "Show badge" toggle) always wins over either computed one.
 */
export function planBadges(plans: MembershipPlan[], rows: MembershipListRow[]): Map<string, PlanBadge | string> {
  const badges = new Map<string, PlanBadge | string>();
  const active = plans.filter((p) => p.isActive);
  if (active.length === 0) return badges;

  for (const p of active) {
    if (p.badgeText) badges.set(p.id, p.badgeText);
  }

  const counts = memberCountByPlan(rows);
  const popular = [...active].sort(
    (a, b) => (counts.get(b.id) ?? 0) - (counts.get(a.id) ?? 0) || a.name.localeCompare(b.name),
  )[0]!;
  if (!badges.has(popular.id) && (counts.get(popular.id) ?? 0) > 0) badges.set(popular.id, "Most Popular");

  const cheapest = [...active].sort(
    (a, b) =>
      monthlyEquivalentInr(a.priceInr, a.durationDays) - monthlyEquivalentInr(b.priceInr, b.durationDays) ||
      a.name.localeCompare(b.name),
  )[0]!;
  if (!badges.has(cheapest.id)) badges.set(cheapest.id, "Best Value");

  return badges;
}

// ─────────────────────────────────────────────────────────────────────────
// RECURRING billing-period math. Plain day-count arithmetic — the same
// approach create_membership_full already uses for a TIME_BASED plan's own
// end_date (`computed_end := p_start_date + p_duration_days`), which is why
// this needs no special-casing for 28/29/30/31-day months or leap years:
// "add N days" has one unambiguous answer regardless of what falls in
// between, unlike "add N calendar months" (which has to decide what
// "31 Jan + 1 month" even means).
// ─────────────────────────────────────────────────────────────────────────

/** The date the next charge is due — `startDateIso` plus the billing interval, in days. */
export function nextBillingDate(startDateIso: string, billingIntervalDays: number): string {
  return format(addDays(parseISO(startDateIso), billingIntervalDays), "yyyy-MM-dd");
}

/** The [start, end] of the billing period that begins on `startDateIso` — end is inclusive. */
export function currentBillingPeriod(startDateIso: string, billingIntervalDays: number): { start: string; end: string } {
  return { start: startDateIso, end: format(addDays(parseISO(startDateIso), billingIntervalDays - 1), "yyyy-MM-dd") };
}
