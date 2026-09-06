import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { MembershipReport } from "./membership-report";
import { installFakeReportsFilterDeps } from "@/test/fakes/fake-reports-filter-deps";
import { installFakeReportsService } from "@/test/fakes/fake-reports-service";

const SLOW = { timeout: 4000 } as const;

function setup() {
  installFakeReportsFilterDeps();
  return installFakeReportsService();
}

describe("MembershipReport", () => {
  it("shows the empty state with no membership activity", async () => {
    setup();
    render(<MembershipReport />);
    expect(await screen.findByText(/no membership activity/i, {}, SLOW)).toBeInTheDocument();
  });

  it("renders KPIs, the by-type table and the session panel", async () => {
    const reports = setup();
    reports.membershipAnalytics = {
      activeMembers: 84,
      newMemberships: 12,
      expiringSoon: 5,
      membershipRevenueMinor: 6_000_000,
      paidCount: 9,
      partiallyPaidCount: 2,
      pendingCount: 1,
      outstandingMinor: 1_000_000,
    };
    reports.membershipsByType = [
      { membershipType: "INDIVIDUAL", planName: "Monthly", count: 8, revenueMinor: 4_000_000 },
      { membershipType: "FAMILY", planName: "—", count: 4, revenueMinor: 2_000_000 },
    ];
    reports.membershipSessionAnalytics = {
      sessionCount: 40,
      totalCapacity: 500,
      memberAllocations: 360,
      guestReleased: 100,
      guestBooked: 75,
      remainingReleased: 25,
      unusedCapacity: 65,
    };
    reports.guestReleaseAnalytics = { released: 100, booked: 75, remaining: 25, revenueMinor: 3_800_000 };

    render(<MembershipReport />);

    expect(await screen.findByText("84", {}, SLOW)).toBeInTheDocument();
    expect(screen.getByRole("table", { name: /memberships by type/i })).toBeInTheDocument();
    expect(screen.getByRole("table", { name: /membership session capacity/i })).toBeInTheDocument();
    expect(screen.getByText("65")).toBeInTheDocument();
  });
});
