import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { GuestBookingReport } from "./guest-booking-report";
import { installFakeReportsFilterDeps } from "@/test/fakes/fake-reports-filter-deps";
import { installFakeReportsService } from "@/test/fakes/fake-reports-service";

const SLOW = { timeout: 4000 } as const;

function setup() {
  installFakeReportsFilterDeps();
  return installFakeReportsService();
}

describe("GuestBookingReport", () => {
  it("shows the empty state with no guest bookings", async () => {
    setup();
    render(<GuestBookingReport />);
    expect(await screen.findByText(/no guest bookings for this period/i, {}, SLOW)).toBeInTheDocument();
  });

  it("renders KPIs and the by-sport table", async () => {
    const reports = setup();
    reports.guestBookingAnalytics = {
      total: 120,
      completed: 90,
      confirmed: 20,
      pending: 3,
      cancelled: 7,
      revenueMinor: 4_500_000,
      avgBookingValueMinor: 50_000,
      collectedMinor: 4_500_000,
      outstandingMinor: 500_000,
      collectionRatePct: 90,
    };
    reports.guestBookingsBySport = [
      { facilitySportId: "fs1", sportName: "Badminton", bookingCount: 80, revenueMinor: 3_000_000 },
    ];
    reports.guestBookingsByCourt = [
      { courtId: "c1", courtName: "Court 1", sportName: "Badminton", bookingCount: 50, revenueMinor: 2_000_000 },
    ];
    reports.guestPeakHours = [{ hour: 18, bookingCount: 30 }];

    render(<GuestBookingReport />);

    expect(await screen.findByText("120", {}, SLOW)).toBeInTheDocument();
    expect(screen.getByRole("table", { name: /guest bookings by sport/i })).toBeInTheDocument();
    expect(screen.getByText("Collection Rate")).toBeInTheDocument();
    expect(screen.getAllByText("90%").length).toBeGreaterThan(0);
  });
});
