import { describe, expect, it } from "vitest";
import {
  DEFAULT_PRICING_SETTINGS,
  autoTier,
  cloneSetup,
  dayGroupLabel,
  emptySetup,
  hasSetupProblems,
  newSlotId,
  nextSlot,
  openSpan,
  previewRows,
  priceRangeLabel,
  rulesFromSetup,
  setupFromRules,
  usesDayGroups,
  validateSetup,
  type PriceSetup,
  type PricingSettings,
  type Slot,
} from "@/features/pricing/setup/pricing-setup-model";
import { resolvePrice } from "@/features/pricing/validation";
import { scheduleFromPlans, defaultPlans } from "@/features/operating-hours/setup-model";

const SPAN = { open: "06:00", close: "23:00" };
const SCOPE = { facilitySportId: "fs-bad" };
const settings = (over: Partial<PricingSettings> = {}): PricingSettings => ({ ...DEFAULT_PRICING_SETTINGS, ...over });
const slot = (start: string, end: string, price: string, tier: Slot["tier"] = ""): Slot => ({ id: newSlotId(), start, end, price, tier });

function timedSetup(): PriceSetup {
  return {
    ...emptySetup(),
    basePrice: "400",
    timeBased: true,
    weekdays: [slot("06:00", "17:00", "400", "OFF_PEAK"), slot("17:00", "23:00", "550", "PEAK")],
    weekends: [slot("06:00", "17:00", "500", "OFF_PEAK"), slot("17:00", "23:00", "650", "PEAK")],
  };
}

describe("setup -> rules", () => {
  it("a plain base price is one full-day rate for all days", () => {
    const rules = rulesFromSetup({ ...emptySetup(), basePrice: "400" }, SCOPE, settings());
    expect(rules).toEqual([
      expect.objectContaining({ facilitySportId: "fs-bad", dayType: "ALL_DAYS", coversFullDay: true, amountMinor: 40000, pricingUnit: "PER_HOUR", audience: "GENERAL", priority: 0 }),
    ]);
  });

  it("a court's rules carry the court id and win with a higher priority", () => {
    const [rule] = rulesFromSetup({ ...emptySetup(), basePrice: "300" }, { ...SCOPE, playingAreaId: "court-1" }, settings());
    expect(rule).toMatchObject({ playingAreaId: "court-1", priority: 10 });
  });

  it("per session is carried on every rule", () => {
    const rules = rulesFromSetup({ ...timedSetup(), unit: "PER_SESSION" }, SCOPE, settings());
    expect(rules.every((r) => r.pricingUnit === "PER_SESSION")).toBe(true);
  });

  it("time-based pricing adds weekday and weekend slots with their peak / off-peak tag", () => {
    const rules = rulesFromSetup(timedSetup(), SCOPE, settings());
    expect(rules).toHaveLength(5); // base + 2 + 2
    const wd = rules.filter((r) => r.dayType === "WEEKDAYS");
    expect(wd.map((r) => [r.startTime, r.endTime, r.amountMinor, r.rateTier])).toEqual([
      ["06:00", "17:00", 40000, "OFF_PEAK"],
      ["17:00", "23:00", 55000, "PEAK"],
    ]);
    expect(rules.filter((r) => r.dayType === "WEEKENDS")).toHaveLength(2);
  });

  it("specific days carry the chosen days", () => {
    const setup = { ...timedSetup(), weekdays: [], weekends: [], specific: { days: [5, 1] as never, slots: [slot("18:00", "21:00", "700", "PEAK")] } };
    const rules = rulesFromSetup(setup, SCOPE, settings());
    expect(rules.find((r) => r.dayType === "SPECIFIC_DAYS")).toMatchObject({ daysOfWeek: [1, 5], amountMinor: 70000, rateTier: "PEAK" });
  });

  it("with weekday / weekend pricing off, slots apply to all days and the weekday lists are ignored", () => {
    const setup = { ...timedSetup(), allDays: [slot("06:00", "12:00", "350"), slot("12:00", "23:00", "450")] };
    const rules = rulesFromSetup(setup, SCOPE, settings({ differentWeekendPricing: false }));
    expect(rules.filter((r) => !r.coversFullDay).map((r) => r.dayType)).toEqual(["ALL_DAYS", "ALL_DAYS"]);
  });

  it("slots are ignored when time-based pricing is off, and blank prices are skipped", () => {
    const off = { ...timedSetup(), timeBased: false };
    expect(rulesFromSetup(off, SCOPE, settings())).toHaveLength(1);
    const blank = { ...timedSetup(), weekdays: [slot("06:00", "17:00", "")] , weekends: [] };
    expect(rulesFromSetup(blank, SCOPE, settings())).toHaveLength(1);
  });

  it("member and coaching rates are stored as their own audience, only when switched on", () => {
    const setup = { ...emptySetup(), basePrice: "400", memberPrice: "300", coachingPrice: "250" };
    expect(rulesFromSetup(setup, SCOPE, settings())).toHaveLength(1);
    const rules = rulesFromSetup(setup, SCOPE, settings({ memberPricingEnabled: true, coachingPricingEnabled: true }));
    expect(rules.map((r) => [r.audience, r.amountMinor])).toEqual([["GENERAL", 40000], ["MEMBER", 30000], ["COACHING", 25000]]);
  });
});

