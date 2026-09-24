import { describe, expect, it } from "vitest";
import {
  activeInactiveTrend,
  activeMembersChangePct,
  axisTicks,
  bucketForRow,
  expiringSoon,
  expiringSoonChangePct,
  inactiveChangePct,
  inactiveMembers,
  membersDeltaAbs,
  planDistribution,
  rowStatus,
  summaryFromRows,
} from "@/features/memberships/dashboard-stats";
import type { MembershipListRow, MembershipListStatus } from "@/features/memberships/types";

const NOW = new Date("2026-09-15T00:00:00Z");

function row(overrides: Partial<MembershipListRow>): MembershipListRow {
  return {
    membershipId: overrides.membershipId ?? "m1",
    memberId: "member-1",
    memberName: "Test Member",
    memberPhone: "9999999999",
    memberEmail: null,
    planId: "plan-1",
    planName: "Plan",
    monthlyPriceInr: 1000,
    status: "active" as MembershipListStatus,
    startDate: "2026-01-01",
    endDate: "2026-02-01",
    slot: null,
    ...overrides,
  };
}

describe("bucketForRow / planDistribution", () => {
  it("buckets by the billed period length", () => {
    expect(bucketForRow(row({ startDate: "2026-01-01", endDate: "2026-01-30" }))).toBe("Monthly");
    expect(bucketForRow(row({ startDate: "2026-01-01", endDate: "2026-04-01" }))).toBe("3 Months");
    expect(bucketForRow(row({ startDate: "2026-01-01", endDate: "2026-07-01" }))).toBe("6 Months");
    expect(bucketForRow(row({ startDate: "2026-01-01", endDate: "2027-01-01" }))).toBe("1 Year");
    expect(bucketForRow(row({ startDate: "2026-01-01", endDate: "2028-01-01" }))).toBe("Others");
  });

  it("counts and percentages every bucket, including empty ones", () => {
    const rows = [
      row({ startDate: "2026-01-01", endDate: "2026-01-30" }),
      row({ startDate: "2026-01-01", endDate: "2026-01-30" }),
      row({ startDate: "2026-01-01", endDate: "2027-01-01" }),
    ];
    const dist = planDistribution(rows);
    expect(dist.find((d) => d.bucket === "Monthly")).toMatchObject({ count: 2, percent: (2 / 3) * 100 });
    expect(dist.find((d) => d.bucket === "1 Year")).toMatchObject({ count: 1, percent: (1 / 3) * 100 });
    expect(dist.find((d) => d.bucket === "3 Months")).toMatchObject({ count: 0, percent: 0 });
  });

  it("returns all-zero percentages for no rows", () => {
    const dist = planDistribution([]);
    expect(dist.every((d) => d.count === 0 && d.percent === 0)).toBe(true);
  });
});

describe("expiringSoon", () => {
  it("includes non-inactive rows ending within 5 days", () => {
    const rows = [
      row({ membershipId: "in-window", endDate: "2026-09-18" }),
      row({ membershipId: "too-far", endDate: "2026-09-25" }),
      row({ membershipId: "already-past", endDate: "2026-09-01" }),
      row({ membershipId: "inactive-but-in-window", status: "inactive", endDate: "2026-09-18" }),
    ];
    const result = expiringSoon(rows, NOW).map((r) => r.membershipId);
    expect(result).toEqual(["in-window"]);
  });
});

describe("inactiveMembers", () => {
  it("only returns status === inactive", () => {
    const rows = [row({ status: "inactive" }), row({ status: "active" }), row({ status: "payment_incomplete" })];
    expect(inactiveMembers(rows)).toHaveLength(1);
  });
});

describe("expiringSoonChangePct / inactiveChangePct", () => {
  it("returns null when the prior cohort was empty", () => {
    const rows = [row({ endDate: "2026-09-25" })];
    expect(expiringSoonChangePct(rows, NOW)).toBeNull();
    expect(inactiveChangePct(rows, NOW)).toBeNull();
  });

  it("computes a percent change against the 30-day-ago cohort", () => {
    // 30 days before NOW (2026-09-15) is 2026-08-16; a row already started and ending within
    // that 5-day window, [2026-08-16, 2026-08-21], counted as "expiring soon" back then.
    const rows = [
      row({ membershipId: "was-expiring-then", startDate: "2026-08-01", endDate: "2026-08-20" }),
      row({ membershipId: "expiring-now", startDate: "2026-08-01", endDate: "2026-09-18" }),
    ];
    // before: 1 ("was-expiring-then"), current: 1 ("expiring-now") -> 0% change
    expect(expiringSoonChangePct(rows, NOW)).toBe(0);
  });

  it("computes inactive change from rows already past their end date 30 days ago", () => {
    const rows = [
      row({ membershipId: "expired-long-ago", status: "inactive", endDate: "2026-07-01" }),
      row({ membershipId: "expired-recently", status: "inactive", endDate: "2026-09-05" }),
    ];
    // before (endDate < 2026-08-16): 1, current (status inactive): 2 -> +100%
    expect(inactiveChangePct(rows, NOW)).toBe(100);
  });
});

describe("activeMembersChangePct", () => {
  it("returns null with no prior cohort", () => {
    const rows = [row({ startDate: "2026-09-01", endDate: "2026-10-01" })];
    expect(activeMembersChangePct(rows, 1, NOW)).toBeNull();
  });

  it("compares the current active count against the 30-day-ago cohort", () => {
    const rows = [
      row({ startDate: "2026-01-01", endDate: "2026-12-31" }), // active both then and now
      row({ startDate: "2026-01-01", endDate: "2026-12-31" }), // active both then and now
    ];
    // before: 2, current passed as 3 -> +50%
    expect(activeMembersChangePct(rows, 3, NOW)).toBe(50);
  });
});

