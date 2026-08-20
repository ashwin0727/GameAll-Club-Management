import { describe, expect, it } from "vitest";
import { FACILITY_TYPE_OPTIONS, INDIAN_STATES } from "@/features/onboarding/constants";

describe("onboarding constants", () => {
  it("lists every facility type option exactly once, defaulting to Multi-Sport", () => {
    const values = FACILITY_TYPE_OPTIONS.map((option) => option.value);
    expect(new Set(values).size).toBe(values.length);
    expect(values).toEqual([
      "BADMINTON",
      "PICKLEBALL",
      "CRICKET",
      "FOOTBALL",
      "TENNIS",
      "MULTI_SPORT",
      "OTHER",
    ]);
  });

  it("lists every Indian state and union territory exactly once", () => {
    expect(new Set(INDIAN_STATES).size).toBe(INDIAN_STATES.length);
    expect(INDIAN_STATES).toContain("Tamil Nadu");
    expect(INDIAN_STATES).toContain("Delhi");
    expect(INDIAN_STATES.length).toBe(36);
  });
});
