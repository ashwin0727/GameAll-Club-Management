import { describe, expect, it } from "vitest";
import {
  buildMissingRequirements,
  computeSetupStatus,
  detectMissingOperatingHours,
  detectMissingPlayingAreas,
  detectMissingPricing,
  detectMissingSports,
  transformPricingSummary,
  transformSportsSummary,
} from "@/features/onboarding-summary/validation";
import type { PlayingArea } from "@/features/courts-setup/types";
import type { OperatingDay, OperatingSchedule } from "@/features/operating-hours/types";
import type { PricingRule } from "@/features/pricing/types";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";

const SPORT: Sport = { id: "sport-badminton", name: "Badminton", code: "BADMINTON", icon: "🏸", description: "", isActive: true };

const FACILITY_SPORT: FacilitySport = {
  id: "fs-1",
  facilityId: "facility-1",
  sportId: "sport-badminton",
  enabled: true,
  createdAt: "2026-01-01T00:00:00.000Z",
  updatedAt: "2026-01-01T00:00:00.000Z",
};

const AREA: PlayingArea = {
  id: "area-1",
  facilityId: "facility-1",
  facilitySportId: "fs-1",
  sportId: "sport-badminton",
  name: "Court 1",
  type: "INDOOR",
  status: "ACTIVE",
  bookingEnabled: true,
  archived: false,
  displayOrder: 0,
  createdAt: "2026-01-01T00:00:00.000Z",
  updatedAt: "2026-01-01T00:00:00.000Z",
};

function schedule(days: OperatingDay[]): OperatingSchedule {
  return {
    id: "schedule-1",
    facilityId: "facility-1",
    scopeType: "FACILITY",
    timezone: "Asia/Kolkata",
    days,
    createdAt: "2026-01-01T00:00:00.000Z",
    updatedAt: "2026-01-01T00:00:00.000Z",
  };
}

function rule(overrides: Partial<PricingRule> = {}): PricingRule {
  return {
    facilitySportId: "fs-1",
    dayType: "ALL_DAYS",
    coversFullDay: true,
    amountMinor: 40000,
    currency: "INR",
    pricingUnit: "PER_HOUR",
    priority: 0,
    ...overrides,
  };
}

describe("detectMissingSports", () => {
  it("flags an empty facility_sports list", () => {
    expect(detectMissingSports([])).toBe(true);
  });
  it("passes when at least one sport is configured", () => {
    expect(detectMissingSports([FACILITY_SPORT])).toBe(false);
  });
});

describe("detectMissingPlayingAreas", () => {
  it("flags an empty playing-area list", () => {
    expect(detectMissingPlayingAreas([])).toBe(true);
  });
  it("passes when at least one playing area exists", () => {
    expect(detectMissingPlayingAreas([AREA])).toBe(false);
  });
});

describe("detectMissingOperatingHours", () => {
  it("flags a null schedule", () => {
    expect(detectMissingOperatingHours(null)).toBe(true);
  });
  it("flags a schedule where every day is closed", () => {
    const days: OperatingDay[] = Array.from({ length: 7 }, (_, d) => ({
      dayOfWeek: d as OperatingDay["dayOfWeek"],
      isClosed: true,
      is24Hours: false,
      slots: [],
    }));
    expect(detectMissingOperatingHours(schedule(days))).toBe(true);
  });
  it("passes when at least one day is open", () => {
    const days: OperatingDay[] = Array.from({ length: 7 }, (_, d) => ({
      dayOfWeek: d as OperatingDay["dayOfWeek"],
      isClosed: d !== 1,
      is24Hours: false,
      slots: d === 1 ? [{ startTime: "06:00", endTime: "23:00", crossesMidnight: false, displayOrder: 0 }] : [],
    }));
    expect(detectMissingOperatingHours(schedule(days))).toBe(false);
  });
});

describe("detectMissingPricing", () => {
  it("lists a sport with no sport-level rule", () => {
    const missing = detectMissingPricing([FACILITY_SPORT], [SPORT], []);
    expect(missing).toEqual(["Badminton"]);
  });
  it("does not list a sport that has a sport-level rule", () => {
    const missing = detectMissingPricing([FACILITY_SPORT], [SPORT], [rule()]);
    expect(missing).toEqual([]);
  });
  it("ignores a playing-area-only override — the sport still needs its own default", () => {
    const missing = detectMissingPricing([FACILITY_SPORT], [SPORT], [rule({ playingAreaId: "area-1" })]);
    expect(missing).toEqual(["Badminton"]);
  });
});

describe("computeSetupStatus", () => {
  it("is READY with no missing requirements", () => {
    expect(computeSetupStatus([])).toBe("READY");
  });
  it("is ACTION_REQUIRED with at least one missing requirement", () => {
    expect(
      computeSetupStatus([{ code: "SPORTS", message: "x", actionLabel: "Fix", actionHref: "/onboarding/sports" }]),
    ).toBe("ACTION_REQUIRED");
  });
});

describe("buildMissingRequirements", () => {
  it("generates one requirement per missing area, plus one per unpriced sport", () => {
    const requirements = buildMissingRequirements({
      missingSports: false,
      missingPlayingAreas: true,
      missingOperatingHours: true,
      sportsMissingPricing: ["Badminton", "Cricket"],
    });
    expect(requirements.map((r) => r.code)).toEqual(["PLAYING_AREAS", "OPERATING_HOURS", "PRICING", "PRICING"]);
    expect(requirements.every((r) => r.actionHref.startsWith("/onboarding/"))).toBe(true);
  });

  it("generates nothing when everything is complete", () => {
    expect(
      buildMissingRequirements({
        missingSports: false,
        missingPlayingAreas: false,
        missingOperatingHours: false,
        sportsMissingPricing: [],
      }),
    ).toEqual([]);
  });
});

describe("transformSportsSummary (sports + playing-area grouping)", () => {
  it("groups playing areas under their sport, with a friendly area label", () => {
    const result = transformSportsSummary([FACILITY_SPORT], [SPORT], [AREA]);
    expect(result).toHaveLength(1);
    expect(result[0]?.sportName).toBe("Badminton");
    expect(result[0]?.areaLabel).toBe("Court");
    expect(result[0]?.playingAreas).toEqual([{ id: "area-1", name: "Court 1" }]);
  });

  it("uses the custom sport name when one was set", () => {
    const custom: FacilitySport = { ...FACILITY_SPORT, customSportName: "Kabaddi" };
    const result = transformSportsSummary([custom], [SPORT], []);
    expect(result[0]?.sportName).toBe("Kabaddi");
  });
});

describe("transformPricingSummary (pricing summary formatting + inheritance)", () => {
  it("shows the sport-level default rate with no overrides", () => {
    const result = transformPricingSummary([FACILITY_SPORT], [SPORT], [AREA], [rule()]);
    expect(result[0]?.defaultAmountMinor).toBe(40000);
    expect(result[0]?.overrides).toEqual([]);
  });

  it("lists a playing-area override alongside the sport default", () => {
    const rules = [rule(), rule({ playingAreaId: "area-1", amountMinor: 45000 })];
    const result = transformPricingSummary([FACILITY_SPORT], [SPORT], [AREA], rules);
    expect(result[0]?.defaultAmountMinor).toBe(40000);
    expect(result[0]?.overrides).toEqual([{ playingAreaId: "area-1", playingAreaName: "Court 1", amountMinor: 45000 }]);
  });

  it("reports null when no default rate exists yet", () => {
    const result = transformPricingSummary([FACILITY_SPORT], [SPORT], [AREA], []);
    expect(result[0]?.defaultAmountMinor).toBeNull();
  });
});