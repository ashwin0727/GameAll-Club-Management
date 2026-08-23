import { describe, expect, it } from "vitest";
import {
  hasOverlappingPricingPeriods,
  resolvePrice,
  validatePriceAmount,
  validatePricingAgainstOperatingHours,
  validatePricingRule,
  validatePricingRules,
} from "@/features/pricing/validation";
import { clonePeriods, defaultPeriod } from "@/features/pricing/components/types";
import type { OperatingDay } from "@/features/operating-hours/types";
import type { PricingRule } from "@/features/pricing/types";

function rule(overrides: Partial<PricingRule> = {}): PricingRule {
  return {
    facilitySportId: "fs-badminton",
    dayType: "ALL_DAYS",
    coversFullDay: true,
    amountMinor: 40000,
    currency: "INR",
    pricingUnit: "PER_HOUR",
    priority: 0,
    ...overrides,
  };
}

describe("validatePriceAmount", () => {
  it("rejects zero", () => {
    expect(validatePriceAmount(0)).toMatch(/greater than 0/i);
  });

  it("rejects a negative amount", () => {
    expect(validatePriceAmount(-100)).toMatch(/greater than 0/i);
  });

  it("accepts a positive integer", () => {
    expect(validatePriceAmount(40000)).toBeNull();
  });
});

describe("validatePricingRule", () => {
  it("a full-day rule only needs a valid amount", () => {
    expect(validatePricingRule(rule())).toBeNull();
  });

  it("a time-bounded rule requires start and end time", () => {
    expect(validatePricingRule(rule({ coversFullDay: false }))).toMatch(/start time/i);
  });

  it("rejects identical start and end time", () => {
    expect(
      validatePricingRule(rule({ coversFullDay: false, startTime: "16:00", endTime: "16:00" })),
    ).toMatch(/cannot be the same/i);
  });
});

describe("hasOverlappingPricingPeriods (overlap detection)", () => {
  it("allows non-overlapping peak/off-peak windows", () => {
    const rules = [
      rule({ coversFullDay: false, startTime: "06:00", endTime: "16:00" }),
      rule({ coversFullDay: false, startTime: "16:00", endTime: "23:00" }),
    ];
    expect(hasOverlappingPricingPeriods(rules)).toBe(false);
  });

  it("detects overlapping windows in the same sport/day-type scope", () => {
    const rules = [
      rule({ coversFullDay: false, startTime: "06:00", endTime: "18:00" }),
      rule({ coversFullDay: false, startTime: "17:00", endTime: "23:00" }),
    ];
    expect(hasOverlappingPricingPeriods(rules)).toBe(true);
  });

  it("does not compare windows across different playing areas", () => {
    const rules = [
      rule({ coversFullDay: false, startTime: "06:00", endTime: "18:00", playingAreaId: "court-1" }),
      rule({ coversFullDay: false, startTime: "10:00", endTime: "20:00", playingAreaId: "court-2" }),
    ];
    expect(hasOverlappingPricingPeriods(rules)).toBe(false);
  });

  it("ignores full-day rules when checking overlap", () => {
    const rules = [rule({ coversFullDay: true }), rule({ coversFullDay: false, startTime: "16:00", endTime: "23:00" })];
    expect(hasOverlappingPricingPeriods(rules)).toBe(false);
  });
});

describe("weekday/weekend logic", () => {
  const weekdayRule = rule({ dayType: "WEEKDAYS", amountMinor: 40000 });
  const weekendRule = rule({ dayType: "WEEKENDS", amountMinor: 50000 });

  it("resolves the weekday rate on a Tuesday", () => {
    const tuesday = new Date("2026-08-25"); // a Tuesday
    const resolved = resolvePrice([weekdayRule, weekendRule], "fs-badminton", null, tuesday, "10:00");
    expect(resolved?.amountMinor).toBe(40000);
  });

  it("resolves the weekend rate on a Saturday", () => {
    const saturday = new Date("2026-08-29");
    const resolved = resolvePrice([weekdayRule, weekendRule], "fs-badminton", null, saturday, "10:00");
    expect(resolved?.amountMinor).toBe(50000);
  });
});

