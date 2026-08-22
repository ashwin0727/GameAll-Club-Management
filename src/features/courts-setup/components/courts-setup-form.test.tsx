import { beforeEach, describe, expect, it, vi } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { CourtsSetupForm } from "@/features/courts-setup/components/courts-setup-form";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import {
  installFakeAuthService,
  installFakeFacilityService,
  installFakePlayingAreasService,
  installFakeSportsService,
  renderWithProviders,
} from "@/test/harness";
import { routerMock } from "@/test/router-mock";

const FAKE_USER = {
  id: "owner-1",
  name: "Uma Shankar",
  email: "owner@yourturf.com",
  emailVerified: true,
  onboardingCompleted: false,
};

function installAuth() {
  installFakeAuthService({ getCurrentUser: vi.fn(async () => FAKE_USER) });
  const facilityService = installFakeFacilityService();
  facilityService.setCurrentUserId(FAKE_USER.id);
  const sportsService = installFakeSportsService();
  const playingAreasService = installFakePlayingAreasService();
  return { facilityService, sportsService, playingAreasService };
}

async function seedFacility(facilityService: ReturnType<typeof installFakeFacilityService>) {
  return facilityService.createFacility({
    ownerId: FAKE_USER.id,
    name: "GameAll Sports Arena",
    type: "MULTI_SPORT",
    businessEmail: FAKE_USER.email,
    businessPhone: "9876543210",
    address: {
      line1: "123 Anna Salai",
      area: "Ambattur",
      city: "Chennai",
      state: "Tamil Nadu",
      country: "India",
      pinCode: "600053",
    },
  });
}

async function seedSports(
  sportsService: ReturnType<typeof installFakeSportsService>,
  facilityId: string,
  sportIds: string[],
) {
  return sportsService.saveFacilitySports(
    facilityId,
    sportIds.map((sportId) => ({ facilityId, sportId, enabled: true })),
  );
}

