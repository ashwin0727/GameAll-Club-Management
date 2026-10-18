import type { MembershipBatch } from "@/features/membership-sessions/types";

/**
 * One court/day/time slot a plan reserves. A plan's slots are fixed when the plan is created
 * (Court Access step), so a member joining the plan gets exactly these — nothing to pick.
 */
export interface PlanSlot {
  batchId: string;
  courtId: string;
  courtName: string;
  /** 0=Sunday..6=Saturday. */
  daysOfWeek: number[];
  /** "HH:MM" (any seconds suffix from Postgres is dropped). */
  startTime: string;
  endTime: string;
}

/** The plan's active slots, ordered by court then start time. Empty when the plan reserves none. */
export function planSlotsFor(batches: MembershipBatch[], planId: string, courtNames: ReadonlyMap<string, string>): PlanSlot[] {
  if (!planId) return [];
  return batches
    .filter((b) => b.isActive && b.planId === planId)
    .map((b) => ({
      batchId: b.id,
      courtId: b.courtId,
      courtName: courtNames.get(b.courtId) ?? "Court",
      daysOfWeek: [...b.daysOfWeek].sort((a, c) => a - c),
      startTime: b.startTime.slice(0, 5),
      endTime: b.endTime.slice(0, 5),
    }))
    .sort((a, b) => a.courtName.localeCompare(b.courtName) || a.startTime.localeCompare(b.startTime));
}

/** The distinct courts a plan's slots are on, in slot order. */
export function courtsOf(slots: PlanSlot[]): { courtId: string; courtName: string }[] {
  const seen = new Map<string, string>();
  for (const sl of slots) if (!seen.has(sl.courtId)) seen.set(sl.courtId, sl.courtName);
  return [...seen].map(([courtId, courtName]) => ({ courtId, courtName }));
}

/**
 * A member plays on ONE court at a time. When the plan spans several courts the member picks one, and
 * gets only that court's slots; a single-court plan needs no choice. Until a court is picked on a
 * multi-court plan this returns no slots.
 */
export function slotsForChosenCourt(slots: PlanSlot[], chosenCourtId: string): PlanSlot[] {
  if (courtsOf(slots).length <= 1) return slots;
  return slots.filter((sl) => sl.courtId === chosenCourtId);
}
