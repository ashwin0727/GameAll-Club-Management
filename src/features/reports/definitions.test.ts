import { describe, expect, it } from "vitest";
import { KPI_DEFINITIONS, FRESHNESS_NOTE, type KpiKey } from "./definitions";

describe("KPI_DEFINITIONS", () => {
  it("gives every KPI key a non-empty, sentence-like definition", () => {
    const keys = Object.keys(KPI_DEFINITIONS) as KpiKey[];
    expect(keys.length).toBeGreaterThanOrEqual(20);
    for (const key of keys) {
      const def = KPI_DEFINITIONS[key];
      expect(def, key).toBeTruthy();
      expect(def.length, key).toBeGreaterThan(15);
      expect(def.trim().endsWith("."), key).toBe(true);
    }
  });

  it("states the cash-basis rule on the revenue KPIs", () => {
    expect(KPI_DEFINITIONS.totalRevenue.toLowerCase()).toContain("cash basis");
    expect(KPI_DEFINITIONS.bookingRevenue.toLowerCase()).toContain("not counted");
  });

  it("has a freshness note", () => {
    expect(FRESHNESS_NOTE.toLowerCase()).toContain("real-time");
  });
});
