import type { BillingInterval, PlanOption, PlanSnapshot } from "@/features/plans/types";

export const AUTOPAY_FEATURE = "AUTOPAY";

type Row = Record<string, unknown>;

export function toPlanOption(r: Row): PlanOption {
  return {
    code: r.code as string,
    name: r.name as string,
    description: (r.description as string | null) ?? null,
    monthlyMinor: Number(r.monthly_minor),
    yearlyMinor: Number(r.yearly_minor),
    currency: (r.currency as string) ?? "INR",
    maxCourts: r.max_courts == null ? null : Number(r.max_courts),
    maxStaff: r.max_staff == null ? null : Number(r.max_staff),
    featureFlags: (r.feature_flags as string[] | null) ?? [],
    features: (r.features as string[] | null) ?? [],
    isPopular: Boolean(r.is_popular),
    trialDays: Number(r.trial_days ?? 0),
    pageKeys: (r.page_keys as string[] | null) ?? [],
  };
}

export function toPlanSnapshot(r: Row | null | undefined): PlanSnapshot | null {
  if (!r) return null;
  return {
    planCode: r.planCode as string,
    effectiveCode: r.effectiveCode as string,
    name: (r.name as string) ?? "",
    status: r.status as PlanSnapshot["status"],
    interval: r.interval as BillingInterval,
    priceMinor: Number(r.priceMinor ?? 0),
    validTill: r.validTill as string,
    onTrial: Boolean(r.onTrial),
    lapsed: Boolean(r.lapsed),
    daysLeft: Number(r.daysLeft ?? 0),
    maxCourts: r.maxCourts == null ? null : Number(r.maxCourts),
    maxStaff: r.maxStaff == null ? null : Number(r.maxStaff),
    features: (r.features as string[] | null) ?? [],
    pageKeys: (r.pageKeys as string[] | null) ?? [],
  };
}

/** Whether the club's plan includes the page. A club with no plan is unrestricted. */
export function planIncludesPage(plan: PlanSnapshot | null, page: string): boolean {
  return plan === null || plan.pageKeys.includes(page);
}

export function planHasFeature(plan: PlanSnapshot | null, feature: string): boolean {
  return plan === null || plan.features.includes(feature);
}

export function priceFor(plan: PlanOption, interval: BillingInterval): number {
  return interval === "year" ? plan.yearlyMinor : plan.monthlyMinor;
}

/** Whole months of the monthly price saved by paying yearly (e.g. ₹1,299 vs 12 × ₹129 → 2.4 months free). */
export function yearlySavingMinor(plan: PlanOption): number {
  return Math.max(0, plan.monthlyMinor * 12 - plan.yearlyMinor);
}

/** "₹1,299" — whole rupees when there are no paise. */
export function formatRupees(minor: number): string {
  const rupees = minor / 100;
  return `₹${rupees.toLocaleString("en-IN", { minimumFractionDigits: Number.isInteger(rupees) ? 0 : 2, maximumFractionDigits: 2 })}`;
}

export function limitLabel(n: number | null, noun: string): string {
  return n === null ? `Unlimited ${noun}` : `Up to ${n} ${noun}`;
}

/** The one-line status for the banner; null when nothing needs saying. */
export function planNotice(plan: PlanSnapshot | null): { tone: "info" | "warn"; text: string } | null {
  if (!plan) return { tone: "info", text: "Choose a plan to unlock your club's features." };
  if (plan.lapsed) {
    return { tone: "warn", text: `Your ${plan.name} plan has ended. You are on Basic until you renew.` };
  }
  if (plan.onTrial) {
    const d = plan.daysLeft;
    return {
      tone: d <= 3 ? "warn" : "info",
      text: d <= 0 ? `Your free trial ends today.` : `${d} day${d === 1 ? "" : "s"} left in your free ${plan.name} trial.`,
    };
  }
  return null;
}