describe("membersDeltaAbs", () => {
  it("returns null when there's no change percent", () => {
    expect(membersDeltaAbs(124, null)).toBeNull();
  });

  it("recovers the absolute change from current value and percent", () => {
    // 124 members at +12% implies ~111 before, so +13.
    expect(membersDeltaAbs(124, 11.71171171171171)).toBe(13);
  });

  it("handles a negative change", () => {
    // 90 at -10% implies 100 before, so -10.
    expect(membersDeltaAbs(90, -10)).toBe(-10);
  });
});

describe("rowStatus", () => {
  it("calls out a still-running membership that lapses within 5 days", () => {
    expect(rowStatus(row({ endDate: "2026-09-18" }), NOW)).toBe("expiring");
    expect(rowStatus(row({ endDate: "2026-12-25" }), NOW)).toBe("active");
  });

  it("leaves the membership's own status alone when it isn't active", () => {
    expect(rowStatus(row({ status: "inactive", endDate: "2026-09-25" }), NOW)).toBe("inactive");
    expect(rowStatus(row({ status: "payment_incomplete", endDate: "2026-09-25" }), NOW)).toBe("payment_incomplete");
  });

  it("doesn't call an already-lapsed date expiring", () => {
    expect(rowStatus(row({ endDate: "2026-09-01" }), NOW)).toBe("active");
  });
});

describe("axisTicks", () => {
  it("gives four round gridlines topping out at or above the tallest bar", () => {
    expect(axisTicks(124)).toEqual([0, 50, 100, 150]);
    expect(axisTicks(3)).toEqual([0, 1, 2, 3]);
    expect(axisTicks(7)).toEqual([0, 5, 10, 15]);
  });

  it("never collapses to a zero-height axis", () => {
    expect(axisTicks(0)).toEqual([0, 1, 2, 3]);
  });

  it("keeps the top tick at or above the value", () => {
    for (const v of [1, 9, 33, 260, 1234]) {
      const ticks = axisTicks(v);
      expect(ticks[3]).toBeGreaterThanOrEqual(v);
      expect(ticks).toHaveLength(4);
    }
  });

  it("splits into the requested number of divisions, for money-sized values", () => {
    expect(axisTicks(285_000, 4)).toEqual([0, 100_000, 200_000, 300_000, 400_000]);
    expect(axisTicks(0, 4)).toHaveLength(5);
  });
});

describe("activeInactiveTrend", () => {
  it("returns the requested number of months, oldest first, labelled by month", () => {
    const rows = [row({ startDate: "2026-01-01", endDate: "2026-12-31" })];
    const trend = activeInactiveTrend(rows, NOW, 3);
    expect(trend).toHaveLength(3);
    expect(trend.map((p) => p.label)).toEqual(["Jul", "Aug", "Sep"]);
    expect(trend.every((p) => p.active === 1 && p.inactive === 0)).toBe(true);
  });

  it("marks a membership inactive for months after it ended", () => {
    const rows = [row({ startDate: "2026-01-01", endDate: "2026-07-15" })];
    const trend = activeInactiveTrend(rows, NOW, 3);
    // Jul: covers month-end (Jul 31)? endDate 2026-07-15 < Jul 31 -> already inactive by Jul end.
    expect(trend[0]).toMatchObject({ label: "Jul", active: 0, inactive: 1 });
    expect(trend[2]).toMatchObject({ label: "Sep", active: 0, inactive: 1 });
  });
});

describe("summaryFromRows", () => {
  it("counts totals, active members and revenue from active rows only", () => {
    const rows = [
      row({ membershipId: "m1", status: "active", monthlyPriceInr: 1000 }),
      row({ membershipId: "m2", status: "active", monthlyPriceInr: 2000 }),
      row({ membershipId: "m3", status: "inactive", monthlyPriceInr: 500 }),
    ];
    const summary = summaryFromRows(rows, NOW);
    expect(summary.totalMembers).toBe(3);
    expect(summary.activeMembers).toBe(2);
    expect(summary.activePctOfTotal).toBeCloseTo((2 / 3) * 100);
    expect(summary.revenueInr).toBe(3000);
  });

  it("returns null change percentages when nothing existed 30 days ago", () => {
    const rows = [row({ membershipId: "m1", startDate: "2026-09-10", endDate: "2026-10-10" })];
    const summary = summaryFromRows(rows, NOW);
    expect(summary.totalMembersChangePct).toBeNull();
    expect(summary.revenueChangePct).toBeNull();
  });

  it("reports growth once a membership already existed 30+ days ago", () => {
    const rows = [
      row({ membershipId: "m1", startDate: "2026-01-01", endDate: "2026-12-31", monthlyPriceInr: 1000 }),
      row({ membershipId: "m2", startDate: "2026-09-01", endDate: "2026-10-01", monthlyPriceInr: 1000 }),
    ];
    const summary = summaryFromRows(rows, NOW);
    expect(summary.totalMembersChangePct).toBeGreaterThan(0);
    expect(summary.revenueChangePct).toBeGreaterThan(0);
  });

  it("handles an empty row set without dividing by zero", () => {
    const summary = summaryFromRows([], NOW);
    expect(summary).toEqual({
      totalMembers: 0,
      totalMembersChangePct: null,
      activeMembers: 0,
      activePctOfTotal: 0,
      revenueInr: 0,
      revenueChangePct: null,
    });
  });
});
