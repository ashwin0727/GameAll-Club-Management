import { describe, expect, it } from "vitest";
import {
  billingIntervalLabel,
  currentBillingPeriod,
  durationLabel,
  memberCountByPlan,
  monthlyEquivalentInr,
  nextBillingDate,
  planBadges,
  planBand,
  planFeatures,
  planStats,
  planTagline,
  splitPlanName,
} from "@/features/memberships/plan-insights";
import type { MembershipListRow, MembershipPlan } from "@/features/memberships/types";

function plan(overrides: Partial<MembershipPlan>): MembershipPlan {
  return {
    id: "plan-1",
    facilityId: "facility-1",
    name: "Monthly Membership",
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
    createdAt: "2026-09-10T00:00:00Z",
    ...overrides,
  };
}

function row(overrides: Partial<MembershipListRow>): MembershipListRow {
  return {
    membershipId: "m1",
    memberId: "member-1",
    memberName: "Test Member",
    memberPhone: "9999999999",
    memberEmail: null,
    planId: "plan-1",
    planName: "Monthly Membership",
    monthlyPriceInr: 2500,
    status: "active",
    startDate: "2026-09-01",
    endDate: "2026-10-01",
    slot: null,
    ...overrides,
  };
}

describe("planBand / durationLabel / monthlyEquivalentInr", () => {
  it("bands a plan by its length", () => {
    expect(planBand(30)).toBe("Monthly");
    expect(planBand(90)).toBe("3 Months");
    expect(planBand(180)).toBe("6 Months");
    expect(planBand(365)).toBe("1 Year");
    expect(planBand(900)).toBe("Others");
  });

  it("labels the length in whole months", () => {
    expect(durationLabel(30)).toBe("1 Month");
    expect(durationLabel(90)).toBe("3 Months");
    expect(durationLabel(365)).toBe("12 Months");
  });

  it("works a price back to a per-month figure", () => {
    expect(monthlyEquivalentInr(2500, 30)).toBe(2500);
    expect(monthlyEquivalentInr(7000, 90)).toBe(2333);
    expect(monthlyEquivalentInr(20000, 365)).toBe(1667);
  });

  it("never divides by a zero-month duration", () => {
    expect(monthlyEquivalentInr(500, 0)).toBe(500);
    expect(durationLabel(0)).toBe("1 Month");
  });
});

describe("planTagline / planFeatures", () => {
  it("describes the plan by its band", () => {
    expect(planTagline(30)).toBe("Perfect for regular players");
    expect(planTagline(365)).toBe("Best for long-term players");
  });

  it("prefers the plan's own saved features", () => {
    expect(planFeatures(plan({ features: ["Towel service"] }))).toEqual(["Towel service"]);
  });

  it("falls back to the TIME_BASED defaults for a fixed-duration plan", () => {
    expect(planFeatures(plan({ planType: "TIME_BASED" }))).toEqual([
      "Fixed membership period",
      "One-time payment",
      "Valid until expiry",
      "Manual renewal required",
    ]);
  });

  it("falls back to the RECURRING defaults, with the actual billing interval, for a recurring plan", () => {
    expect(planFeatures(plan({ planType: "RECURRING", durationDays: 90 }))).toEqual([
      "Auto-renews every 3 months",
      "Recurring payment",
      "Continuous membership",
      "Cancel anytime",
    ]);
    expect(planFeatures(plan({ planType: "RECURRING", durationDays: 30 }))[0]).toBe("Auto-renews every month");
  });
});

describe("splitPlanName", () => {
  it("peels a trailing bracketed qualifier onto its own line", () => {
    expect(splitPlanName("Batch 1(5 A.M to 6 A.M)")).toEqual({ main: "Batch 1", detail: "(5 A.M to 6 A.M)" });
    expect(splitPlanName("Batch 2 (6 A.M to 7 A.M)")).toEqual({ main: "Batch 2", detail: "(6 A.M to 7 A.M)" });
  });

  it("leaves a plain name alone", () => {
    expect(splitPlanName("Monthly Membership")).toEqual({ main: "Monthly Membership", detail: null });
  });

  it("keeps a name that is only brackets in one piece", () => {
    expect(splitPlanName("(5 A.M to 6 A.M)")).toEqual({ main: "(5 A.M to 6 A.M)", detail: null });
  });

  it("ignores brackets that aren't at the end", () => {
    expect(splitPlanName("Batch (A) plan")).toEqual({ main: "Batch (A) plan", detail: null });
  });
});

