import { formatSlot } from "@/features/memberships/slot-format";
import type { AssignableBatch } from "@/features/memberships/types";

export const ALL_DAYS = [0, 1, 2, 3, 4, 5, 6];
export const WEEKDAYS = [1, 2, 3, 4, 5];

export const DAY_OPTIONS: { value: number; label: string }[] = [
  { value: 1, label: "Mon" },
  { value: 2, label: "Tue" },
  { value: 3, label: "Wed" },
  { value: 4, label: "Thu" },
  { value: 5, label: "Fri" },
  { value: 6, label: "Sat" },
  { value: 0, label: "Sun" },
];

export interface NewSlotDraft {
  facilitySportId: string;
  courtId: string;
  daysOfWeek: number[];
  startTime: string;
  endTime: string;
  capacity: string;
}

export type SlotSelection =
  | { kind: "none" }
  | { kind: "existing"; batchId: string }
  | { kind: "new"; draft: NewSlotDraft };

export function sameDays(a: number[], b: number[]): boolean {
  if (a.length !== b.length) return false;
  const sa = [...a].sort((x, y) => x - y);
  const sb = [...b].sort((x, y) => x - y);
  return sa.every((v, i) => v === sb[i]);
}

export function validateSlotSelection(sel: SlotSelection): string | null {
  if (sel.kind === "none") return null;
  if (sel.kind === "existing") {
    return sel.batchId ? null : "Pick a time slot or clear the court.";
  }
  const d = sel.draft;
  if (!d.courtId) return "Select a court for the time slot.";
  if (d.daysOfWeek.length === 0) return "Select at least one day for the time slot.";
  if (!d.startTime || !d.endTime || d.endTime <= d.startTime) {
    return "Time slot end must be after the start.";
  }
  const cap = Number(d.capacity);
  if (!Number.isInteger(cap) || cap < 1) return "Enter a time slot capacity of at least 1.";
  return null;
}

export function describeBatchOption(b: AssignableBatch): string {
  return `${formatSlot(b.daysOfWeek, b.startTime, b.endTime)} · ${b.enrolledCount} / ${b.capacity}`;
}

export function toNewBatchPayload(draft: NewSlotDraft) {
  return {
    courtId: draft.courtId,
    facilitySportId: draft.facilitySportId,
    daysOfWeek: draft.daysOfWeek,
    startTime: draft.startTime,
    endTime: draft.endTime,
    capacity: Number(draft.capacity),
  };
}