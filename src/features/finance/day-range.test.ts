import { describe, expect, it } from "vitest";
import { currentMonthRange, fillTrendBuckets, isCurrentMonth } from "@/features/finance/day-range";

const zero = (date: string) => ({ date, v: 0 });

describe("currentMonthRange", () => {
  it("is the first to the last day of the month", () => {
    expect(currentMonthRange(new Date(2026, 1, 10))).toEqual({ from: "2026-02-01", to: "2026-02-28" });
    expect(currentMonthRange(new Date(2026, 9, 19))).toEqual({ from: "2026-10-01", to: "2026-10-31" });
    expect(isCurrentMonth({ from: "2026-10-01", to: "2026-10-31" }, new Date(2026, 9, 19))).toBe(true);
    expect(isCurrentMonth({ from: "2026-10-01", to: "2026-10-15" }, new Date(2026, 9, 19))).toBe(false);
  });
});

describe("fillTrendBuckets", () => {
  it("adds every quiet day inside the chosen dates as zero and keeps the days that had activity", () => {
    const out = fillTrendBuckets([{ date: "2026-10-12", v: 500 }, { date: "2026-10-14", v: 900 }], { from: "2026-10-11", to: "2026-10-15" }, "daily", zero);
    expect(out.map((p) => p.date)).toEqual(["2026-10-11", "2026-10-12", "2026-10-13", "2026-10-14", "2026-10-15"]);
    expect(out.map((p) => p.v)).toEqual([0, 500, 0, 900, 0]);
  });

  it("weekly buckets are named by their Monday", () => {
    const out = fillTrendBuckets([{ date: "2026-10-12", v: 7 }], { from: "2026-10-01", to: "2026-10-20" }, "weekly", zero);
    expect(out.map((p) => p.date)).toEqual(["2026-09-28", "2026-10-05", "2026-10-12", "2026-10-19"]);
    expect(out.find((p) => p.date === "2026-10-12")?.v).toBe(7);
  });

  it("monthly buckets are named by the 1st", () => {
    const out = fillTrendBuckets([], { from: "2026-08-15", to: "2026-10-02" }, "monthly", zero);
    expect(out.map((p) => p.date)).toEqual(["2026-08-01", "2026-09-01", "2026-10-01"]);
  });

  it("leaves the data alone for an invalid range", () => {
    const pts = [{ date: "2026-10-12", v: 1 }];
    expect(fillTrendBuckets(pts, { from: "2026-10-20", to: "2026-10-01" }, "daily", zero)).toBe(pts);
  });
});