describe("CourtsSetupForm", () => {
  beforeEach(() => {
    useOnboardingStore.getState().reset();
  });

  it("redirects to /login when there is no signed-in user", async () => {
    installFakeAuthService({ getCurrentUser: vi.fn(async () => null) });
    installFakeFacilityService();
    installFakeSportsService();
    installFakePlayingAreasService();
    renderWithProviders(<CourtsSetupForm />);

    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/login"));
  });

  it("redirects to /onboarding/facility when the user has no facility", async () => {
    installAuth();
    renderWithProviders(<CourtsSetupForm />);

    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/onboarding/facility"));
  });

  it("redirects to /onboarding/sports when the facility has no selected sports", async () => {
    const { facilityService } = installAuth();
    await seedFacility(facilityService);
    renderWithProviders(<CourtsSetupForm />);

    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/onboarding/sports"));
  });

  it("shows only the sections for sports actually selected", async () => {
    const { facilityService, sportsService } = installAuth();
    const facility = await seedFacility(facilityService);
    await seedSports(sportsService, facility.id, ["sport-badminton", "sport-cricket"]);
    renderWithProviders(<CourtsSetupForm />);

    expect(await screen.findByText("Badminton")).toBeInTheDocument();
    expect(screen.getByText("Cricket")).toBeInTheDocument();
    expect(screen.queryByText("Football")).not.toBeInTheDocument();
    expect(screen.queryByText("Tennis")).not.toBeInTheDocument();
  });

  it("uses Turf terminology for Cricket and Court terminology for Badminton", async () => {
    const { facilityService, sportsService } = installAuth();
    const facility = await seedFacility(facilityService);
    await seedSports(sportsService, facility.id, ["sport-badminton", "sport-cricket"]);
    renderWithProviders(<CourtsSetupForm />);

    await screen.findByText("Badminton");
    expect(screen.getByRole("button", { name: "+ Add Court" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "+ Add Turf" })).toBeInTheDocument();
  });

  it("adding a court auto-generates a sequential name and increments the count", async () => {
    const user = userEvent.setup();
    const { facilityService, sportsService } = installAuth();
    const facility = await seedFacility(facilityService);
    await seedSports(sportsService, facility.id, ["sport-badminton"]);
    renderWithProviders(<CourtsSetupForm />);

    await user.click(await screen.findByRole("button", { name: "+ Add Court" }));
    expect(await screen.findByDisplayValue("Court 1")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "+ Add Court" }));
    expect(await screen.findByDisplayValue("Court 2")).toBeInTheDocument();
  });

  it("auto-saves a new court via the debounce timer alone, without clicking Continue", async () => {
    const user = userEvent.setup();
    const { facilityService, sportsService, playingAreasService } = installAuth();
    const facility = await seedFacility(facilityService);
    await seedSports(sportsService, facility.id, ["sport-badminton"]);
    renderWithProviders(<CourtsSetupForm />);

    await user.click(await screen.findByRole("button", { name: "+ Add Court" }));
    await screen.findByDisplayValue("Court 1");

    expect(await playingAreasService.getPlayingAreas(facility.id)).toHaveLength(0);

    await waitFor(
      async () => {
        const saved = await playingAreasService.getPlayingAreas(facility.id);
        expect(saved.map((a) => a.name)).toEqual(["Court 1"]);
      },
      { timeout: 2000 },
    );
    expect(routerMock.push).not.toHaveBeenCalled();
  });

  it("auto-saves an edit to an already-saved court via the debounce timer alone", async () => {
    const user = userEvent.setup();
    const { facilityService, sportsService, playingAreasService } = installAuth();
    const facility = await seedFacility(facilityService);
    const [facilitySport] = await seedSports(sportsService, facility.id, ["sport-badminton"]);
    if (!facilitySport) throw new Error("facilitySport not seeded");
    const saved = await playingAreasService.createPlayingArea({
      id: crypto.randomUUID(),
      facilityId: facility.id,
      facilitySportId: facilitySport.id,
      sportId: "sport-badminton",
      name: "Court 1",
      type: "INDOOR",
      status: "ACTIVE",
      bookingEnabled: true,
      archived: false,
      displayOrder: 0,
    });

    renderWithProviders(<CourtsSetupForm />);
    const nameField = await screen.findByDisplayValue("Court 1");
    await user.clear(nameField);
    await user.type(nameField, "Center Court");

    await waitFor(
      async () => {
        const [area] = await playingAreasService.getPlayingAreas(facility.id);
        expect(area?.name).toBe("Center Court");
      },
      { timeout: 2000 },
    );
    const [persisted] = await playingAreasService.getPlayingAreas(facility.id);
    expect(persisted?.id).toBe(saved.id);
    expect(routerMock.push).not.toHaveBeenCalled();
  });

  it("does not reuse a name still in use after removing an earlier court", async () => {
    const user = userEvent.setup();
    const { facilityService, sportsService } = installAuth();
    const facility = await seedFacility(facilityService);
    await seedSports(sportsService, facility.id, ["sport-badminton"]);
    renderWithProviders(<CourtsSetupForm />);

    await user.click(await screen.findByRole("button", { name: "+ Add Court" }));
    await screen.findByDisplayValue("Court 1");
    await user.click(screen.getByRole("button", { name: "+ Add Court" }));
    await screen.findByDisplayValue("Court 2");

    // Remove "Court 1" (a never-saved draft — removed immediately, no dialog).
    const removeButtons = screen.getAllByRole("button", { name: "Remove" });
    const firstRemove = removeButtons[0];
    if (!firstRemove) throw new Error("expected a Remove button");
    await user.click(firstRemove);
    expect(screen.queryByDisplayValue("Court 1")).not.toBeInTheDocument();
    expect(screen.getByDisplayValue("Court 2")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "+ Add Court" }));

    // A count-based scheme would re-mint "Court 2" (1 remaining + 1), colliding
    // with the surviving court — it must skip ahead to "Court 3" instead.
    expect(await screen.findByDisplayValue("Court 3")).toBeInTheDocument();
  });

  it("removing a never-saved draft removes it immediately with no confirmation dialog", async () => {
    const user = userEvent.setup();
    const { facilityService, sportsService } = installAuth();
    const facility = await seedFacility(facilityService);
    await seedSports(sportsService, facility.id, ["sport-badminton"]);
    renderWithProviders(<CourtsSetupForm />);

    await user.click(await screen.findByRole("button", { name: "+ Add Court" }));
    await screen.findByDisplayValue("Court 1");

    await user.click(screen.getByRole("button", { name: "Remove" }));

    expect(screen.queryByText(/Remove this court\?/)).not.toBeInTheDocument();
    expect(screen.queryByDisplayValue("Court 1")).not.toBeInTheDocument();
  });

  it("removing an already-saved court shows a confirm dialog, and Remove soft-deletes it", async () => {
    const user = userEvent.setup();
    const { facilityService, sportsService, playingAreasService } = installAuth();
    const facility = await seedFacility(facilityService);
    const [facilitySport] = await seedSports(sportsService, facility.id, ["sport-badminton"]);
    if (!facilitySport) throw new Error("facilitySport not seeded");
    const saved = await playingAreasService.createPlayingArea({
      id: crypto.randomUUID(),
      facilityId: facility.id,
      facilitySportId: facilitySport.id,
      sportId: "sport-badminton",
      name: "Court 1",
      type: "INDOOR",
      status: "ACTIVE",
      bookingEnabled: true,
      archived: false,
      displayOrder: 0,
    });

    renderWithProviders(<CourtsSetupForm />);
    await screen.findByDisplayValue("Court 1");

    await user.click(screen.getByRole("button", { name: "Remove" }));
    expect(await screen.findByText(/Remove this court\?/)).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Remove" }));

    await waitFor(async () => {
      const remaining = await playingAreasService.getPlayingAreas(facility.id);
      expect(remaining).toHaveLength(0);
    });
    // Soft delete: the row survives (archived), it's just excluded from reads.
    const archivedRow = playingAreasService.rows.find((row) => row.id === saved.id);
    expect(archivedRow?.archived).toBe(true);
  });

  it("blocks Continue and shows an error when a selected sport has zero playing areas", async () => {
    const user = userEvent.setup();
    const { facilityService, sportsService } = installAuth();
    const facility = await seedFacility(facilityService);
    await seedSports(sportsService, facility.id, ["sport-badminton"]);
    renderWithProviders(<CourtsSetupForm />);

    await screen.findByText("Badminton");
    await user.click(screen.getByRole("button", { name: /Continue/ }));

    expect(await screen.findByText(/Add at least one court for Badminton/)).toBeInTheDocument();
    expect(routerMock.push).not.toHaveBeenCalled();
  });

  it("blocks Continue on duplicate names within the same sport", async () => {
    const user = userEvent.setup();
    const { facilityService, sportsService } = installAuth();
    const facility = await seedFacility(facilityService);
    await seedSports(sportsService, facility.id, ["sport-badminton"]);
    renderWithProviders(<CourtsSetupForm />);

    await user.click(await screen.findByRole("button", { name: "+ Add Court" }));
    await screen.findByDisplayValue("Court 1");
    await user.click(screen.getByRole("button", { name: "+ Add Court" }));
    await screen.findByDisplayValue("Court 2");

    const secondNameField = screen.getByDisplayValue("Court 2");
    await user.clear(secondNameField);
    await user.type(secondNameField, "Court 1");

    await user.click(screen.getByRole("button", { name: /Continue/ }));

    expect(await screen.findByText(/already used for this sport/)).toBeInTheDocument();
    expect(routerMock.push).not.toHaveBeenCalled();
  });

  it("blocks Continue when a court's name is too short", async () => {
    const user = userEvent.setup();
    const { facilityService, sportsService } = installAuth();
    const facility = await seedFacility(facilityService);
    await seedSports(sportsService, facility.id, ["sport-badminton"]);
    renderWithProviders(<CourtsSetupForm />);

    await user.click(await screen.findByRole("button", { name: "+ Add Court" }));
    const nameField = await screen.findByDisplayValue("Court 1");
    await user.clear(nameField);
    await user.type(nameField, "A");

    await user.click(screen.getByRole("button", { name: /Continue/ }));

    expect(await screen.findByText(/between 2 and 50 characters/)).toBeInTheDocument();
    expect(routerMock.push).not.toHaveBeenCalled();
  });

  it("saves playing areas and navigates to the operating-hours placeholder on Continue", async () => {
    const user = userEvent.setup();
    const { facilityService, sportsService, playingAreasService } = installAuth();
    const facility = await seedFacility(facilityService);
    await seedSports(sportsService, facility.id, ["sport-badminton"]);
    renderWithProviders(<CourtsSetupForm />);

    await user.click(await screen.findByRole("button", { name: "+ Add Court" }));
    await screen.findByDisplayValue("Court 1");

    await user.click(screen.getByRole("button", { name: /Continue/ }));

    await waitFor(() => expect(routerMock.push).toHaveBeenCalledWith("/onboarding/operating-hours"));
    expect(useOnboardingStore.getState().courtsCompleted).toBe(true);

    const saved = await playingAreasService.getPlayingAreas(facility.id);
    expect(saved.map((a) => a.name)).toEqual(["Court 1"]);
  });

  it("restores previously saved playing areas after remounting", async () => {
    const { facilityService, sportsService, playingAreasService } = installAuth();
    const facility = await seedFacility(facilityService);
    const [facilitySport] = await seedSports(sportsService, facility.id, ["sport-badminton"]);
    if (!facilitySport) throw new Error("facilitySport not seeded");
    await playingAreasService.createPlayingArea({
      id: crypto.randomUUID(),
      facilityId: facility.id,
      facilitySportId: facilitySport.id,
      sportId: "sport-badminton",
      name: "Court 1",
      type: "INDOOR",
      status: "ACTIVE",
      bookingEnabled: true,
      archived: false,
      displayOrder: 0,
    });

    renderWithProviders(<CourtsSetupForm />);
    expect(await screen.findByDisplayValue("Court 1")).toBeInTheDocument();
  });
});