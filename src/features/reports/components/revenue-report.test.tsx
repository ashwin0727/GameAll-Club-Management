import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { RevenueReport } from "./revenue-report";
import { installFakeReportsFilterDeps } from "@/test/fakes/fake-reports-filter-deps";
import { installFakeReportsService } from "@/test/fakes/fake-reports-service";

const SLOW = { timeout: 4000 } as const;

function setup() {
  installFakeReportsFilterDeps();
  return installFakeReportsService();
}

describe("RevenueReport", () => {
  it("shows the empty state when there is no revenue", async () => {
    setup();
    render(<RevenueReport />);
    expect(await screen.findByText("No revenue data for this period.", {}, SLOW)).toBeInTheDocument();
  });

  it("renders totals, the trend table and the by-sport / by-court tables (unscoped)", async () => {
    const reports = setup();
    reports.revenueSummary = {
      grossMinor: 11_000_000,
      refundsMinor: 0,
      expensesMinor: 3_500_000,
      netMinor: 7_500_000,
      outstandingMinor: 0,
    };
    reports.revenueTrend = [{ date: "2026-09-01", grossMinor: 800000, refundMinor: 0, netMinor: 800000 }];
    reports.revenueBreakdown = {
      membershipMinor: 6_000_000,
      memberBookingMinor: 500_000,
      guestBookingMinor: 4_500_000,
      refundsMinor: 0,
      netMinor: 11_000_000,
    };
    reports.paymentMethods = [{ method: "UPI", amountMinor: 5_000_000, count: 20 }];
    reports.revenueBySport = [{ facilitySportId: "fs1", sportName: "Badminton", revenueMinor: 4_500_000 }];
    reports.revenueByCourt = [
      { courtId: "c1", courtName: "Court 1", facilitySportId: "fs1", sportName: "Badminton", revenueMinor: 3_000_000 },
    ];

    render(<RevenueReport />);

    expect(await screen.findByText("Total Revenue", {}, SLOW)).toBeInTheDocument();
    expect(screen.getByRole("table", { name: /revenue over time/i })).toBeInTheDocument();
    expect(screen.getByRole("table", { name: /revenue by sport/i })).toBeInTheDocument();
    expect(screen.getByRole("table", { name: /revenue by court/i })).toBeInTheDocument();
  });
});
