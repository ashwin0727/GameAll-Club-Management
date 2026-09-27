import { beforeEach, describe, expect, it, vi } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { CoachingOverviewPage } from "@/features/coaching/components/overview-page";
import { renderWithProviders } from "@/test/harness";
import { routerMock, resetRouterMock } from "@/test/router-mock";
import type { CoachingInsights, CoachingOverview } from "@/features/coaching/types";

const getOverview = vi.fn();
const getInsights = vi.fn();
const listCoaches = vi.fn();
const listCoachCandidates = vi.fn();
const listRoles = vi.fn();

vi.mock("@/features/auth/context/permission-provider", () => ({
  usePermissionContext: () => ({
    facilityId: "f1",
    facilityName: "Test Club",
    baseRole: "owner",
    permissions: new Set(["COACHING_MANAGE_COACHES", "COACHING_CREATE_SESSION", "COACHING_MANAGE_PROGRAMS"]),
    can: () => true,
    canAny: () => true,
  }),
}));

vi.mock("@/services/coaching", () => ({
  getCoachingService: () => ({ getOverview, getInsights, listCoaches, listCoachCandidates }),
}));

vi.mock("@/services/staff", () => ({
  getStaffService: () => ({ listRoles }),
}));

vi.mock("@/features/facility/hooks/use-facility-sport-options", () => ({
  useFacilitySportOptions: () => ({ data: [] }),
}));

const OVERVIEW: CoachingOverview = {
  kpis: {
    activeStudents: 12,
    activePrograms: 3,
    activeCoaches: 5,
    coachesOnLeave: 1,
    sessionsThisMonth: 42,
    upcomingSessions: 7,
    revenueThisMonthMinor: 285_00000,
  },
  upcomingSessions: [
    {
      id: "s1",
      startAt: "2026-09-26T00:30:00Z",
      endAt: "2026-09-26T01:30:00Z",
      programName: "Beginner Badminton",
      coachName: "Arjun V",
      courtName: "Court 01",
      enrolled: 5,
      capacity: 8,
      status: "SCHEDULED",
    },
  ],
  activePrograms: [],
  studentsByProgram: [{ programId: "p1", programName: "Beginner Badminton", students: 12 }],
  studentGrowth: [],
  recentEnrollments: [],
};

const INSIGHTS_30: CoachingInsights = {
  windowDays: 30,
  totalStudents: 20,
  sessionAttendancePct: 85,
  coachingRevenueMinor: 28500_00,
  averageRating: 4.8,
};

const INSIGHTS_60: CoachingInsights = {
  windowDays: 60,
  totalStudents: 35,
  sessionAttendancePct: 78.5,
  coachingRevenueMinor: 55000_00,
  averageRating: 4.6,
};