describe("rules -> setup", () => {
  it("round-trips a setup", () => {
    const original = timedSetup();
    const rules = rulesFromSetup(original, SCOPE, settings({ memberPricingEnabled: true }));
    const back = setupFromRules(rules, SPAN);
    expect(back.basePrice).toBe("400");
    expect(back.timeBased).toBe(true);
    expect(back.weekdays.map((s) => [s.start, s.end, s.price, s.tier])).toEqual([["06:00", "17:00", "400", "OFF_PEAK"], ["17:00", "23:00", "550", "PEAK"]]);
    expect(back.weekends.map((s) => s.price)).toEqual(["500", "650"]);
    expect(back.unit).toBe("PER_HOUR");
  });

  it("reads specific days, per-session and member / coaching rates", () => {
    const setup = { ...emptySetup(), unit: "PER_SESSION" as const, basePrice: "900", memberPrice: "700", coachingPrice: "600", timeBased: true, specific: { days: [2, 4] as never, slots: [slot("10:00", "12:00", "800")] } };
    const back = setupFromRules(rulesFromSetup(setup, SCOPE, settings({ memberPricingEnabled: true, coachingPricingEnabled: true })), SPAN);
    expect(back.unit).toBe("PER_SESSION");
    expect(back.specific.days.sort()).toEqual([2, 4]);
    expect(back.specific.slots[0]).toMatchObject({ start: "10:00", end: "12:00", price: "800" });
    expect([back.memberPrice, back.coachingPrice]).toEqual(["700", "600"]);
  });

  it("an old weekday full-day rate becomes a slot over the open hours, and the lowest price is the base", () => {
    const back = setupFromRules(
      [
        { facilitySportId: "fs", dayType: "WEEKDAYS", coversFullDay: true, amountMinor: 30000, currency: "INR", pricingUnit: "PER_HOUR", priority: 0 },
        { facilitySportId: "fs", dayType: "WEEKENDS", coversFullDay: true, amountMinor: 40000, currency: "INR", pricingUnit: "PER_HOUR", priority: 0 },
      ],
      SPAN,
    );
    expect(back.timeBased).toBe(true);
    expect(back.weekdays[0]).toMatchObject({ start: "06:00", end: "23:00", price: "300" });
    expect(back.basePrice).toBe("300");
  });

  it("nothing saved is an empty setup", () => {
    expect(setupFromRules([], SPAN)).toEqual(emptySetup());
    expect(usesDayGroups(rulesFromSetup(timedSetup(), SCOPE, settings()))).toBe(true);
    expect(usesDayGroups(rulesFromSetup({ ...emptySetup(), basePrice: "1" }, SCOPE, settings()))).toBe(false);
  });
});

