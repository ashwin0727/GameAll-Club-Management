import { describe, expect, it } from "vitest";
import { monthStartIso, revenueOverMonths, todayIso } from "@/features/memberships/revenue-window";

const NOW = new Date(2026, 9, 17); // 17 Oct 2026

describe("monthStartIso / todayIso", () => {
  it("goes back whole calendar months, across a year end", () => {
    expect(monthStartIso(NOW, 0)).toBe("2026-10-01");
    expect(monthStartIso(NOW, 2)).toBe("2026-08-01");
    expect(monthStartIso(NOW, 5)).toBe("2026-05-01");
    expect(monthStartIso(new Date(2026, 1, 10), 3)).toBe("2025-11-01");
  });
  it("formats today", () => expect(todayIso(NOW)).toBe("2026-10-17"));
});

describe("revenueOverMonths", () => {
  const points = [
    { bucket: "2026-05-10T00:00:00Z", amountInr: 100 },
    { bucket: "2026-07-31T00:00:00Z", amountInr: 200 },
    { bucket: "2026-08-01T00:00:00Z", amountInr: 300 },
    { bucket: "2026-09-15T00:00:00Z", amountInr: 400 },
    { bucket: "2026-10-05T00:00:00Z", amountInr: 500 },
  ];
  it("totals the last three months (Aug, Sep, Oct) and compares with May–Jul", () => {
    const r = revenueOverMonths(points, NOW, 3);
    expect(r.total).toBe(1200);
    expect(r.previous).toBe(300);
    expect(r.changePct).toBe(300);
    expect(r.current).toHaveLength(3);
  });
  it("has no percentage when there was nothing before", () => {
    expect(revenueOverMonths(points.slice(2), NOW, 3).changePct).toBeNull();
  });
});