describe("peak/off-peak logic", () => {
  const offPeak = rule({ coversFullDay: false, startTime: "06:00", endTime: "16:00", amountMinor: 30000 });
  const peak = rule({ coversFullDay: false, startTime: "16:00", endTime: "23:00", amountMinor: 45000 });

  it("resolves the off-peak rate inside the off-peak window", () => {
    expect(resolvePrice([offPeak, peak], "fs-badminton", null, new Date("2026-08-24"), "09:00")?.amountMinor).toBe(30000);
  });

  it("resolves the peak rate inside the peak window", () => {
    expect(resolvePrice([offPeak, peak], "fs-badminton", null, new Date("2026-08-24"), "18:00")?.amountMinor).toBe(45000);
  });
});

describe("playing-area override / sport-level inheritance (pricing resolution priority)", () => {
  const sportDefault = rule({ amountMinor: 40000, priority: 0 });
  const courtOverride = rule({ amountMinor: 45000, playingAreaId: "court-3", priority: 10 });

  it("a court with no override inherits the sport default", () => {
    const resolved = resolvePrice([sportDefault, courtOverride], "fs-badminton", "court-1", new Date("2026-08-24"), "10:00");
    expect(resolved?.amountMinor).toBe(40000);
  });

  it("a court with its own rule uses the override, not the sport default", () => {
    const resolved = resolvePrice([sportDefault, courtOverride], "fs-badminton", "court-3", new Date("2026-08-24"), "10:00");
    expect(resolved?.amountMinor).toBe(45000);
  });

  it("returns null when nothing is configured for the sport", () => {
    expect(resolvePrice([], "fs-badminton", null, new Date("2026-08-24"), "10:00")).toBeNull();
  });
});

describe("validatePricingAgainstOperatingHours", () => {
  const openAllWeek: OperatingDay[] = Array.from({ length: 7 }, (_, dayOfWeek) => ({
    dayOfWeek: dayOfWeek as OperatingDay["dayOfWeek"],
    isClosed: false,
    is24Hours: false,
    slots: [{ startTime: "06:00", endTime: "23:00", crossesMidnight: false, displayOrder: 0 }],
  }));

  it("accepts a pricing window fully inside the operating slot", () => {
    expect(
      validatePricingAgainstOperatingHours({ dayType: "ALL_DAYS", coversFullDay: false, startTime: "16:00", endTime: "20:00" }, openAllWeek),
    ).toBeNull();
  });

  it("rejects a pricing window outside the operating slot", () => {
    expect(
      validatePricingAgainstOperatingHours({ dayType: "ALL_DAYS", coversFullDay: false, startTime: "02:00", endTime: "05:00" }, openAllWeek),
    ).toMatch(/operating hours/i);
  });

  it("rejects a rule that applies on a day the facility is closed", () => {
    const days = openAllWeek.map((d) => (d.dayOfWeek === 0 ? { ...d, isClosed: true, slots: [] } : d));
    expect(
      validatePricingAgainstOperatingHours({ dayType: "ALL_DAYS", coversFullDay: true }, days),
    ).toMatch(/closed/i);
  });
});

describe("validatePricingRules (aggregate)", () => {
  it("is valid for a well-formed sport-level rule set", () => {
    const result = validatePricingRules([rule()]);
    expect(result.isValid).toBe(true);
  });

  it("collects an amount error", () => {
    const result = validatePricingRules([rule({ amountMinor: 0 })]);
    expect(result.isValid).toBe(false);
    expect(result.ruleErrors[0]).toMatch(/greater than 0/i);
  });

  it("reports the overlap error separately from per-rule errors", () => {
    const result = validatePricingRules([
      rule({ coversFullDay: false, startTime: "06:00", endTime: "18:00" }),
      rule({ coversFullDay: false, startTime: "17:00", endTime: "23:00" }),
    ]);
    expect(result.isValid).toBe(false);
    expect(result.overlapError).toMatch(/cannot overlap/i);
  });
});

describe("copy pricing logic (clonePeriods)", () => {
  it("produces an independent deep copy — editing the clone doesn't mutate the source", () => {
    const source = [defaultPeriod("400")];
    const copy = clonePeriods(source);
    copy[0]!.amountInput = "999";
    expect(source[0]!.amountInput).toBe("400");
  });
});