describe("what a booking is charged (the same pick the database makes)", () => {
  const rules = rulesFromSetup(timedSetup(), SCOPE, settings());
  const monday = new Date(2026, 8, 7); // a Monday
  const saturday = new Date(2026, 8, 12);

  it("uses the slot for the day and time, the base price outside the slots, and ignores member rates", () => {
    expect(resolvePrice(rules, "fs-bad", null, monday, "07:00")?.amountMinor).toBe(40000);
    expect(resolvePrice(rules, "fs-bad", null, monday, "18:00")?.amountMinor).toBe(55000);
    expect(resolvePrice(rules, "fs-bad", null, saturday, "18:00")?.amountMinor).toBe(65000);
    expect(resolvePrice(rules, "fs-bad", null, monday, "23:30")?.amountMinor).toBe(40000); // base
    const withMember = [...rules, ...rulesFromSetup({ ...emptySetup(), basePrice: "1", memberPrice: "100" }, SCOPE, settings({ memberPricingEnabled: true })).filter((r) => r.audience === "MEMBER")];
    expect(resolvePrice(withMember, "fs-bad", null, monday, "07:00")?.amountMinor).toBe(40000);
  });

  it("specific days beat weekday slots on their days", () => {
    const setup = { ...timedSetup(), specific: { days: [1] as never, slots: [slot("17:00", "23:00", "900", "PEAK")] } };
    const r = rulesFromSetup(setup, SCOPE, settings());
    expect(resolvePrice(r, "fs-bad", null, monday, "18:00")?.amountMinor).toBe(90000);
    expect(resolvePrice(r, "fs-bad", null, new Date(2026, 8, 8), "18:00")?.amountMinor).toBe(55000); // Tuesday
  });

  it("a court's own rate wins over its sport's", () => {
    const court = rulesFromSetup({ ...emptySetup(), basePrice: "800" }, { ...SCOPE, playingAreaId: "c1" }, settings());
    expect(resolvePrice([...rules, ...court], "fs-bad", "c1", monday, "07:00")?.amountMinor).toBe(80000);
    expect(resolvePrice([...rules, ...court], "fs-bad", "c2", monday, "07:00")?.amountMinor).toBe(40000);
  });
});

describe("checking a setup", () => {
  const hours = scheduleFromPlans(defaultPlans(), null); // Mon-Sat 6 AM - 11 PM

  it("a base price is required and must be a valid amount", () => {
    expect(validateSetup(emptySetup(), SCOPE, settings(), hours).base).toBe("Enter the base price.");
    expect(validateSetup({ ...emptySetup(), basePrice: "abc" }, SCOPE, settings(), hours).base).toBe("Enter a valid amount greater than 0.");
    expect(validateSetup({ ...emptySetup(), basePrice: "0" }, SCOPE, settings(), hours).base).toBe("Enter a valid amount greater than 0.");
    expect(hasSetupProblems(validateSetup({ ...emptySetup(), basePrice: "400.50" }, SCOPE, settings(), hours))).toBe(false);
  });

  it("each slot needs a price and a real time range", () => {
    const bad = { ...timedSetup(), weekdays: [slot("06:00", "06:00", "400"), slot("07:00", "08:00", "")], weekends: [] };
    const p = validateSetup(bad, SCOPE, settings(), hours);
    expect(Object.values(p.slots).sort()).toEqual(["Enter a price.", "Start and end time cannot be the same."]);
  });

  it("slots must not overlap, and must fall inside the opening hours", () => {
    const overlap = { ...timedSetup(), weekdays: [slot("06:00", "12:00", "400"), slot("11:00", "14:00", "500")], weekends: [] };
    expect(Object.values(validateSetup(overlap, SCOPE, settings(), hours).groups)[0]).toBe("Pricing periods cannot overlap.");
    const outside = { ...timedSetup(), weekdays: [slot("04:00", "08:00", "400")], weekends: [] };
    expect(Object.values(validateSetup(outside, SCOPE, settings(), hours).groups)[0]).toMatch(/operating hours/);
  });

  it("a slot may run across a daily break", () => {
    const withBreak = scheduleFromPlans(defaultPlans(), { start: "13:00", end: "14:00" });
    const across = { ...timedSetup(), weekdays: [slot("06:00", "17:00", "400")], weekends: [] };
    expect(hasSetupProblems(validateSetup(across, SCOPE, settings(), withBreak))).toBe(false);
  });

  it("specific days need at least one day", () => {
    const none = { ...timedSetup(), weekdays: [], weekends: [], specific: { days: [], slots: [slot("10:00", "12:00", "600")] } };
    expect(validateSetup(none, SCOPE, settings(), hours).groups.SPECIFIC_DAYS).toBe("Choose at least one day.");
  });

  it("member and coaching rates are required once switched on", () => {
    const p = validateSetup({ ...emptySetup(), basePrice: "400" }, SCOPE, settings({ memberPricingEnabled: true, coachingPricingEnabled: true }), hours);
    expect([p.member, p.coaching]).toEqual(["Enter the member price.", "Enter the coaching price."]);
    expect(hasSetupProblems(validateSetup({ ...emptySetup(), basePrice: "400", memberPrice: "300", coachingPrice: "250" }, SCOPE, settings({ memberPricingEnabled: true, coachingPricingEnabled: true }), hours))).toBe(false);
  });
});

