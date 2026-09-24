import { describe, expect, it } from "vitest";
import { courtsForSport, membershipRowsForSport, planIdsForSport, plansForSport, scheduleRowsForSport } from "@/features/memberships/sport-scope";
import type { MembershipBatch } from "@/features/membership-sessions/types";
import type { MemberScheduleRow, MembershipListRow, MembershipPlan } from "@/features/memberships/types";

function batch(overrides: Partial<MembershipBatch> = {}): MembershipBatch {
  return {
    id: "b1",
    facilityId: "f1",
    planId: "plan-1",
    facilitySportId: "badminton",
    courtId: "court-1",
    name: "Batch",
    daysOfWeek: [1, 2, 3],
    startTime: "07:00",
    endTime: "08:00",
    capacity: 4,
    isActive: true,
    createdAt: "2026-01-01T00:00:00Z",
    updatedAt: "2026-01-01T00:00:00Z",
    ...overrides,
  };
}

function plan(overrides: Partial<MembershipPlan> = {}): MembershipPlan {
  return {
    id: "plan-1",
    facilityId: "f1",
    name: "Monthly",
    description: null,
    category: null,
    planType: "TIME_BASED",
    priceInr: 2500,
    durationDays: 30,
    joiningFeeInr: null,
    securityDepositInr: null,
    badgeText: null,
    features: [],
    isActive: true,
    createdAt: "2026-01-01T00:00:00Z",
    ...overrides,
  };
}

function membershipRow(overrides: Partial<MembershipListRow> = {}): MembershipListRow {
  return {
    membershipId: "m1",
    memberId: "member-1",
    memberName: "Alex",
    memberPhone: "9999999999",
    memberEmail: null,
    planId: "plan-1",
    planName: "Monthly",
    monthlyPriceInr: 2500,
    status: "active",
    startDate: "2026-01-01",
    endDate: "2026-02-01",
    slot: null,
    ...overrides,
  };
}

function scheduleRow(overrides: Partial<MemberScheduleRow> = {}): MemberScheduleRow {
  return {
    memberId: "member-1",
    fullName: "Alex",
    phone: "9999999999",
    status: "ACTIVE",
    membershipId: "m1",
    batchId: "b1",
    batchName: "Batch",
    courtId: "court-1",
    courtName: "Court 1",
    facilitySportId: "badminton",
    sportName: "Badminton",
    daysOfWeek: [1, 2, 3],
    startTime: "07:00",
    endTime: "08:00",
    ...overrides,
  };
}

describe("courtsForSport", () => {
  it("keeps only courts on the active sport", () => {
    const courts = [{ id: "c1", facilitySportId: "badminton" }, { id: "c2", facilitySportId: "cricket" }];
    expect(courtsForSport(courts, "badminton").map((c) => c.id)).toEqual(["c1"]);
  });

  it("passes everything through when there's no sport to filter by", () => {
    const courts = [{ id: "c1", facilitySportId: "badminton" }, { id: "c2", facilitySportId: "cricket" }];
    expect(courtsForSport(courts, null)).toHaveLength(2);
  });
});

describe("planIdsForSport / plansForSport", () => {
  it("only counts a plan as belonging to a sport once one of its batches is on that sport", () => {
    const batches = [batch({ planId: "plan-1", facilitySportId: "badminton" }), batch({ id: "b2", planId: "plan-2", facilitySportId: "cricket" })];
    expect(planIdsForSport(batches, "badminton")).toEqual(new Set(["plan-1"]));
  });

  it("drops a plan with no batches on the active sport at all, even if it has batches elsewhere", () => {
    const plans = [plan({ id: "plan-1" }), plan({ id: "plan-2", name: "Turf Plan" })];
    const batches = [batch({ planId: "plan-1", facilitySportId: "badminton" }), batch({ id: "b2", planId: "plan-2", facilitySportId: "cricket" })];
    expect(plansForSport(plans, batches, "badminton").map((p) => p.id)).toEqual(["plan-1"]);
  });

  it("returns every plan unfiltered when sportId is null", () => {
    const plans = [plan({ id: "plan-1" }), plan({ id: "plan-2" })];
    expect(plansForSport(plans, [], null)).toHaveLength(2);
  });

  it("a plan with no batches yet belongs to no sport, and drops out once a filter is active", () => {
    const plans = [plan({ id: "plan-1" })];
    expect(plansForSport(plans, [], "badminton")).toHaveLength(0);
  });
});

describe("membershipRowsForSport", () => {
  it("keeps only rows whose plan has a batch on the active sport", () => {
    const rows = [membershipRow({ planId: "plan-1" }), membershipRow({ membershipId: "m2", planId: "plan-2" })];
    const batches = [batch({ planId: "plan-1", facilitySportId: "badminton" }), batch({ id: "b2", planId: "plan-2", facilitySportId: "cricket" })];
    expect(membershipRowsForSport(rows, batches, "badminton").map((r) => r.membershipId)).toEqual(["m1"]);
  });
});

describe("scheduleRowsForSport", () => {
  it("filters directly by the row's own facilitySportId", () => {
    const rows = [scheduleRow({ facilitySportId: "badminton" }), scheduleRow({ batchId: "b2", facilitySportId: "cricket" })];
    expect(scheduleRowsForSport(rows, "badminton")).toHaveLength(1);
  });

  it("returns everything when sportId is null", () => {
    const rows = [scheduleRow({ facilitySportId: "badminton" }), scheduleRow({ batchId: "b2", facilitySportId: "cricket" })];
    expect(scheduleRowsForSport(rows, null)).toHaveLength(2);
  });
});
