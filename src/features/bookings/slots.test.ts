import { describe, expect, it } from "vitest";
import { computeAvailableSlots } from "@/features/bookings/slots";
import type { OperatingDay } from "@/features/operating-hours/types";

const monday = new Date(2026, 0, 5); // a Monday, local time, no DST concerns

function day(overrides: Partial<OperatingDay> = {}): OperatingDay {
  return {
    dayOfWeek: 1,
    isClosed: false,
    is24Hours: false,
    slots: [{ startTime: "09:00", endTime: "12:00", crossesMidnight: false, displayOrder: 0 }],
    ...overrides,
  };
}

describe("computeAvailableSlots", () => {
  it("is empty when the day is closed", () => {
    expect(computeAvailableSlots(monday, day({ isClosed: true }), [])).toHaveLength(0);
  });

  it("generates one slot per hour across the open window", () => {
    const slots = computeAvailableSlots(monday, day(), []);
    expect(slots).toHaveLength(3);
    expect(slots.every((s) => s.available)).toBe(true);
  });

  it("caps a 24-hour day at the local calendar day boundary", () => {
    const slots = computeAvailableSlots(monday, day({ is24Hours: true }), []);
    expect(slots).toHaveLength(24);
    expect(new Date(slots[0]!.startTime).getHours()).toBe(0);
    expect(new Date(slots[23]!.endTime).getHours()).toBe(0); // rolls to midnight next day
  });

  it("marks a slot unavailable when an existing booking overlaps it", () => {
    const existing = [{ startTime: new Date(2026, 0, 5, 10, 0).toISOString(), endTime: new Date(2026, 0, 5, 11, 0).toISOString() }];
    const slots = computeAvailableSlots(monday, day(), existing);
    const overlapping = slots.find((s) => new Date(s.startTime).getHours() === 10);
    const untouched = slots.find((s) => new Date(s.startTime).getHours() === 9);
    expect(overlapping?.available).toBe(false);
    expect(untouched?.available).toBe(true);
  });

  it("extends an overnight slot's window but still caps it at end-of-day", () => {
    const overnight = day({
      slots: [{ startTime: "22:00", endTime: "02:00", crossesMidnight: true, displayOrder: 0 }],
    });
    const slots = computeAvailableSlots(monday, overnight, []);
    // 22:00-23:00 and 23:00-24:00 fit; the 00:00-02:00 remainder belongs to the next calendar day.
    expect(slots).toHaveLength(2);
  });
});