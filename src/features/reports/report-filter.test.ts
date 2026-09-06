import { describe, expect, it } from "vitest";
import { dateRangeArgs, scopeArgs } from "./report-filter";
import type { AnalyticsFilter } from "./types";

const base: AnalyticsFilter = { facilityId: "f1", preset: "THIS_MONTH" };

describe("dateRangeArgs", () => {
  it("passes the preset and nulls the custom dates for a preset range", () => {
    expect(dateRangeArgs(base)).toEqual({ p_preset: "THIS_MONTH", p_start_date: null, p_end_date: null });
  });
  it("passes explicit dates for CUSTOM", () => {
    expect(
      dateRangeArgs({ ...base, preset: "CUSTOM", startDate: "2026-09-01", endDate: "2026-09-15" }),
    ).toEqual({ p_preset: "CUSTOM", p_start_date: "2026-09-01", p_end_date: "2026-09-15" });
  });
  it("nulls missing CUSTOM dates rather than passing undefined", () => {
    expect(dateRangeArgs({ ...base, preset: "CUSTOM" })).toEqual({
      p_preset: "CUSTOM",
      p_start_date: null,
      p_end_date: null,
    });
  });
});

describe("scopeArgs", () => {
  it("nulls absent sport/court", () => {
    expect(scopeArgs(base)).toEqual({ p_facility_sport_id: null, p_court_id: null });
  });
  it("passes sport and court when set", () => {
    expect(scopeArgs({ ...base, facilitySportId: "fs-1", courtId: "c-2" })).toEqual({
      p_facility_sport_id: "fs-1",
      p_court_id: "c-2",
    });
  });
});
