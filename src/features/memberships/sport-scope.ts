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

/** The ids of every plan that has at least one Court Access time window (batch) on the given
 *  sport. Doesn't say anything about a plan with zero batches at all — see `planIdsOnOtherSportOnly`
 *  below for how those are treated when filtering. */
export function planIdsForSport(batches: MembershipBatch[], sportId: string | null): Set<string> | null {
  if (!sportId) return null;
  return new Set(batches.filter((b) => b.facilitySportId === sportId && b.planId).map((b) => b.planId!));
}

/** The ids of plans that should be hidden while `sportId` is active: plans that have at least one
 *  batch, all of them on some *other* sport. A plan with no batches at all is deliberately NOT
 *  included here — batches are the only place a plan's sport is currently tracked (the
 *  `membership_plans` table has no sport column of its own), but a plan routinely has real,
 *  paying members before any Court Access time window is ever set up for it (the Add Member
 *  wizard's playing-schedule step is optional). Treating "no batches yet" the same as "wrong
 *  sport" hid those members/plans from every Membership v1 page the moment a sport filter was
 *  active, instead of just narrowing to genuinely cross-sport plans. */
function planIdsOnOtherSportOnly(batches: MembershipBatch[], sportId: string): Set<string> {
  const sportsByPlan = new Map<string, Set<string>>();
  for (const b of batches) {
    if (!b.planId) continue;
    const sports = sportsByPlan.get(b.planId) ?? new Set<string>();
    sports.add(b.facilitySportId);
    sportsByPlan.set(b.planId, sports);
  }
  const excluded = new Set<string>();
  for (const [planId, sports] of sportsByPlan) {
    if (!sports.has(sportId)) excluded.add(planId);
  }
  return excluded;
}

export function plansForSport(plans: MembershipPlan[], batches: MembershipBatch[], sportId: string | null): MembershipPlan[] {
  if (!sportId) return plans;
  const excluded = planIdsOnOtherSportOnly(batches, sportId);
  return plans.filter((p) => !excluded.has(p.id));
}

/** Membership rows (a member's plan enrolment) whose plan isn't clearly tied to a different sport. */
export function membershipRowsForSport(rows: MembershipListRow[], batches: MembershipBatch[], sportId: string | null): MembershipListRow[] {
  if (!sportId) return rows;
  const excluded = planIdsOnOtherSportOnly(batches, sportId);
  return rows.filter((r) => !excluded.has(r.planId));
}

/** `list_member_schedules` rows already carry their own batch's `facilitySportId` directly, so
 *  this doesn't need the batches list the plan/membership filters above do. */
export function scheduleRowsForSport(rows: MemberScheduleRow[], sportId: string | null): MemberScheduleRow[] {
  return sportId ? rows.filter((r) => r.facilitySportId === sportId) : rows;
}
