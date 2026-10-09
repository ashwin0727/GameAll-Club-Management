import { describe, expect, it } from "vitest";
import { findDuplicateMember, findDuplicatePlan, normalizePhone, slotSetSignature } from "@/features/memberships/duplicate-guards";
import type { MembershipListRow } from "@/features/memberships/types";

const slot = (days: number[], start: string, end: string, courtId = "c1") => ({ courtId, daysOfWeek: days, startTime: start, endTime: end });
const monFri = [1, 2, 3, 4, 5];

describe("findDuplicatePlan", () => {
  const plans = [{ id: "p1", name: "Morning", slots: [slot(monFri, "05:00", "06:00")] }];

  it("flags the exact same days and timing", () => {
    expect(findDuplicatePlan([slot(monFri, "05:00", "06:00")], plans)).toEqual({ id: "p1", name: "Morning" });
  });
  it("ignores day order and a seconds suffix", () => {
    expect(findDuplicatePlan([slot([5, 4, 3, 2, 1], "05:00:00", "06:00:00")], plans)?.id).toBe("p1");
  });
  it("allows the same hours on different days (Mon-Sun)", () => {
    expect(findDuplicatePlan([slot([0, 1, 2, 3, 4, 5, 6], "05:00", "06:00")], plans)).toBeNull();
  });
  it("allows different hours or a different court", () => {
    expect(findDuplicatePlan([slot(monFri, "06:00", "07:00")], plans)).toBeNull();
    expect(findDuplicatePlan([slot(monFri, "05:00", "06:00", "c2")], plans)).toBeNull();
  });
  it("needs the whole slot set to match, not just one slot", () => {
    expect(findDuplicatePlan([slot(monFri, "05:00", "06:00"), slot(monFri, "18:00", "19:00")], plans)).toBeNull();
  });
  it("skips the plan being edited and empty drafts", () => {
    expect(findDuplicatePlan([slot(monFri, "05:00", "06:00")], plans, "p1")).toBeNull();
    expect(findDuplicatePlan([], plans)).toBeNull();
  });
  it("signature ignores slot order", () => {
    const a = slot(monFri, "05:00", "06:00");
    const b = slot([6], "07:00", "08:00");
    expect(slotSetSignature([a, b])).toBe(slotSetSignature([b, a]));
  });
});

describe("findDuplicateMember", () => {
  const row = (over: Partial<MembershipListRow>): MembershipListRow =>
    ({
      membershipId: "m1",
      memberId: "x",
      memberName: "Arun",
      memberPhone: "9876543210",
      memberEmail: null,
      planId: "p1",
      planName: "Morning",
      monthlyPriceInr: 1,
      status: "active",
      startDate: "2026-10-01",
      endDate: "2026-10-31",
      slot: null,
      ...over,
    }) as MembershipListRow;
  const plan = { id: "p1", name: "Morning" };

  it("flags the same phone on the same plan, however it is typed", () => {
    expect(findDuplicateMember([row({})], plan, "+91 98765 43210")?.membershipId).toBe("m1");
    expect(findDuplicateMember([row({})], plan, "9876543210")?.membershipId).toBe("m1");
  });
  it("allows the same person on a different plan", () => {
    expect(findDuplicateMember([row({ planId: "p2", planName: "Evening" })], plan, "9876543210")).toBeNull();
  });
  it("allows a different person, and rejoining after a lapsed membership", () => {
    expect(findDuplicateMember([row({ memberPhone: "9000000000" })], plan, "9876543210")).toBeNull();
    expect(findDuplicateMember([row({ status: "inactive" })], plan, "9876543210")).toBeNull();
  });
  it("matches by plan name when the membership has no plan id", () => {
    expect(findDuplicateMember([row({ planId: "" })], plan, "9876543210")).not.toBeNull();
  });
  it("ignores a too-short number while it is still being typed", () => {
    expect(findDuplicateMember([row({})], plan, "98")).toBeNull();
    expect(normalizePhone("+91 98765 43210")).toBe("9876543210");
  });
});
