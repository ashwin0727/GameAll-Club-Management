import { describe, expect, it } from "vitest";
import { filterToSearchParams, filterFromSearchParams } from "./url-state";
import type { AnalyticsFilter } from "./types";

describe("filterToSearchParams", () => {
  it("emits facility + preset, and omits custom dates / null scope", () => {
    const f: AnalyticsFilter = { facilityId: "fac-1", preset: "THIS_MONTH", facilitySportId: null, courtId: null };
    expect(filterToSearchParams(f).toString()).toBe("facility=fac-1&preset=THIS_MONTH");
  });

  it("includes from/to only for CUSTOM, and sport/court when set", () => {
    const f: AnalyticsFilter = {
      facilityId: "fac-1",
      preset: "CUSTOM",
      startDate: "2026-09-01",
      endDate: "2026-09-15",
      facilitySportId: "fs-2",
      courtId: "c-3",
    };
    const p = filterToSearchParams(f);
    expect(p.get("from")).toBe("2026-09-01");
    expect(p.get("to")).toBe("2026-09-15");
    expect(p.get("sport")).toBe("fs-2");
    expect(p.get("court")).toBe("c-3");
  });
});

describe("filterFromSearchParams", () => {
  it("round-trips a CUSTOM filter", () => {
    const f: AnalyticsFilter = {
      facilityId: "fac-1",
      preset: "CUSTOM",
      startDate: "2026-09-01",
      endDate: "2026-09-15",
      facilitySportId: "fs-2",
      courtId: "c-3",
    };
    expect(filterFromSearchParams(filterToSearchParams(f), "fallback")).toEqual(f);
  });

  it("falls back to the default preset on an unknown preset", () => {
    const p = new URLSearchParams("facility=fac-1&preset=NONSENSE");
    expect(filterFromSearchParams(p, "fallback").preset).toBe("THIS_MONTH");
  });

  it("falls back to the default preset when CUSTOM is missing dates", () => {
    const p = new URLSearchParams("facility=fac-1&preset=CUSTOM&from=2026-09-01");
    expect(filterFromSearchParams(p, "fallback").preset).toBe("THIS_MONTH");
  });

  it("uses the fallback facility id when the param is absent", () => {
    const p = new URLSearchParams("preset=THIS_WEEK");
    expect(filterFromSearchParams(p, "fallback-fac")).toMatchObject({
      facilityId: "fallback-fac",
      preset: "THIS_WEEK",
    });
  });
});
