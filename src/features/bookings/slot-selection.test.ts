import { describe, expect, it } from "vitest";
import { hoursBetween, mergeRuns, toggleSlot } from "@/features/bookings/slot-selection";
import type { TimeSlot } from "@/features/bookings/types";

const at = (h: number) => new Date(2026, 9, 20, h).toISOString();
const slot = (h: number): TimeSlot => ({ startTime: at(h), endTime: at(h + 1), available: true });

describe("toggleSlot", () => {
  it("adds, keeps time order, and removes on a second pick", () => {
    let sel = toggleSlot([], slot(19));
    sel = toggleSlot(sel, slot(18));
    expect(sel.map((s) => s.startTime)).toEqual([at(18), at(19)]);
    expect(toggleSlot(sel, slot(18)).map((s) => s.startTime)).toEqual([at(19)]);
  });
});

describe("mergeRuns", () => {
  it("joins back-to-back slots into one booking", () => {
    const runs = mergeRuns([slot(19), slot(18), slot(20)]);
    expect(runs).toHaveLength(1);
    expect(runs[0]).toMatchObject({ startTime: at(18), endTime: at(21) });
    expect(hoursBetween(runs[0]!.startTime, runs[0]!.endTime)).toBe(3);
  });
  it("splits at a gap", () => {
    const runs = mergeRuns([slot(18), slot(19), slot(21)]);
    expect(runs.map((r) => [r.startTime, r.endTime])).toEqual([
      [at(18), at(20)],
      [at(21), at(22)],
    ]);
  });
  it("is empty for no selection", () => expect(mergeRuns([])).toEqual([]));
});
