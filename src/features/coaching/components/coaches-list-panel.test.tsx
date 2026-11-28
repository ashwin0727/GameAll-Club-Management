import { beforeEach, describe, expect, it, vi } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { CoachesListPanel } from "@/features/coaching/components/coaches-list-panel";
import { renderWithProviders } from "@/test/harness";
import { useUiStore } from "@/stores/ui-store";
import { routerMock, resetRouterMock } from "@/test/router-mock";
import type { CoachRow } from "@/features/coaching/types";

const listCoaches = vi.fn();
const listCoachCandidates = vi.fn();
const listCoachOnboardingDrafts = vi.fn();
const addCoach = vi.fn();
const listRoles = vi.fn();

vi.mock("@/features/auth/context/permission-provider", () => ({
  usePermissionContext: () => ({
    facilityId: "f1",
    facilityName: "Test Club",
    baseRole: "owner",
    permissions: new Set(["COACHING_MANAGE_COACHES"]),
    can: () => true,
    canAny: () => true,
  }),
}));

vi.mock("@/services/coaching", () => ({
  getCoachingService: () => ({ listCoaches, listCoachCandidates, addCoach, listCoachOnboardingDrafts }),
}));

vi.mock("@/services/staff", () => ({
  getStaffService: () => ({ listRoles }),
}));

vi.mock("@/features/facility/hooks/use-facility-sport-options", () => ({
  useFacilitySportOptions: () => ({
    isSuccess: true,
    isError: false,
    data: [
      { facilitySportId: "fs-badminton", name: "Badminton", icon: "🏸" },
      { facilitySportId: "fs-tennis", name: "Tennis", icon: "🎾" },
    ],
  }),
}));

const COACH: CoachRow = {
  id: "c1",
  userId: "u1",
  fullName: "Arjun V",
  email: "arjun@x.com",
  phone: "9876543210",
  avatarUrl: null,
  specialization: null,
  experienceYears: 5,
  status: "ACTIVE",
  expertiseLevels: ["Beginner", "Intermediate"],
  rating: 4.9,
  sports: [{ id: "fs-badminton", name: "Badminton" }],
  programCount: 2,
  sessionCount: 68,
  studentCount: 12,
};

describe("CoachesListPanel", () => {
  beforeEach(() => {
    useUiStore.setState({ selectedSportIds: null });
    resetRouterMock();
    listCoaches.mockReset().mockResolvedValue({ coaches: [COACH], totalCount: 1 });
    listCoachCandidates.mockReset().mockResolvedValue([]);
    listCoachOnboardingDrafts.mockReset().mockResolvedValue([]);
    addCoach.mockReset().mockResolvedValue("coach-2");
    listRoles.mockReset().mockResolvedValue([]);
  });

  it("shows the All Status / sort dropdowns and the tabs, and no rating column", async () => {
    renderWithProviders(<CoachesListPanel facilityId="f1" />);

    expect(await screen.findByText("Arjun V")).toBeInTheDocument();
    expect(screen.getByRole("combobox", { name: /filter by status/i })).toHaveTextContent("All Status");
    expect(screen.getByRole("combobox", { name: /sort by/i })).toHaveTextContent("Name (A-Z)");
    expect(screen.queryByText("4.9")).not.toBeInTheDocument();
    expect(screen.queryByText("Rating")).not.toBeInTheDocument();
    expect(screen.getByText("All Coaches")).toBeInTheDocument();
    expect(screen.getAllByText("Active").length).toBeGreaterThan(0); // tab + status badge
  });

  it("keeps the Active tab and the All Status dropdown in sync", async () => {
    const user = userEvent.setup();
    renderWithProviders(<CoachesListPanel facilityId="f1" />);
    await screen.findByText("Arjun V");

    await user.click(screen.getByRole("button", { name: "Active" }));
    await waitFor(() =>
      expect(listCoaches).toHaveBeenCalledWith(expect.objectContaining({ filters: expect.objectContaining({ status: "ACTIVE" }) })),
    );
    expect(screen.getByRole("combobox", { name: /filter by status/i })).toHaveTextContent("Active");

    await user.click(screen.getByRole("combobox", { name: /filter by status/i }));
    await user.click(await screen.findByRole("option", { name: "Inactive" }));
    await waitFor(() =>
      expect(listCoaches).toHaveBeenCalledWith(expect.objectContaining({ filters: expect.objectContaining({ status: "INACTIVE" }) })),
    );
    expect(screen.getByRole("button", { name: "Inactive" }).className).toContain("border-primary");
  });

  it("sends the selected sort option to listCoaches", async () => {
    const user = userEvent.setup();
    renderWithProviders(<CoachesListPanel facilityId="f1" />);
    await screen.findByText("Arjun V");

    await user.click(screen.getByRole("combobox", { name: /sort by/i }));
    await user.click(await screen.findByRole("option", { name: "Most Sessions" }));

    await waitFor(() => expect(listCoaches).toHaveBeenCalledWith(expect.objectContaining({ sort: "sessions_desc" })));
  });

  it("follows the sports ticked in the top bar: All Sports sends none, a subset sends just those", async () => {
    renderWithProviders(<CoachesListPanel facilityId="f1" />);
    await screen.findByText("Arjun V");
    expect(listCoaches).toHaveBeenLastCalledWith(expect.objectContaining({ filters: expect.objectContaining({ sportIds: null }) }));
    // There is no separate Sport filter on this page any more.
    expect(screen.queryByRole("combobox", { name: /filter by sport/i })).not.toBeInTheDocument();

    useUiStore.setState({ selectedSportIds: ["fs-tennis"] });
    await waitFor(() =>
      expect(listCoaches).toHaveBeenLastCalledWith(expect.objectContaining({ filters: expect.objectContaining({ sportIds: ["fs-tennis"] }) })),
    );
  });

  it("shows an empty state when nothing matches", async () => {
    listCoaches.mockResolvedValue({ coaches: [], totalCount: 0 });
    renderWithProviders(<CoachesListPanel facilityId="f1" />);
    expect(await screen.findByText(/no coaches/i)).toBeInTheDocument();
  });

  it("goes to the full Add Coach page from its own button (no slide-over)", async () => {
    const user = userEvent.setup();
    renderWithProviders(<CoachesListPanel facilityId="f1" showAddButton />);
    await screen.findByText("Arjun V");

    await user.click(screen.getByRole("button", { name: "Add Coach" }));
    expect(routerMock.push).toHaveBeenCalledWith("/coaching/coaches/add");
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });

  it("lists onboarding drafts with their step and a Resume link", async () => {
    listCoachOnboardingDrafts.mockResolvedValue([{ coachId: "c9", fullName: "Ravi Kumar", currentStep: 3 }]);
    renderWithProviders(<CoachesListPanel facilityId="f1" showAddButton />);
    expect(await screen.findByText("Draft – step 3 of 5")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Resume" })).toHaveAttribute("href", "/coaching/coaches/add?coach=c9");
  });
});
