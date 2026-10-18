import { describe, expect, it } from "vitest";
import { advanceMinor, advanceSummary, needsAdvance } from "@/features/bookings/advance-payment";

const at = (h: number, m = 0) => new Date(2026, 9, 20, h, m).toISOString();

describe("needsAdvance", () => {
  it("is false for an hour or less and true for anything longer", () => {
    expect(needsAdvance(at(18), at(19))).toBe(false);
    expect(needsAdvance(at(18), at(18, 30))).toBe(false);
    expect(needsAdvance(at(18), at(19, 30))).toBe(true);
    expect(needsAdvance(at(18), at(22))).toBe(true);
  });
});

describe("advanceMinor", () => {
  it("is half the total: 4 hours at 300 → 600 of 1200", () => {
    expect(advanceMinor(120000)).toBe(60000);
  });
  it("rounds an odd amount up", () => {
    expect(advanceMinor(10001)).toBe(5001);
  });
});

describe("advanceSummary", () => {
  it("is not required when every booking is an hour or less", () => {
    expect(advanceSummary([{ startTime: at(18), endTime: at(19), totalMinor: 30000 }]).required).toBe(false);
  });
  it("splits a long booking into advance now and balance later", () => {
    expect(advanceSummary([{ startTime: at(18), endTime: at(22), totalMinor: 120000 }])).toEqual({
      required: true,
      dueNowMinor: 60000,
      balanceMinor: 60000,
      longCount: 1,
    });
  });
  it("only takes an advance on the long bookings; the short ones are all balance", () => {
    const r = advanceSummary([
      { startTime: at(18), endTime: at(20), totalMinor: 60000 },
      { startTime: at(7), endTime: at(8), totalMinor: 30000 },
    ]);
    expect(r).toEqual({ required: true, dueNowMinor: 30000, balanceMinor: 60000, longCount: 1 });
  });
  it("has no amounts while a long booking is unpriced", () => {
    expect(advanceSummary([{ startTime: at(18), endTime: at(20), totalMinor: null }])).toEqual({ required: true, dueNowMinor: null, balanceMinor: null, longCount: 1 });
  });
});
