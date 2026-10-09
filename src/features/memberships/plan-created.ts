import type { MembershipPlan } from "@/features/memberships/types";

/** What the plan costs a new member up front: its price plus any joining fee and security deposit. */
export function planTotalAmountInr(plan: Pick<MembershipPlan, "priceInr" | "joiningFeeInr" | "securityDepositInr">): number {
  return plan.priceInr + (plan.joiningFeeInr ?? 0) + (plan.securityDepositInr ?? 0);
}

/** "Regular Membership" → "Regular Plan"; any other category is shown as it is. */
export function planCategoryLabel(category: string | null): string | null {
  const c = category?.trim();
  if (!c) return null;
  return c.replace(/\s+Membership$/i, " Plan");
}

/** "Regular Plan • Badminton" — whichever parts exist. */
export function planSubtitle(category: string | null, sport: string | null): string {
  return [planCategoryLabel(category), sport?.trim() || null].filter(Boolean).join(" • ");
}

/** "6 features" / "1 feature". */
export function featureCountLabel(count: number): string {
  return `${count} ${count === 1 ? "feature" : "features"}`;
}
