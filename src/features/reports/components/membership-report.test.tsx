import { describe, expect, it, vi } from "vitest";
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MembershipReport } from "./membership-report";
import { installFakeReportsFilterDeps } from "@/test/fakes/fake-reports-filter-deps";
import { installFakeReportsService } from "@/test/fakes/fake-reports-service";

// The report reads the facility and the top bar's sport selection; these tests have no query client, and All Sports is what
// they mean.
const FACILITY = { id: "fac-1", name: "Champz Turf" };
vi.mock("@/features/facility/hooks/use-facility", () => ({
  useFacility: () => ({ data: FACILITY, isLoading: false }),
}));
vi.mock("@/features/facility/hooks/use-sport-filter", () => ({
  useSportIds: () => ({ sportIds: null, ready: true, key: "all" }),
}));

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

  it("shows only the five cards, the types one by one, and no session panels", async () => {
    const reports = setup();
    reports.membershipMemberCounts = { asOf: "2026-10-21", total: 90, active: 31, inactive: 59 };
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
      { membershipType: "FAMILY", planName: "—", count: 1, revenueMinor: 2_000_000 },
    ];
    reports.guestReleaseAnalytics = { released: 100, booked: 75, remaining: 25, revenueMinor: 3_800_000 };

    render(<MembershipReport />);

    for (const title of ["Total Members", "Active Members", "Inactive Members", "Membership Revenue", "Membership Outstanding"]) {
      expect(await screen.findByText(title, {}, SLOW)).toBeInTheDocument();
    }
    expect(await screen.findByText("90", {}, SLOW)).toBeInTheDocument();
    expect(await screen.findByText("31", {}, SLOW)).toBeInTheDocument();
    expect(await screen.findByText("59", {}, SLOW)).toBeInTheDocument();

    // types are a plain list, one row each — not a Type / Plan / Count / Revenue table
    const list = screen.getByRole("list", { name: /memberships by type/i });
    expect(list.textContent).toContain("Individual · Monthly");
    expect(list.textContent).toContain("Family");
    expect(screen.queryByRole("table", { name: /memberships by type/i })).not.toBeInTheDocument();

    // sessions are gone
    expect(screen.queryByText("Session Utilization")).not.toBeInTheDocument();
    expect(screen.queryByText("Membership Sessions")).not.toBeInTheDocument();
    expect(screen.queryByText("New Memberships")).not.toBeInTheDocument();
    expect(screen.queryByText("Expiring Soon")).not.toBeInTheDocument();

    // From / To dates only
    expect(screen.getByLabelText("From date")).toBeInTheDocument();
    expect(screen.getByLabelText("To date")).toBeInTheDocument();
    expect(screen.queryByText("All Sports")).not.toBeInTheDocument();
    expect(screen.queryByText("This Month")).not.toBeInTheDocument();
  });

  it("splits memberships by sport and by court / turf with their timings", async () => {
    const reports = setup();
    reports.membershipMemberCounts = { asOf: "2026-10-21", total: 5, active: 4, inactive: 1 };
    reports.membershipAnalytics = {
      activeMembers: 4, newMemberships: 5, expiringSoon: 0, membershipRevenueMinor: 1000, paidCount: 5, partiallyPaidCount: 0, pendingCount: 0, outstandingMinor: 0,
    };
    const base = { facilitySportId: "fs-1", sportName: "Badminton", courtId: "c-1", courtName: "Court 1", capacity: 20, courtMembers: 3, sportMembers: 4 };
    reports.membershipBatchBreakdown = [
      { ...base, batchId: "b-1", batchName: "Morning Monthly", daysOfWeek: [1, 2, 3, 4, 5, 6], startTime: "05:00:00", endTime: "06:00:00", members: 3, activeMembers: 2 },
      { ...base, courtId: "c-9", courtName: "Court 9", batchId: "b-9", batchName: "Empty", daysOfWeek: [1], startTime: "06:00:00", endTime: "07:00:00", members: 0, activeMembers: 0, courtMembers: 0 },
      { ...base, courtId: "c-2", courtName: "Court 2", batchId: "b-2", batchName: "Evening", daysOfWeek: [1, 3, 5], startTime: "18:00:00", endTime: "19:00:00", members: 1, activeMembers: 1, courtMembers: 1 },
      { facilitySportId: null, sportName: "Not assigned to a session", courtId: null, courtName: null, batchId: null, batchName: null, daysOfWeek: [], startTime: null, endTime: null, capacity: null, members: 1, activeMembers: 1, courtMembers: 0, sportMembers: 0 },
    ];
    render(<MembershipReport />);

    // left: by sport, right: by court — the same two-panel layout as Guest Bookings
    const bySport = await screen.findByRole("table", { name: /memberships by sport/i }, SLOW);
    expect(bySport.textContent).toContain("Badminton");
    const byCourt = screen.getByRole("table", { name: /memberships by court/i });
    expect(byCourt.textContent).toContain("Court 1");
    expect(byCourt.textContent).toContain("Court 2");

    // a court with a timing but nobody in it is not listed anywhere
    expect(screen.queryByText("Court 9")).not.toBeInTheDocument();

    // below them: every booked timing
    const timings = screen.getByRole("table", { name: /memberships by timing/i });
    expect(timings.textContent).toContain("5:00 AM – 6:00 AM");
    expect(timings.textContent).toContain("Mon–Sat");
    expect(timings.textContent).toContain("6:00 PM – 7:00 PM");
    expect(screen.getByText(/1 member is not assigned to any session timing/i)).toBeInTheDocument();

    // a court filter for the timing table only
    await userEvent.click(screen.getByRole("combobox", { name: /filter timings by court/i }));
    await userEvent.click(await screen.findByRole("option", { name: "Court 2" }));
    const filtered = screen.getByRole("table", { name: /memberships by timing/i });
    expect(filtered.textContent).toContain("6:00 PM – 7:00 PM");
    expect(filtered.textContent).not.toContain("5:00 AM – 6:00 AM");
    // ...and the by-sport / by-court tables are untouched by it
    expect(within(screen.getByRole("table", { name: /memberships by court/i })).getByText("Court 1")).toBeInTheDocument();
  });
});
