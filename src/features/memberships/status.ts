/**
 * Single source of truth for "is this membership active / expiring / expired"
 * on the web. Never re-derive this in a component or in SQL — status is a
 * function of (raw DB status, end_date, now), computed here once.
 */
export type MembershipDisplayStatus = "ACTIVE" | "EXPIRING_SOON" | "EXPIRED" | "CANCELLED" | "NO_MEMBERSHIP";

export const EXPIRING_SOON_DAYS = 7;

/** A member is a facility customer record independent of any membership — passing `null` (never assigned a plan) is a normal, valid input, not an error case. */
export function computeMembershipStatus(
  membership: { status: string; endDate: string } | null,
  now: Date = new Date(),
): MembershipDisplayStatus {
  if (!membership) return "NO_MEMBERSHIP";
  if (membership.status === "cancelled") return "CANCELLED";

  const end = new Date(membership.endDate);
  end.setHours(23, 59, 59, 999);
  const daysRemaining = Math.ceil((end.getTime() - now.getTime()) / (1000 * 60 * 60 * 24));

  if (daysRemaining < 0) return "EXPIRED";
  if (daysRemaining <= EXPIRING_SOON_DAYS) return "EXPIRING_SOON";
  return "ACTIVE";
}

export function daysUntilExpiry(endDate: string, now: Date = new Date()): number {
  const end = new Date(endDate);
  end.setHours(23, 59, 59, 999);
  return Math.ceil((end.getTime() - now.getTime()) / (1000 * 60 * 60 * 24));
}

export function computeMembershipEndDate(startDate: string, durationDays: number): string {
  const start = new Date(startDate);
  start.setDate(start.getDate() + durationDays);
  return start.toISOString().slice(0, 10);
}