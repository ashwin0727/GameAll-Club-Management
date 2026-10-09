import { describe, expect, it } from "vitest";
import { planSlotsFor } from "@/features/memberships/plan-slots";
import type { MembershipBatch } from "@/features/membership-sessions/types";

function batch(over: Partial<MembershipBatch>): MembershipBatch {
  return {
    id: "b1",
    facilityId: "f",
    planId: "plan-1",
    facilitySportId: "s",
    courtId: "c1",
    name: "x",
    daysOfWeek: [3, 1, 2],
    startTime: "07:00:00",
    endTime: "08:00:00",
    capacity: 999,
    isActive: true,
    createdAt: "",
    updatedAt: "",
    ...over,
  };
}

describe("planSlotsFor", () => {
  const courts = new Map([["c1", "Court 1"], ["c2", "Court 2"]]);

  it("returns only the plan's active batches, with trimmed clocks and sorted days", () => {
    const slots = planSlotsFor(
      [batch({}), batch({ id: "b2", planId: "other" }), batch({ id: "b3", isActive: false })],
      "plan-1",
      courts,
    );
    expect(slots).toEqual([
      { batchId: "b1", courtId: "c1", courtName: "Court 1", daysOfWeek: [1, 2, 3], startTime: "07:00", endTime: "08:00" },
    ]);
  });

  it("orders by court then start time", () => {
    const slots = planSlotsFor(
      [batch({ id: "a", courtId: "c2", startTime: "06:00" }), batch({ id: "b", startTime: "09:00" }), batch({ id: "c", startTime: "07:00" })],
      "plan-1",
      courts,
    );
    expect(slots.map((s) => s.batchId)).toEqual(["c", "b", "a"]);
  });

  it("is empty with no plan chosen", () => {
    expect(planSlotsFor([batch({})], "", courts)).toEqual([]);
  });
});
