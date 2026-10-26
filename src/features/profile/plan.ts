import type { FacilityPlan, NotificationPrefs, PlanInterval } from "@/features/profile/types";

export const INTERVAL_LABEL: Record<PlanInterval, string> = { month: "month", quarter: "quarter", year: "year" };

/** Local today as yyyy-mm-dd — the plan's valid-till date is a plain calendar date, not an instant. */
export function todayIso(now: Date = new Date()): string {
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  return `${now.getFullYear()}-${m}-${d}`;
}

/** Active (paid or in its free trial) only while the plan has not been cancelled and its last covered day has not passed. */
export function isPlanActive(plan: Pick<FacilityPlan, "status" | "validTill"> | null, today: string = todayIso()): boolean {
  if (!plan) return false;
  return (plan.status === "active" || plan.status === "trialing") && plan.validTill >= today;
}

/** True during the free trial: the plan is chosen and authorised, the first payment is still ahead. */
export function isPlanTrial(plan: Pick<FacilityPlan, "status" | "validTill"> | null, today: string = todayIso()): boolean {
  return !!plan && plan.status === "trialing" && plan.validTill >= today;
}

/** Whole days until (and including) the valid-till date; negative once it has passed. */
export function daysLeft(validTill: string, today: string = todayIso()): number {
  const a = Date.parse(`${today}T00:00:00Z`);
  const b = Date.parse(`${validTill}T00:00:00Z`);
  return Math.round((b - a) / 86_400_000);
}

/** "31 Dec 2026". */
export function formatPlanDate(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  return `${d} ${months[(m ?? 1) - 1]} ${y}`;
}

export const DEFAULT_NOTIFICATION_PREFS: NotificationPrefs = {
  bookings: true,
  payments: true,
  memberships: true,
  reports: false,
};
