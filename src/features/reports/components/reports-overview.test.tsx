import { beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ReportsOverview } from "./reports-overview";
import { installFakeReportsService } from "@/test/fakes/fake-reports-service";

// The page reads the facility and the top bar's sport choice through hooks that need a query client; these tests stand
// those two in, and drive the sport choice through a variable.
const FACILITY = { id: "fac-1", name: "Champz Turf" };
let sportsSelected = false;
// Stable references, like the real hook's memoised ones — a fresh object each render would re-run the page's effects forever.
const ONE_SPORT = new Set(["fs-1"]);
const OPTIONS = [
  { facilitySportId: "fs-1", name: "Badminton" },
  { facilitySportId: "fs-2", name: "Cricket" },
];
const SELECTED_ONE = ["fs-1"];
const SELECTED_ALL = ["fs-1", "fs-2"];
vi.mock("@/features/facility/hooks/use-facility", () => ({
  useFacility: () => ({ data: FACILITY, isLoading: false }),
}));
vi.mock("@/features/facility/hooks/use-sport-filter", () => ({
  useSportFilter: () => ({
    ready: true,
    isAll: !sportsSelected,
    selectedIds: sportsSelected ? SELECTED_ONE : SELECTED_ALL,
    sportSet: sportsSelected ? ONE_SPORT : null,
    options: OPTIONS,
  }),
}));

const SLOW = { timeout: 4000 } as const;

function setup() {
  const reports = installFakeReportsService();
  reports.reportsOverview = {
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
  reports.overviewTrend = [{ date: "2026-10-18", value: 500_000 }];
  return reports;
}

beforeEach(() => {
  sportsSelected = false;
});

describe("ReportsOverview", () => {
  it("shows the twelve cards, worded Overall under All Sports", async () => {
    setup();
    render(<ReportsOverview />);
    for (const title of [
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
    ]) {
      expect(await screen.findByText(title, {}, SLOW)).toBeInTheDocument();
    }
    expect(screen.getByText("Overall revenue")).toBeInTheDocument();
    expect(screen.getByText("Overall active memberships")).toBeInTheDocument();
    expect(screen.queryByText(/selected revenue/i)).not.toBeInTheDocument();
  });

  it("says Selected instead of Overall when particular sports are chosen", async () => {
    sportsSelected = true;
    setup();
    render(<ReportsOverview />);
    expect(await screen.findByText("Selected revenue", {}, SLOW)).toBeInTheDocument();
    expect(screen.queryByText("Overall revenue")).not.toBeInTheDocument();
    // expenses are not split by sport, and the card says so
    expect(screen.getByText(/selected expenses \(not split by sport\)/i)).toBeInTheDocument();
  });

  it("charts Overall Revenue by default, and switches the chart and its heading when another card is tapped", async () => {
    const reports = setup();
    render(<ReportsOverview />);
    expect(await screen.findByRole("heading", { name: "Overall Revenue Trend" }, SLOW)).toBeInTheDocument();
    await waitFor(() => expect(reports.overviewTrendCalls).toContain("REVENUE"));

    await userEvent.click(screen.getByRole("button", { name: /total members/i }));
    expect(await screen.findByRole("heading", { name: "New Memberships Started" }, SLOW)).toBeInTheDocument();
    await waitFor(() => expect(reports.overviewTrendCalls).toContain("MEMBERS"));

    await userEvent.click(screen.getByRole("button", { name: /coaching expenses/i }));
    expect(await screen.findByRole("heading", { name: "Overall Coaching Expenses Trend" }, SLOW)).toBeInTheDocument();
    await waitFor(() => expect(reports.overviewTrendCalls).toContain("COACHING_EXPENSES"));
  });

  it("has From and To dates and an Export button, and no facility or month dropdown", async () => {
    setup();
    render(<ReportsOverview />);
    expect(await screen.findByLabelText("From date", {}, SLOW)).toBeInTheDocument();
    expect(screen.getByLabelText("To date")).toBeInTheDocument();
    expect(await screen.findByRole("button", { name: /export/i }, SLOW)).toBeEnabled();
    expect(screen.queryByRole("combobox")).not.toBeInTheDocument();
  });

  it("shows an error with a retry when the figures cannot load", async () => {
    const reports = setup();
    reports.error = new Error("boom");
    render(<ReportsOverview />);
    expect(await screen.findByText(/unable to load analytics/i, {}, SLOW)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /try again/i })).toBeInTheDocument();
  });
});
