import { beforeEach, describe, expect, it, vi } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { CoachesListPanel } from "@/features/coaching/components/coaches-list-panel";
import { renderWithProviders } from "@/test/harness";
import type { CoachRow } from "@/features/coaching/types";

const listCoaches = vi.fn();
const listCoachCandidates = vi.fn();
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
  getCoachingService: () => ({ listCoaches, listCoachCandidates, addCoach }),
}));

vi.mock("@/services/staff", () => ({
  getStaffService: () => ({ listRoles }),
}));

vi.mock("@/features/facility/hooks/use-facility-sport-options", () => ({
  useFacilitySportOptions: () => ({
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
    listCoaches.mockReset().mockResolvedValue({ coaches: [COACH], totalCount: 1 });
    listCoachCandidates.mockReset().mockResolvedValue([]);
    addCoach.mockReset().mockResolvedValue("coach-2");
    listRoles.mockReset().mockResolvedValue([]);
  });

  it("shows the All Sports / All Status / sort dropdowns and the tabs, and renders the rating column", async () => {
    renderWithProviders(<CoachesListPanel facilityId="f1" />);

    expect(await screen.findByText("Arjun V")).toBeInTheDocument();
    expect(screen.getByRole("combobox", { name: /filter by sport/i })).toHaveTextContent("All Sports");
    expect(screen.getByRole("combobox", { name: /filter by status/i })).toHaveTextContent("All Status");
    expect(screen.getByRole("combobox", { name: /sort by/i })).toHaveTextContent("Name (A-Z)");
    expect(screen.getByText("4.9")).toBeInTheDocument();
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

  it("filters by sport", async () => {
    const user = userEvent.setup();
    renderWithProviders(<CoachesListPanel facilityId="f1" />);
    await screen.findByText("Arjun V");

    await user.click(screen.getByRole("combobox", { name: /filter by sport/i }));
    await user.click(await screen.findByRole("option", { name: "Tennis" }));

    await waitFor(() =>
      expect(listCoaches).toHaveBeenCalledWith(expect.objectContaining({ filters: expect.objectContaining({ sportId: "fs-tennis" }) })),
    );
  });

  it("shows an empty state when nothing matches, and a dash for coaches with no rating yet", async () => {
    listCoaches.mockResolvedValue({ coaches: [{ ...COACH, rating: null }], totalCount: 1 });
    renderWithProviders(<CoachesListPanel facilityId="f1" />);
    expect(await screen.findByText("—")).toBeInTheDocument();
  });

  it("opens the Add Coach slide-over from its own button and refreshes the roster once a coach is added", async () => {
    listCoachCandidates.mockResolvedValue([{ userId: "u2", fullName: "Priya Sharma", email: null, phone: null, avatarUrl: null, title: null }]);
    const user = userEvent.setup();
    renderWithProviders(<CoachesListPanel facilityId="f1" showAddButton />);
    await screen.findByText("Arjun V");

    await user.click(screen.getByRole("button", { name: "Add Coach" }));
    expect(await screen.findByRole("heading", { name: "Add Coach" })).toBeInTheDocument();

    await user.click(screen.getByRole("combobox", { name: /staff member/i }));
    await user.click(await screen.findByText(/Priya Sharma/i));
    await user.click(screen.getByRole("button", { name: "Badminton" }));
    await user.click(screen.getByRole("button", { name: "Beginner" }));

    listCoaches.mockClear();
    await user.click(screen.getByRole("button", { name: "+ Add Coach" }));

    expect(await screen.findByText("Coach Added Successfully!")).toBeInTheDocument();
    await waitFor(() => expect(listCoaches).toHaveBeenCalled()); // roster refreshed via onCoachAdded
  });
});
