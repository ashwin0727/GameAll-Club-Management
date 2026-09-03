import { describe, expect, it } from "vitest";
import {
  spanDays,
  pickGranularity,
  pickGranularityForDays,
  filterSpanDays,
  previousPeriod,
  toCsv,
} from "./aggregation";
import type { AnalyticsFilter } from "./types";

const base: AnalyticsFilter = { facilityId: "f1", preset: "THIS_MONTH" };

describe("spanDays", () => {
  it("counts a single day as 1", () => {
    expect(spanDays("2026-09-03", "2026-09-03")).toBe(1);
  });
  it("counts an inclusive range", () => {
    expect(spanDays("2026-09-01", "2026-09-30")).toBe(30);
  });
});

describe("pickGranularity", () => {
  it("is daily up to 31 days", () => {
    expect(pickGranularity("2026-09-01", "2026-10-01")).toBe("daily"); // 31
  });
  it("is weekly from 32 to 183 days", () => {
    expect(pickGranularity("2026-09-01", "2026-10-02")).toBe("weekly"); // 32
    expect(pickGranularity("2026-01-01", "2026-07-02")).toBe("weekly"); // 183
  });
  it("is monthly beyond 183 days", () => {
    expect(pickGranularity("2026-01-01", "2026-07-03")).toBe("monthly"); // 184
  });
});

describe("pickGranularityForDays", () => {
  it("matches the day-count boundaries", () => {
    expect(pickGranularityForDays(31)).toBe("daily");
    expect(pickGranularityForDays(32)).toBe("weekly");
    expect(pickGranularityForDays(183)).toBe("weekly");
    expect(pickGranularityForDays(184)).toBe("monthly");
  });
});

describe("filterSpanDays", () => {
  it("returns the approximate preset span", () => {
    expect(filterSpanDays({ facilityId: "f", preset: "THIS_QUARTER" })).toBe(92);
    expect(filterSpanDays({ facilityId: "f", preset: "TODAY" })).toBe(1);
  });
  it("measures an explicit CUSTOM range", () => {
    expect(
      filterSpanDays({ facilityId: "f", preset: "CUSTOM", startDate: "2026-09-01", endDate: "2026-09-10" }),
    ).toBe(10);
  });
  it("falls back to 31 for a CUSTOM range with no dates", () => {
    expect(filterSpanDays({ facilityId: "f", preset: "CUSTOM" })).toBe(31);
  });
});

describe("previousPeriod", () => {
  it("maps the common presets to their prior preset", () => {
    expect(previousPeriod({ ...base, preset: "TODAY" })?.preset).toBe("YESTERDAY");
    expect(previousPeriod({ ...base, preset: "THIS_WEEK" })?.preset).toBe("LAST_WEEK");
    expect(previousPeriod({ ...base, preset: "THIS_MONTH" })?.preset).toBe("LAST_MONTH");
  });

  it("shifts a resolved quarter back by its own length as a CUSTOM range", () => {
    // Q3 (Jul 1 - Sep 30) is 92 days; the prior 92-day window ends Jun 30 and
    // therefore starts Mar 31.
    const prev = previousPeriod(
      { ...base, preset: "THIS_QUARTER" },
      { startDate: "2026-07-01", endDate: "2026-09-30" },
    );
    expect(prev).toEqual({ ...base, preset: "CUSTOM", startDate: "2026-03-31", endDate: "2026-06-30" });
  });

  it("shifts an explicit CUSTOM range back", () => {
    const prev = previousPeriod({ ...base, preset: "CUSTOM", startDate: "2026-09-10", endDate: "2026-09-19" });
    expect(prev).toEqual({ ...base, preset: "CUSTOM", startDate: "2026-08-31", endDate: "2026-09-09" });
  });

  it("returns null for a CUSTOM range with no dates", () => {
    expect(previousPeriod({ ...base, preset: "CUSTOM" })).toBeNull();
  });

  it("returns null for a resolved-range preset when no resolved range is given", () => {
    expect(previousPeriod({ ...base, preset: "THIS_YEAR" })).toBeNull();
  });
});

describe("toCsv", () => {
  it("writes a header row from the first object's keys", () => {
    expect(toCsv([{ sport: "Badminton", revenue: 45000 }])).toBe("sport,revenue\r\nBadminton,45000");
  });
  it("quotes fields containing comma, quote or newline and doubles quotes", () => {
    expect(toCsv([{ name: 'A, "B"', note: "line1\nline2" }])).toBe(
      'name,note\r\n"A, ""B""","line1\nline2"',
    );
  });
  it("renders null as an empty quoted field and returns '' for no rows", () => {
    expect(toCsv([{ a: null, b: 1 }])).toBe('a,b\r\n"",1');
    expect(toCsv([])).toBe("");
  });
});
