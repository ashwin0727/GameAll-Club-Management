import { describe, expect, it } from "vitest";
import { OVERVIEW_METRICS, buildOverviewCsv, metricDef, scopeWord, trendGranularity } from "@/features/reports/overview-metrics";
import type { ReportsOverviewMetrics } from "@/features/reports/types";

const metrics: ReportsOverviewMetrics = {
  totalRevenueMinor: 1_300_000,
  totalExpensesMinor: 635_000,
  netRevenueMinor: 665_000,
  guestBookings: 42,
  members: 17,
  programs: 3,
  coaches: 2,
  students: 25,
  guestBookingRevenueMinor: 400_000,
  membershipRevenueMinor: 700_000,
  coachingRevenueMinor: 200_000,
  coachingExpensesMinor: 90_000,
};

describe("overview metrics", () => {
  it("lists the twelve cards in the agreed order", () => {
    expect(OVERVIEW_METRICS.map((m) => m.title)).toEqual([
      "Total Revenue",
      "Total Expenses",
      "Net Revenue",
      "Total Guest Booking",
      "Total Members",
      "Total Program",
      "Total Coach",
      "Total Students",
      "Guest Booking Revenue",
      "Membership Revenue",
      "Coaching Revenue",
      "Coaching Expenses",
    ]);
  });

  it("words the scope: Overall under All Sports, Selected otherwise", () => {
    expect(scopeWord(false)).toBe("Overall");
    expect(scopeWord(true)).toBe("Selected");
    expect(metricDef("REVENUE").describe("Selected")).toBe("Selected revenue");
    expect(metricDef("REVENUE").heading("Overall")).toBe("Overall Revenue Trend");
  });

  it("picks day / week / month buckets from the span", () => {
    expect(trendGranularity({ from: "2026-10-01", to: "2026-10-31" })).toBe("daily");
    expect(trendGranularity({ from: "2026-08-01", to: "2026-10-31" })).toBe("weekly");
    expect(trendGranularity({ from: "2025-10-01", to: "2026-10-31" })).toBe("monthly");
  });
});

describe("buildOverviewCsv", () => {
  it("splits the figures into the card groups, then the chart that was on screen", () => {
    const csv = buildOverviewCsv({
      range: { from: "2026-10-01", to: "2026-10-31" },
      sportsLabel: null,
      metrics,
      chart: { title: "Overall Revenue Trend", kind: "money", points: [{ date: "2026-10-18", value: 500_000 }] },
    }).replace("﻿", "");
    const lines = csv.split("\r\n");
    expect(lines).toContain("Period,2026-10-01 to 2026-10-31");
    expect(lines).toContain("Sports,All sports");
    expect(lines).toContain("Finance");
    expect(lines).toContain("Activity");
    expect(lines).toContain("Total Revenue,Overall revenue,INR,13000.00");
    expect(lines).toContain("Net Revenue,Overall revenue less expenses,INR,6650.00");
    expect(lines).toContain("Total Guest Booking,Overall guest bookings,count,42");
    expect(lines).toContain("Total Students,Overall enrolled students,count,25");
    expect(lines).toContain("Coaching Expenses,Overall coaching expenses,INR,900.00");
    expect(lines).toContain("Overall Revenue Trend");
    expect(lines).toContain("2026-10-18,5000.00");
  });

  it("says Selected and flags the facility-wide figures when sports are chosen", () => {
    const csv = buildOverviewCsv({
      range: { from: "2026-10-01", to: "2026-10-31" },
      sportsLabel: "Badminton",
      metrics,
      chart: { title: "New Memberships Started", kind: "count", points: [{ date: "2026-10-18", value: 3 }] },
    });
    expect(csv).toContain("Sports,Badminton");
    expect(csv).toContain("Total Revenue,Selected revenue,INR,13000.00");
    expect(csv).toContain("Total Expenses,Selected expenses (not split by sport),INR,6350.00");
    expect(csv).toContain("Date,Count");
    expect(csv).toContain("2026-10-18,3");
  });
});
