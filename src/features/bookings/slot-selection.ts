import type { TimeSlot } from "@/features/bookings/types";

/** Adds the slot to the selection, or removes it if it is already there. Kept in time order. */
export function toggleSlot(selected: TimeSlot[], slot: TimeSlot): TimeSlot[] {
  if (selected.some((s) => s.startTime === slot.startTime)) return selected.filter((s) => s.startTime !== slot.startTime);
  return [...selected, slot].sort((a, b) => new Date(a.startTime).getTime() - new Date(b.startTime).getTime());
}

/** One booking's worth of time: back-to-back selected slots joined into a single range. */
export interface SlotRun {
  startTime: string;
  endTime: string;
  /** The selected slots inside this range, in order. */
  slots: TimeSlot[];
}

/**
 * Groups the selection into bookings: slots that touch (one ends exactly when the next starts) become one
 * continuous booking, so 6–7 + 7–8 is one 6–8 booking; a gap starts another. Input order does not matter.
 */
export function mergeRuns(selected: TimeSlot[]): SlotRun[] {
  const sorted = [...selected].sort((a, b) => new Date(a.startTime).getTime() - new Date(b.startTime).getTime());
  const runs: SlotRun[] = [];
  for (const s of sorted) {
    const last = runs[runs.length - 1];
    if (last && new Date(last.endTime).getTime() === new Date(s.startTime).getTime()) {
      last.endTime = s.endTime;
      last.slots.push(s);
    } else {
      runs.push({ startTime: s.startTime, endTime: s.endTime, slots: [s] });
    }
  }
  return runs;
}

/** Hours in a time range. */
export function hoursBetween(startIso: string, endIso: string): number {
  return (new Date(endIso).getTime() - new Date(startIso).getTime()) / 3_600_000;
}
