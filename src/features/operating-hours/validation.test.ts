import { describe, expect, it } from "vitest";
import {
  hasOverlappingSlots,
  isOvernightSlot,
  normalizeTime,
  sortTimeSlots,
  validateOperatingDay,
  validateSchedule,
  validateTimeSlot,
} from "@/features/operating-hours/validation";
import type { OperatingDay, OperatingTimeSlot } from "@/features/operating-hours/types";

function slot(startTime: string, endTime: string, overrides: Partial<OperatingTimeSlot> = {}): OperatingTimeSlot {
  return { startTime, endTime, crossesMidnight: false, displayOrder: 0, ...overrides };
}

describe("normalizeTime", () => {
  it("zero-pads a short time string", () => {
    expect(normalizeTime("6:5")).toBe("06:05");
  });
});

describe("isOvernightSlot", () => {
  it("detects a slot that ends before it starts as overnight", () => {
    expect(isOvernightSlot(slot("18:00", "02:00"))).toBe(true);
  });

  it("does not flag a normal same-day slot", () => {
    expect(isOvernightSlot(slot("06:00", "23:00"))).toBe(false);
  });
});

describe("sortTimeSlots", () => {
  it("sorts slots chronologically by start time", () => {
    const sorted = sortTimeSlots([slot("16:00", "20:00"), slot("09:00", "13:00")]);
    expect(sorted.map((s) => s.startTime)).toEqual(["09:00", "16:00"]);
  });
});

describe("hasOverlappingSlots", () => {
  it("allows non-overlapping slots (morning + evening)", () => {
    expect(hasOverlappingSlots([slot("06:00", "12:00"), slot("16:00", "23:00")])).toBe(false);
  });

  it("detects overlapping slots", () => {
    expect(hasOverlappingSlots([slot("06:00", "14:00"), slot("13:00", "23:00")])).toBe(true);
  });

  it("detects an overnight slot overlapping an early-morning slot the next day", () => {
    expect(hasOverlappingSlots([slot("22:00", "03:00"), slot("02:00", "06:00")])).toBe(true);
  });

  it("does not flag an overnight slot against a same-evening slot that doesn't actually overlap", () => {
    expect(hasOverlappingSlots([slot("22:00", "02:00"), slot("08:00", "12:00")])).toBe(false);
  });
});

describe("validateTimeSlot", () => {
  it("requires an opening time", () => {
    expect(validateTimeSlot(slot("", "23:00"))).toMatch(/opening time/i);
  });

  it("requires a closing time", () => {
    expect(validateTimeSlot(slot("06:00", ""))).toMatch(/closing time/i);
  });

  it("rejects identical start and end times", () => {
    expect(validateTimeSlot(slot("06:00", "06:00"))).toMatch(/cannot be the same/i);
  });

  it("accepts a valid slot", () => {
    expect(validateTimeSlot(slot("06:00", "23:00"))).toBeNull();
  });
});

describe("validateOperatingDay", () => {
  const base: Pick<OperatingDay, "isClosed" | "is24Hours" | "slots"> = {
    isClosed: false,
    is24Hours: false,
    slots: [],
  };

  it("a closed day is always valid, regardless of slots", () => {
    expect(validateOperatingDay({ ...base, isClosed: true })).toBeNull();
  });

  it("a 24-hour day is valid with no slots", () => {
    expect(validateOperatingDay({ ...base, is24Hours: true })).toBeNull();
  });

  it("an open day with zero slots is invalid", () => {
    expect(validateOperatingDay(base)).toMatch(/at least one time slot/i);
  });

  it("an open day with valid, non-overlapping slots is valid", () => {
    expect(validateOperatingDay({ ...base, slots: [slot("06:00", "12:00"), slot("16:00", "23:00")] })).toBeNull();
  });

  it("an open day with overlapping slots is invalid", () => {
    expect(validateOperatingDay({ ...base, slots: [slot("06:00", "14:00"), slot("13:00", "23:00")] })).toMatch(
      /cannot overlap/i,
    );
  });
});

describe("validateSchedule", () => {
  it("collects one error per invalid day, keyed by day of week", () => {
    const days: OperatingDay[] = [
      { dayOfWeek: 0, isClosed: true, is24Hours: false, slots: [] },
      { dayOfWeek: 1, isClosed: false, is24Hours: false, slots: [] },
    ];
    const result = validateSchedule(days);
    expect(result.isValid).toBe(false);
    expect(result.dayErrors[1]).toMatch(/at least one time slot/i);
    expect(result.dayErrors[0]).toBeUndefined();
  });

  it("is valid when every day is closed, 24-hour, or has valid slots", () => {
    const days: OperatingDay[] = [
      { dayOfWeek: 0, isClosed: true, is24Hours: false, slots: [] },
      { dayOfWeek: 1, isClosed: false, is24Hours: true, slots: [] },
      { dayOfWeek: 2, isClosed: false, is24Hours: false, slots: [slot("06:00", "23:00")] },
    ];
    expect(validateSchedule(days).isValid).toBe(true);
  });
});