describe("tags, slots and previews", () => {
  it("the tag follows the price against the base", () => {
    expect(autoTier("550", "400")).toBe("PEAK");
    expect(autoTier("300", "400")).toBe("OFF_PEAK");
    expect(autoTier("400", "400")).toBe("");
    expect(autoTier("", "400")).toBe("");
  });

  it("a new slot starts where the last ended and runs to closing", () => {
    expect(nextSlot([], SPAN)).toMatchObject({ start: "06:00", end: "23:00" });
    expect(nextSlot([slot("06:00", "17:00", "400")], SPAN)).toMatchObject({ start: "17:00", end: "23:00" });
    expect(nextSlot([slot("06:00", "23:00", "400")], SPAN)).toMatchObject({ start: "06:00", end: "23:00" });
  });

  it("the open span is the earliest opening to the latest closing", () => {
    expect(openSpan(scheduleFromPlans(defaultPlans(), null))).toEqual({ open: "06:00", close: "23:00" });
    expect(openSpan(null)).toEqual({ open: "06:00", close: "23:00" });
  });

  it("labels day groups and price ranges", () => {
    expect(dayGroupLabel("WEEKDAYS")).toBe("Mon – Fri");
    expect(dayGroupLabel("WEEKENDS")).toBe("Sat – Sun");
    expect(dayGroupLabel("ALL_DAYS")).toBe("All days");
    expect(dayGroupLabel("SPECIFIC_DAYS", [5, 1, 3])).toBe("Mon, Wed, Fri");
    expect(priceRangeLabel(timedSetup(), settings())).toBe("₹400 – ₹650 / hour");
    expect(priceRangeLabel({ ...emptySetup(), basePrice: "2000" }, settings())).toBe("₹2,000 / hour");
    expect(priceRangeLabel({ ...emptySetup(), unit: "PER_SESSION", basePrice: "900" }, settings())).toBe("₹900 / session");
    expect(priceRangeLabel(emptySetup(), settings())).toBe("Not set");
  });

  it("the court preview lists each slot, then the base price for other times", () => {
    const rows = previewRows(timedSetup(), settings());
    expect(rows.slice(0, 2)).toEqual([
      { day: "Mon – Fri", time: "6:00 AM – 5:00 PM", rate: "₹400" },
      { day: "Mon – Fri", time: "5:00 PM – 11:00 PM", rate: "₹550" },
    ]);
    expect(rows.at(-1)).toEqual({ day: "Other times", time: "Outside the slots above", rate: "₹400 / hour" });
    expect(previewRows({ ...emptySetup(), basePrice: "400" }, settings())).toEqual([{ day: "All days", time: "Full day", rate: "₹400 / hour" }]);
  });

  it("cloning gives independent slots", () => {
    const a = timedSetup();
    const b = cloneSetup(a);
    b.weekdays[0]!.price = "999";
    expect(a.weekdays[0]!.price).toBe("400");
    expect(b.weekdays[0]!.id).not.toBe(a.weekdays[0]!.id);
  });
});
