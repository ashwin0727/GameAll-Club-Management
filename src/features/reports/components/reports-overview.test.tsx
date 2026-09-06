import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { ReportsOverview } from "./reports-overview";
import { installFakeReportsFilterDeps } from "@/test/fakes/fake-reports-filter-deps";
import { installFakeReportsService } from "@/test/fakes/fake-reports-service";

const SLOW = { timeout: 4000 } as const;

function setup() {
  installFakeReportsFilterDeps();
  return installFakeReportsService();
}

describe("ReportsOverview", () => {
  it("shows the empty state when there is no activity", async () => {
    setup();
    render(<ReportsOverview />);
    expect(await screen.findByText(/no activity for this period/i, {}, SLOW)).toBeInTheDocument();
  });

  it("renders headline KPIs with drill-down links, the trend and top courts", async () => {
    const reports = setup();
    reports.analyticsOverview = {
      grossRevenueMinor: 12_000_000,
      bookingRevenueMinor: 7_000_000,
      membershipRevenueMinor: 5_000_000,
      expensesMinor: 3_500_000,
      netRevenueMinor: 8_500_000,
      outstandingMinor: 1_850_000,
      totalBookings: 205,
      completedBookings: 120,
      cancelledBookings: 20,
      overallUtilizationPct: 68,
    };
    reports.revenueTrend = [{ date: "2026-09-01", grossMinor: 800000, refundMinor: 0, netMinor: 800000 }];
    reports.courtUtilization = [
      {
        courtId: "c1",
        courtName: "Court 1",
        facilitySportId: "fs1",
        sportName: "Badminton",
        openMinutes: 3000,
        bookedMinutes: 2460,
        utilizationPct: 82,
      },
    ];
    reports.peakHours = [{ hour: 18, openMinutes: 300, bookedMinutes: 270, demandPct: 90 }];

    render(<ReportsOverview />);

    expect(await screen.findByText("205", {}, SLOW)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /total revenue/i })).toHaveAttribute(
      "href",
      expect.stringContaining("/reports/revenue"),
    );
    expect(screen.getByRole("link", { name: /outstanding/i })).toHaveAttribute(
      "href",
      "/finance/pending-payments",
    );
    expect(screen.getByRole("table", { name: /top courts/i })).toBeInTheDocument();
  });
});
