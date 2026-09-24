import type { MembershipBatch } from "@/features/membership-sessions/types";
import type { MemberScheduleRow, MembershipListRow, MembershipPlan } from "@/features/memberships/types";

/**
 * Every Membership v1 page is scoped to whichever sport the top bar's Sport picker has active
 * (see `useActiveFacilitySportId`) — a facility with both Badminton and Cricket (Turf) shows only
 * one sport's members/plans/courts at a time, switching sport is how you see the other one's.
 * `sportId` is null only when there's nothing to filter by yet (sport list not loaded), in which
 * case every function here passes its input through unchanged rather than hiding everything.
 */

/** Only the active sport's courts. */
export function courtsForSport<T extends { facilitySportId: string }>(courts: T[], sportId: string | null): T[] {
  return sportId ? courts.filter((c) => c.facilitySportId === sportId) : courts;
}

/** The ids of every plan that has at least one Court Access time window (batch) on the active
 *  sport — a plan with no batches at all (still mid-creation) belongs to no sport, so it drops
 *  out once a filter is active, same as it would show no courts in Court Access either. */
export function planIdsForSport(batches: MembershipBatch[], sportId: string | null): Set<string> | null {
  if (!sportId) return null;
  return new Set(batches.filter((b) => b.facilitySportId === sportId && b.planId).map((b) => b.planId!));
}

export function plansForSport(plans: MembershipPlan[], batches: MembershipBatch[], sportId: string | null): MembershipPlan[] {
  const ids = planIdsForSport(batches, sportId);
  return ids ? plans.filter((p) => ids.has(p.id)) : plans;
}

/** Membership rows (a member's plan enrolment) whose plan belongs to the active sport. */
export function membershipRowsForSport(rows: MembershipListRow[], batches: MembershipBatch[], sportId: string | null): MembershipListRow[] {
  const ids = planIdsForSport(batches, sportId);
  return ids ? rows.filter((r) => ids.has(r.planId)) : rows;
}

/** `list_member_schedules` rows already carry their own batch's `facilitySportId` directly, so
 *  this doesn't need the batches list the plan/membership filters above do. */
export function scheduleRowsForSport(rows: MemberScheduleRow[], sportId: string | null): MemberScheduleRow[] {
  return sportId ? rows.filter((r) => r.facilitySportId === sportId) : rows;
}
