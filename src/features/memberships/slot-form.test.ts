import { describe, expect, it } from "vitest";
import {
  ALL_DAYS,
  WEEKDAYS,
  sameDays,
  validateSlotSelection,
  describeBatchOption,
  toNewBatchPayload,
  type SlotSelection,
} from "@/features/memberships/slot-form";
import type { AssignableBatch } from "@/features/memberships/types";

const draft = {
  facilitySportId: "fs-1",
  courtId: "court-1",
  daysOfWeek: [1, 2, 3, 4, 5],
  startTime: "06:00",
  endTime: "07:00",
  capacity: "10",
};

describe("sameDays", () => {
  it("is order-insensitive", () => {
    expect(sameDays([1, 2, 3, 4, 5], [5, 4, 3, 2, 1])).toBe(true);
    expect(sameDays([1, 2], [1, 2, 3])).toBe(false);
  });
});

describe("validateSlotSelection", () => {
  it("accepts 'none'", () => {
    expect(validateSlotSelection({ kind: "none" })).toBeNull();
  });
  it("accepts a well-formed new slot", () => {
    expect(validateSlotSelection({ kind: "new", draft })).toBeNull();
  });
  it("rejects a new slot with no court", () => {
    expect(validateSlotSelection({ kind: "new", draft: { ...draft, courtId: "" } })).toMatch(/court/i);
  });
  it("rejects a new slot with no days", () => {
    expect(validateSlotSelection({ kind: "new", draft: { ...draft, daysOfWeek: [] } })).toMatch(/day/i);
  });
  it("rejects end <= start", () => {
    expect(validateSlotSelection({ kind: "new", draft: { ...draft, endTime: "06:00" } })).toMatch(/after/i);
  });
  it("rejects capacity below 1", () => {
    expect(validateSlotSelection({ kind: "new", draft: { ...draft, capacity: "0" } })).toMatch(/capacity/i);
    expect(validateSlotSelection({ kind: "new", draft: { ...draft, capacity: "" } })).toMatch(/capacity/i);
  });
  it("accepts an existing selection with a batchId", () => {
    expect(validateSlotSelection({ kind: "existing", batchId: "b1" } as SlotSelection)).toBeNull();
  });
  it("rejects an existing selection without a batchId", () => {
    expect(validateSlotSelection({ kind: "existing", batchId: "" } as SlotSelection)).toMatch(/slot/i);
  });
});

describe("describeBatchOption", () => {
  it("renders days, time range and capacity fraction", () => {
    const batch = {
      batchId: "b1", name: "Evening", planId: null, courtId: "c1", courtName: "Court 1",
      sportName: "Badminton", daysOfWeek: [1, 3, 5], startTime: "06:00:00", endTime: "07:00:00",
      capacity: 6, enrolledCount: 4, spare: 2,
    } as unknown as AssignableBatch;
    expect(describeBatchOption(batch)).toBe("Mon/Wed/Fri · 6:00 AM – 7:00 AM · 4 / 6");
  });
});

describe("toNewBatchPayload", () => {
  it("coerces capacity to a number and drops the sport-only field shape", () => {
    expect(toNewBatchPayload(draft)).toEqual({
      courtId: "court-1",
      facilitySportId: "fs-1",
      daysOfWeek: [1, 2, 3, 4, 5],
      startTime: "06:00",
      endTime: "07:00",
      capacity: 10,
    });
  });
});

it("ALL_DAYS and WEEKDAYS constants", () => {
  expect(ALL_DAYS).toEqual([0, 1, 2, 3, 4, 5, 6]);
  expect(WEEKDAYS).toEqual([1, 2, 3, 4, 5]);
});