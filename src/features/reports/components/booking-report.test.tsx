import { describe, expect, it } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { BookingReport } from "./booking-report";
import { installFakeReportsFilterDeps } from "@/test/fakes/fake-reports-filter-deps";
import { installFakeReportsService } from "@/test/fakes/fake-reports-service";

// The report has two sequential async boundaries (facility load, then the
// four RPC calls); under full-suite CPU contention that outruns the 1s
// default. Give the findBy queries room.
const SLOW = { timeout: 4000 } as const;

function setup() {
  installFakeReportsFilterDeps();
  return installFakeReportsService();
}

describe("BookingReport", () => {
  it("shows the empty state when there are no bookings", async () => {
    setup();
    render(<BookingReport />);
    expect(await screen.findByText("No booking data for this period.", {}, SLOW)).toBeInTheDocument();
  });

  it("renders KPIs, the trend table and the by-sport table when there is data", async () => {
    const reports = setup();
    reports.bookingAnalytics = {
      total: 205,
      completed: 120,
      confirmed: 60,
      pending: 5,
      cancelled: 20,
      guestCount: 130,
      memberCount: 75,
      avgGuestBookingValueMinor: 55000,
    };
    reports.bookingTrend = [{ date: "2026-09-01", total: 8, completed: 5, cancelled: 1 }];
    reports.bookingsBySport = [
      { facilitySportId: "fs-1", sportName: "Badminton", bookingCount: 120 },
      { facilitySportId: "fs-2", sportName: "Football", bookingCount: 85 },
    ];
    reports.bookingSourceSplit = [
      { source: "GUEST", bookingCount: 130 },
      { source: "MEMBER", bookingCount: 75 },
    ];

    render(<BookingReport />);

    expect(await screen.findByText("205", {}, SLOW)).toBeInTheDocument();
    expect(screen.getByRole("table", { name: /bookings by sport/i })).toBeInTheDocument();
    expect(screen.getByRole("table", { name: /bookings over time/i })).toBeInTheDocument();
    expect(screen.getByText("₹550")).toBeInTheDocument();
  });

  it("shows an error state with a retry that re-fetches", async () => {
    const reports = setup();
    reports.error = new Error("boom");
    render(<BookingReport />);
    expect(await screen.findByText(/unable to load/i, {}, SLOW)).toBeInTheDocument();

    reports.error = null;
    reports.bookingAnalytics = { ...reports.bookingAnalytics, total: 3 };
    await userEvent.click(screen.getByRole("button", { name: /try again/i }));
    await waitFor(() => expect(screen.queryByText(/unable to load/i)).not.toBeInTheDocument(), SLOW);
  });

  it("offers a CSV download once data is loaded", async () => {
    const reports = setup();
    reports.bookingAnalytics = { ...reports.bookingAnalytics, total: 10 };
    render(<BookingReport />);
    expect(await screen.findByRole("button", { name: /download csv/i }, SLOW)).toBeInTheDocument();
  });
});