describe("memberCountByPlan / planStats", () => {
  it("counts memberships per plan", () => {
    const counts = memberCountByPlan([row({}), row({}), row({ planId: "plan-2" })]);
    expect(counts.get("plan-1")).toBe(2);
    expect(counts.get("plan-2")).toBe(1);
  });

  it("totals plans, active plans and distinct members", () => {
    const plans = [plan({}), plan({ id: "plan-2", isActive: false })];
    const rows = [row({ memberId: "a" }), row({ memberId: "a" }), row({ memberId: "b" })];
    const stats = planStats(plans, rows);
    expect(stats.totalPlans).toBe(2);
    expect(stats.activePlans).toBe(1);
    expect(stats.totalMembers).toBe(2);
  });

  it("estimates monthly revenue from each plan's per-month price times its roster", () => {
    const plans = [plan({ id: "p1", priceInr: 2500, durationDays: 30 }), plan({ id: "p2", priceInr: 7000, durationDays: 90 })];
    const rows = [row({ planId: "p1" }), row({ planId: "p2" }), row({ planId: "p2" })];
    // 2500 * 1 + 2333 * 2
    expect(planStats(plans, rows).monthlyRevenueEstInr).toBe(2500 + 2333 * 2);
  });
});

describe("planBadges", () => {
  it("marks the plan with the most members, and the cheapest per month as best value", () => {
    const plans = [
      plan({ id: "p1", name: "Monthly", priceInr: 2500, durationDays: 30 }),
      plan({ id: "p2", name: "Yearly", priceInr: 20000, durationDays: 365 }),
    ];
    const rows = [row({ planId: "p1" }), row({ planId: "p1" }), row({ planId: "p2" })];
    const badges = planBadges(plans, rows);
    expect(badges.get("p1")).toBe("Most Popular");
    expect(badges.get("p2")).toBe("Best Value"); // 1667/month beats 2500/month
  });

  it("never puts both badges on one plan", () => {
    const plans = [plan({ id: "p1", priceInr: 100, durationDays: 30 }), plan({ id: "p2", priceInr: 9000, durationDays: 30 })];
    const rows = [row({ planId: "p1" })];
    const badges = planBadges(plans, rows);
    expect(badges.get("p1")).toBe("Most Popular");
    expect([...badges.values()].filter((b) => b === "Most Popular")).toHaveLength(1);
  });

  it("skips inactive plans and gives no popular badge when nobody has signed up", () => {
    const plans = [plan({ id: "p1", isActive: false }), plan({ id: "p2" })];
    const badges = planBadges(plans, []);
    expect(badges.has("p1")).toBe(false);
    expect(badges.get("p2")).toBe("Best Value");
    expect([...badges.values()]).not.toContain("Most Popular");
  });

  it("prefers a plan's own badgeText over either computed badge", () => {
    const plans = [
      plan({ id: "p1", name: "Monthly", priceInr: 2500, durationDays: 30, badgeText: "Editor's Pick" }),
      plan({ id: "p2", name: "Yearly", priceInr: 20000, durationDays: 365 }),
    ];
    const rows = [row({ planId: "p1" }), row({ planId: "p1" }), row({ planId: "p2" })];
    const badges = planBadges(plans, rows);
    expect(badges.get("p1")).toBe("Editor's Pick"); // would otherwise be "Most Popular"
    expect(badges.get("p2")).toBe("Best Value");
  });

  it("returns nothing when there are no active plans", () => {
    expect(planBadges([plan({ isActive: false })], []).size).toBe(0);
  });
});

describe("billingIntervalLabel", () => {
  it("reads as a cadence, not a duration", () => {
    expect(billingIntervalLabel(30)).toBe("every month");
    expect(billingIntervalLabel(90)).toBe("every 3 months");
    expect(billingIntervalLabel(365)).toBe("every 12 months");
  });
});

describe("nextBillingDate / currentBillingPeriod — plain day-count arithmetic", () => {
  it("adds the interval as days, not calendar months, so month-end starts land correctly", () => {
    // 31 Jan + 30 days = 2 Mar (not "31 Feb"), 28 Feb 2026 (non-leap) + 30 days = 30 Mar.
    expect(nextBillingDate("2026-01-31", 30)).toBe("2026-03-02");
    expect(nextBillingDate("2026-02-28", 30)).toBe("2026-03-30");
  });

  it("handles a leap-year February correctly", () => {
    // 2028 is a leap year — 1 Feb + 29 days = 1 Mar, crossing the leap day.
    expect(nextBillingDate("2028-02-01", 29)).toBe("2028-03-01");
  });

  it("covers the 1/3/6/12-month billing intervals", () => {
    expect(nextBillingDate("2026-09-01", 30)).toBe("2026-10-01");
    expect(nextBillingDate("2026-09-01", 90)).toBe("2026-11-30");
    expect(nextBillingDate("2026-09-01", 180)).toBe("2027-02-28");
    expect(nextBillingDate("2026-09-01", 365)).toBe("2027-09-01");
  });

  it("gives the current billing period as an inclusive [start, end] range", () => {
    expect(currentBillingPeriod("2026-09-01", 30)).toEqual({ start: "2026-09-01", end: "2026-09-30" });
  });
});
