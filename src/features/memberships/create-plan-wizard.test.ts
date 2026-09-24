import { describe, expect, it } from "vitest";
import {
  composeFeatures,
  fieldErrors,
  findOverlap,
  furthestReachableStep,
  isStepComplete,
  PLAN_WIZARD_STEPS,
  validateStep,
  windowsOverlap,
  type PlanTimeWindow,
  type PlanWizardDraft,
} from "@/features/memberships/create-plan-wizard";

function draft(overrides: Partial<PlanWizardDraft> = {}): PlanWizardDraft {
  return {
    name: "Monthly Membership",
    description: "",
    planType: "TIME_BASED",
    category: "Regular Membership",
    priceInr: 2500,
    durationDays: 30,
    joiningFeeInr: 0,
    securityDepositInr: 0,
    showBadge: true,
    badgeText: "Popular",
    courtIds: ["court-1"],
    playingDays: [1, 2, 3, 4, 5],
    timeWindows: [{ id: "w1", courtId: "court-1", daysOfWeek: [1, 2, 3, 4, 5], startTime: "06:00", endTime: "07:00", capacity: 4 }],
    allowAdvanceBooking: true,
    limitConsecutiveSlots: false,
    features: [],
    isActive: true,
    ...overrides,
  };
}

function window(overrides: Partial<PlanTimeWindow> = {}): PlanTimeWindow {
  return { id: "w1", courtId: "court-1", daysOfWeek: [1, 2, 3, 4, 5], startTime: "06:00", endTime: "07:00", capacity: 4, ...overrides };
}

describe("PLAN_WIZARD_STEPS", () => {
  it("is the four steps from the design, in order", () => {
    expect(PLAN_WIZARD_STEPS.map((s) => s.title)).toEqual(["Plan Details", "Plan Configuration", "Court Access", "Review & Create"]);
  });
});

describe("fieldErrors / validateStep", () => {
  it("requires a plan name", () => {
    expect(validateStep(1, draft())).toBeNull();
    expect(fieldErrors(1, draft({ name: "" })).name).toMatch(/plan name is required/i);
    expect(fieldErrors(1, draft({ name: "  " })).name).toMatch(/plan name is required/i);
  });

  it("caps the description at 200 characters", () => {
    expect(fieldErrors(1, draft({ description: "x".repeat(200) })).description).toBeUndefined();
    expect(fieldErrors(1, draft({ description: "x".repeat(201) })).description).toBeDefined();
  });

  it("requires a price greater than 0 and a positive whole-day duration", () => {
    expect(validateStep(2, draft())).toBeNull();
    expect(fieldErrors(2, draft({ priceInr: -1 })).priceInr).toBeDefined();
    expect(fieldErrors(2, draft({ priceInr: 0 })).priceInr).toMatch(/price must be greater than 0/i);
    expect(fieldErrors(2, draft({ durationDays: 0 })).durationDays).toBeDefined();
    expect(fieldErrors(2, draft({ durationDays: 30.5 })).durationDays).toBeDefined();
  });

  it("rejects a negative joining fee or security deposit, but allows 0 or empty", () => {
    expect(fieldErrors(2, draft({ joiningFeeInr: -1 })).joiningFeeInr).toBeDefined();
    expect(fieldErrors(2, draft({ joiningFeeInr: 0 })).joiningFeeInr).toBeUndefined();
    expect(fieldErrors(2, draft({ joiningFeeInr: 500 })).joiningFeeInr).toBeUndefined();
    expect(fieldErrors(2, draft({ securityDepositInr: -1 })).securityDepositInr).toBeDefined();
    expect(fieldErrors(2, draft({ securityDepositInr: 0 })).securityDepositInr).toBeUndefined();
  });

  it("requires at least one court, one playing day and one time window", () => {
    expect(validateStep(3, draft())).toBeNull();
    expect(fieldErrors(3, draft({ courtIds: [] })).courtIds).toMatch(/select at least one court/i);
    expect(fieldErrors(3, draft({ playingDays: [] })).playingDays).toMatch(/select at least one playing day/i);
    expect(fieldErrors(3, draft({ timeWindows: [] })).timeWindows).toMatch(/add at least one time window/i);
  });

  it("rejects a time window whose end isn't after its start, or with no capacity", () => {
    expect(fieldErrors(3, draft({ timeWindows: [window({ startTime: "08:00", endTime: "07:00" })] })).timeWindows).toBeDefined();
    expect(fieldErrors(3, draft({ timeWindows: [window({ startTime: "07:00", endTime: "07:00" })] })).timeWindows).toBeDefined();
    expect(fieldErrors(3, draft({ timeWindows: [window({ capacity: 0 })] })).timeWindows).toBeDefined();
  });

  it("never blocks Review & Create", () => {
    expect(validateStep(4, draft())).toBeNull();
  });
});

describe("furthestReachableStep / isStepComplete", () => {
  it("stops at the first of steps 1-3 that isn't finished", () => {
    expect(furthestReachableStep(draft({ name: "" }))).toBe(1);
    expect(furthestReachableStep(draft({ durationDays: 0 }))).toBe(2);
    expect(furthestReachableStep(draft({ courtIds: [] }))).toBe(3);
  });

  it("reaches the end once name/price/duration/court-access are all valid", () => {
    expect(furthestReachableStep(draft())).toBe(4);
  });

  it("only marks a step complete once it's behind you and valid", () => {
    expect(isStepComplete(1, draft(), 4)).toBe(true);
    expect(isStepComplete(3, draft(), 4)).toBe(true);
    expect(isStepComplete(4, draft(), 4)).toBe(false); // not behind current
    expect(isStepComplete(1, draft({ name: "" }), 4)).toBe(false);
    expect(isStepComplete(3, draft({ courtIds: [] }), 4)).toBe(false);
  });
});

describe("windowsOverlap / findOverlap", () => {
  it("flags two windows on the same court sharing a day and overlapping clock times", () => {
    const a = window({ startTime: "06:00", endTime: "08:00" });
    const b = window({ id: "w2", startTime: "07:00", endTime: "09:00" });
    expect(windowsOverlap(a, b)).toBe(true);
  });

  it("doesn't flag different courts, disjoint days, or back-to-back (non-overlapping) times", () => {
    const base = window();
    expect(windowsOverlap(base, window({ id: "w2", courtId: "court-2" }))).toBe(false);
    expect(windowsOverlap(base, window({ id: "w2", daysOfWeek: [6, 0] }))).toBe(false);
    expect(windowsOverlap(base, window({ id: "w2", startTime: "07:00", endTime: "08:00" }))).toBe(false);
  });

  it("finds the first other window a given one overlaps, ignoring itself", () => {
    const a = window({ id: "w1" });
    const b = window({ id: "w2", startTime: "06:30", endTime: "07:30" });
    expect(findOverlap([a, b], a)?.id).toBe("w2");
    expect(findOverlap([a], a)).toBeUndefined();
  });
});

describe("composeFeatures", () => {
  it("trims and drops blank entries from the typed feature list", () => {
    expect(composeFeatures(draft({ features: [" Priority booking ", "", "  "] }))).toEqual(["Priority booking"]);
  });

  it("returns an empty list when no features were typed", () => {
    expect(composeFeatures(draft({ features: [] }))).toEqual([]);
  });
});
