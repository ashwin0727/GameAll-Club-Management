import { describe, expect, it } from "vitest";
import {
  duplicateName,
  filterPlanMembers,
  initialsOf,
  membersOfPlan,
  paginate,
  planRevenue,
  slotsByDay,
} from "@/features/memberships/plan-detail-data";
import type { PlanSlot } from "@/features/memberships/plan-slots";
import type { MembershipListRow } from "@/features/memberships/types";

const slot = (id: string, days: number[], start: string): PlanSlot => ({
  batchId: id,
  courtId: "c",
  courtName: "Court 1",
  daysOfWeek: days,
  startTime: start,
  endTime: "08:00",
});

const row = (over: Partial<MembershipListRow>): MembershipListRow =>
  ({
    membershipId: "m",
    memberId: "x",
    memberName: "Arun Kumar",
    memberPhone: "9876543210",
    memberEmail: null,
    planId: "p1",
    planName: "Batch 2",
    monthlyPriceInr: 1000,
    status: "active",
    startDate: "2026-10-01",
    endDate: "2026-10-31",
    slot: null,
    ...over,
  }) as MembershipListRow;

describe("plan detail data", () => {
  it("lists all seven days, Monday first, empty for days with no slot", () => {
    const rows = slotsByDay([slot("a", [1, 2, 3, 4, 5], "06:00")]);
    expect(rows.map((r) => r.label)).toEqual(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]);
    expect(rows[0]!.slots).toHaveLength(1);
    expect(rows[5]!.slots).toEqual([]);
    expect(rows[6]!.slots).toEqual([]);
  });

  it("orders a day's slots by start time", () => {
    const rows = slotsByDay([slot("late", [1], "18:00"), slot("early", [1], "06:00")]);
    expect(rows[0]!.slots.map((s) => s.batchId)).toEqual(["early", "late"]);
  });

  it("picks a plan's members, newest first", () => {
    const rows = [row({ membershipId: "a", startDate: "2026-09-01" }), row({ membershipId: "b", startDate: "2026-10-05" }), row({ membershipId: "c", planId: "p2" })];
    expect(membersOfPlan(rows, { id: "p1", name: "Batch 2" }).map((r) => r.membershipId)).toEqual(["b", "a"]);
  });

  it("also picks up memberships that only carry the plan's name", () => {
    const rows = [row({ membershipId: "n", planId: "" as never, planName: "batch 2" }), row({ membershipId: "o", planId: "p9", planName: "Batch 2" })];
    expect(membersOfPlan(rows, { id: "p1", name: "Batch 2" }).map((r) => r.membershipId)).toEqual(["n"]);
  });

  it("filters by search and status", () => {
    const rows = [row({ membershipId: "a" }), row({ membershipId: "b", memberName: "Priya Sharma", status: "expired" as never })];
    expect(filterPlanMembers(rows, "priya", "all").map((r) => r.membershipId)).toEqual(["b"]);
    expect(filterPlanMembers(rows, "", "active").map((r) => r.membershipId)).toEqual(["a"]);
    expect(filterPlanMembers(rows, "", "inactive").map((r) => r.membershipId)).toEqual(["b"]);
    expect(filterPlanMembers(rows, "98765", "all")).toHaveLength(2);
  });

  it("paginates and clamps the page", () => {
    const items = [1, 2, 3, 4, 5, 6, 7];
    expect(paginate(items, 1, 5)).toEqual({ items: [1, 2, 3, 4, 5], pages: 2, page: 1 });
    expect(paginate(items, 9, 5)).toEqual({ items: [6, 7], pages: 2, page: 2 });
    expect(paginate([], 1, 5).pages).toBe(1);
  });

  it("totals only paid payments and averages per paying member", () => {
    const r = planRevenue([
      { membershipId: "a", amountMinor: 100000, status: "paid" },
      { membershipId: "b", amountMinor: 100000, status: "paid" },
      { membershipId: "c", amountMinor: 100000, status: "failed" },
    ]);
    expect(r).toEqual({ totalMinor: 200000, members: 2, avgPerMemberMinor: 100000 });
    expect(planRevenue([]).avgPerMemberMinor).toBe(0);
  });

  it("initials and duplicate name", () => {
    expect(initialsOf("Arun Kumar")).toBe("AK");
    expect(duplicateName("Batch 2")).toBe("Batch 2 (Copy)");
  });
});

import { validateSlotEdit } from "@/features/memberships/plan-detail-data";

describe("validateSlotEdit", () => {
  const ok = { days: [1], startTime: "07:00", endTime: "08:00", capacity: 10, enrolled: 0 };
  it("accepts a valid slot", () => expect(validateSlotEdit(ok)).toBeNull());
  it("needs a day, a later end, and a sane capacity", () => {
    expect(validateSlotEdit({ ...ok, days: [] })).toMatch(/day/);
    expect(validateSlotEdit({ ...ok, endTime: "07:00" })).toMatch(/end time/);
    expect(validateSlotEdit({ ...ok, capacity: 0 })).toMatch(/at least 1/);
    expect(validateSlotEdit({ ...ok, capacity: null })).toMatch(/at least 1/);
  });
  it("won't go below the members already on the slot", () => {
    expect(validateSlotEdit({ ...ok, capacity: 3, enrolled: 5 })).toMatch(/5 members are already/);
    expect(validateSlotEdit({ ...ok, capacity: 5, enrolled: 5 })).toBeNull();
  });
});
