import type { MembershipBatch } from "@/features/membership-sessions/types";
import type { MemberScheduleRow, MembershipListRow, MembershipPlan } from "@/features/memberships/types";

/**
 * Every Membership v1 page is scoped to the sports ticked in the top bar's sport picker (see `useSportFilter`):
 * All Sports shows everything; ticking Badminton and Cricket shows just those two sports' members, plans and
 * courts. A scope is one sport id, a set of them, or `null` — nothing to filter by (All Sports, or the sport list
 * not loaded yet) — in which case every function here passes its input through unchanged rather than hiding anything.
 */
export type SportScope = string | ReadonlySet<string> | null;

function toSet(scope: SportScope): ReadonlySet<string> | null {
  if (scope === null) return null;
  return typeof scope === "string" ? (scope ? new Set([scope]) : null) : scope;
}

/** Only the courts of the sports in scope. */
export function courtsForSport<T extends { facilitySportId: string }>(courts: T[], scope: SportScope): T[] {
  const sports = toSet(scope);
  return sports ? courts.filter((c) => sports.has(c.facilitySportId)) : courts;
}

/** The ids of every plan that has at least one Court Access time window (batch) on the given
 *  sport. Doesn't say anything about a plan with zero batches at all — see `planIdsOnOtherSportOnly`
 *  below for how those are treated when filtering. */
export function planIdsForSport(batches: MembershipBatch[], scope: SportScope): Set<string> | null {
  const sports = toSet(scope);
  if (!sports) return null;
  return new Set(batches.filter((b) => sports.has(b.facilitySportId) && b.planId).map((b) => b.planId!));
}

/** The ids of plans that should be hidden while `sportId` is active: plans that have at least one
 *  batch, all of them on some *other* sport. A plan with no batches at all is deliberately NOT
 *  included here — batches are the only place a plan's sport is currently tracked (the
 *  `membership_plans` table has no sport column of its own), but a plan routinely has real,
 *  paying members before any Court Access time window is ever set up for it (the Add Member
 *  wizard's playing-schedule step is optional). Treating "no batches yet" the same as "wrong
 *  sport" hid those members/plans from every Membership v1 page the moment a sport filter was
 *  active, instead of just narrowing to genuinely cross-sport plans. */
function planIdsOnOtherSportOnly(batches: MembershipBatch[], inScope: ReadonlySet<string>): Set<string> {
  const sportsByPlan = new Map<string, Set<string>>();
  for (const b of batches) {
    if (!b.planId) continue;
    const sports = sportsByPlan.get(b.planId) ?? new Set<string>();
    sports.add(b.facilitySportId);
    sportsByPlan.set(b.planId, sports);
  }
  const excluded = new Set<string>();
  for (const [planId, sports] of sportsByPlan) {
    if (![...sports].some((id) => inScope.has(id))) excluded.add(planId);
  }
  return excluded;
}

export function plansForSport(plans: MembershipPlan[], batches: MembershipBatch[], scope: SportScope): MembershipPlan[] {
  const sports = toSet(scope);
  if (!sports) return plans;
  const excluded = planIdsOnOtherSportOnly(batches, sports);
  return plans.filter((p) => !excluded.has(p.id));
}

/** Membership rows (a member's plan enrolment) whose plan isn't clearly tied to a different sport. */
export function membershipRowsForSport(rows: MembershipListRow[], batches: MembershipBatch[], scope: SportScope): MembershipListRow[] {
  const sports = toSet(scope);
  if (!sports) return rows;
  const excluded = planIdsOnOtherSportOnly(batches, sports);
  return rows.filter((r) => !excluded.has(r.planId));
}

/** `list_member_schedules` rows already carry their own batch's `facilitySportId` directly, so
 *  this doesn't need the batches list the plan/membership filters above do. */
export function scheduleRowsForSport(rows: MemberScheduleRow[], scope: SportScope): MemberScheduleRow[] {
  const sports = toSet(scope);
  return sports ? rows.filter((r) => sports.has(r.facilitySportId)) : rows;
}