describe("CoachingOverviewPage", () => {
  beforeEach(() => {
    getOverview.mockReset().mockResolvedValue(OVERVIEW);
    getInsights.mockReset().mockImplementation(async (_facilityId: string, days: 30 | 60 | 90) =>
      days === 60 ? INSIGHTS_60 : INSIGHTS_30,
    );
    listCoaches.mockReset().mockResolvedValue({ coaches: [], totalCount: 0 });
    listCoachCandidates.mockReset().mockResolvedValue([]);
    listRoles.mockReset().mockResolvedValue([]);
    resetRouterMock();
  });

  it("shows skeletons before data loads, then the hero, KPI tiles, coach roster and right rail", async () => {
    renderWithProviders(<CoachingOverviewPage />);

    expect(screen.getByText("Coaching")).toBeInTheDocument();
    expect(screen.getByText("Better Coaching. Stronger Players.")).toBeInTheDocument();

    expect(await screen.findByText("5")).toBeInTheDocument(); // Active Coaches
    expect(screen.getByText("Active Coaches")).toBeInTheDocument();
    expect(screen.getAllByText("42").length).toBeGreaterThan(0); // Coaching Sessions this month

    expect(screen.getByText("Beginner Badminton")).toBeInTheDocument();
    expect(screen.getByText(/Arjun V/)).toBeInTheDocument();

    expect(screen.getByText("Coaching Insights")).toBeInTheDocument();
    expect(screen.getByText("Quick Actions")).toBeInTheDocument();
    expect(screen.getAllByText("Add Coach").length).toBeGreaterThan(0); // hero button + quick action tile
    expect(screen.getByText("Schedule Session")).toBeInTheDocument();
  });

  it("loads the Coaching Insights panel for the default 30-day window and shows all four tiles", async () => {
    renderWithProviders(<CoachingOverviewPage />);
    await waitFor(() => expect(getInsights).toHaveBeenCalledWith("f1", 30));

    expect(await screen.findByText("20")).toBeInTheDocument(); // Total Students (windowed)
    expect(screen.getAllByText("Total Students").length).toBeGreaterThan(0); // KPI row tile + insights tile
    expect(screen.getByText("85%")).toBeInTheDocument();
    expect(screen.getByText("Session Attendance")).toBeInTheDocument();
    expect(screen.getByText("4.8")).toBeInTheDocument();
    expect(screen.getByText("Average Rating")).toBeInTheDocument();
  });

  it("re-fetches and re-renders Coaching Insights when the Last N Days dropdown changes", async () => {
    const user = userEvent.setup();
    renderWithProviders(<CoachingOverviewPage />);
    await screen.findByText("20"); // 30-day Total Students rendered first

    await user.click(screen.getByRole("combobox", { name: /coaching insights time window/i }));
    await user.click(await screen.findByText("Last 60 Days"));

    await waitFor(() => expect(getInsights).toHaveBeenCalledWith("f1", 60));
    expect(await screen.findByText("35")).toBeInTheDocument(); // 60-day Total Students
    expect(screen.getByText("4.6")).toBeInTheDocument();
  });

  it("the hero's Add Coach button opens the Add Coach slide-over instead of navigating", async () => {
    const user = userEvent.setup();
    renderWithProviders(<CoachingOverviewPage />);
    await screen.findByText("5"); // wait for the hero/KPIs to render past loading

    const heroButtons = screen.getAllByRole("button", { name: "Add Coach" });
    await user.click(heroButtons[0]!);
    expect(await screen.findByRole("heading", { name: "Add Coach" })).toBeInTheDocument();
    expect(routerMock.push).not.toHaveBeenCalledWith("/coaching/coaches/add");
  });

  it("the Quick Actions Add Coach tile also opens the slide-over", async () => {
    const user = userEvent.setup();
    renderWithProviders(<CoachingOverviewPage />);
    await screen.findByText("5");

    const addCoachButtons = screen.getAllByRole("button", { name: "Add Coach" });
    await user.click(addCoachButtons[addCoachButtons.length - 1]!); // the Quick Actions tile
    expect(await screen.findByRole("heading", { name: "Add Coach" })).toBeInTheDocument();
  });

  it("shows an empty state when there are no upcoming sessions", async () => {
    getOverview.mockResolvedValue({ ...OVERVIEW, upcomingSessions: [] });
    renderWithProviders(<CoachingOverviewPage />);
    expect(await screen.findByText("No coaching sessions scheduled.")).toBeInTheDocument();
  });

  it("shows a retry-able error state when the overview fails to load", async () => {
    getOverview.mockRejectedValue(new Error("network down"));
    renderWithProviders(<CoachingOverviewPage />);
    expect(await screen.findByText(/Unable to load the coaching overview\./)).toBeInTheDocument();
  });

  it("shows an inline error when insights fail to load, without blocking the rest of the page", async () => {
    getInsights.mockRejectedValue(new Error("boom"));
    renderWithProviders(<CoachingOverviewPage />);
    expect(await screen.findByText("Unable to load coaching insights.")).toBeInTheDocument();
    expect(screen.getByText("Coaching")).toBeInTheDocument();
  });

  it("passes the sport/status filters through to listCoaches when the roster panel loads", async () => {
    renderWithProviders(<CoachingOverviewPage />);
    await waitFor(() =>
      expect(listCoaches).toHaveBeenCalledWith(
        expect.objectContaining({ facilityId: "f1", filters: expect.objectContaining({ status: null, sportId: null }) }),
      ),
    );
  });
});
