import { beforeEach, describe, expect, it, vi } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { CourtsSetupForm } from "@/features/courts-setup/components/courts-setup-form";
import { MockPlayingAreaService } from "@/features/courts-setup/services/mock-playing-area-service";
import { MockFacilityService } from "@/features/onboarding/services/mock-facility-service";
import { MockSportService } from "@/features/sports-setup/services/mock-sport-service";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import { installFakeAuthService, renderWithProviders } from "@/test/harness";
import { routerMock } from "@/test/router-mock";

const FAKE_USER = {
  id: "owner-1",
  name: "Uma Shankar",
  email: "owner@yourturf.com",
  emailVerified: true,
  onboardingCompleted: false,
};

function installAuth() {
  return installFakeAuthService({ getCurrentUser: vi.fn(async () => FAKE_USER) });
}

async function seedFacility() {
  return MockFacilityService.saveFacility({
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

async function seedSports(facilityId: string, sportIds: string[]) {
  return MockSportService.saveFacilitySports(
    facilityId,
    sportIds.map((sportId) => ({ facilityId, sportId, enabled: true })),
  );
}

describe("CourtsSetupForm", () => {
  beforeEach(() => {
    window.localStorage.clear();
    useOnboardingStore.getState().reset();
  });

  it("redirects to /login when there is no signed-in user", async () => {
    installFakeAuthService({ getCurrentUser: vi.fn(async () => null) });
    renderWithProviders(<CourtsSetupForm />);

    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/login"));
  });

  it("redirects to /onboarding/facility when the user has no facility", async () => {
    installAuth();
    renderWithProviders(<CourtsSetupForm />);

    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/onboarding/facility"));
  });

  it("redirects to /onboarding/sports when the facility has no selected sports", async () => {
    installAuth();
    await seedFacility();
    renderWithProviders(<CourtsSetupForm />);

    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/onboarding/sports"));
  });

  it("shows only the sections for sports actually selected", async () => {
    installAuth();
    const facility = await seedFacility();
    await seedSports(facility.id, ["sport_badminton", "sport_cricket"]);
    renderWithProviders(<CourtsSetupForm />);

    expect(await screen.findByText("Badminton")).toBeInTheDocument();
    expect(screen.getByText("Cricket")).toBeInTheDocument();
    expect(screen.queryByText("Football")).not.toBeInTheDocument();
    expect(screen.queryByText("Tennis")).not.toBeInTheDocument();
  });

  it("uses Turf terminology for Cricket and Court terminology for Badminton", async () => {
    installAuth();
    const facility = await seedFacility();
    await seedSports(facility.id, ["sport_badminton", "sport_cricket"]);
    renderWithProviders(<CourtsSetupForm />);

    await screen.findByText("Badminton");
    expect(screen.getByRole("button", { name: "+ Add Court" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "+ Add Turf" })).toBeInTheDocument();
  });

  it("adding a court auto-generates a sequential name and increments the count", async () => {
    const user = userEvent.setup();
    installAuth();
    const facility = await seedFacility();
    await seedSports(facility.id, ["sport_badminton"]);
    renderWithProviders(<CourtsSetupForm />);

    await user.click(await screen.findByRole("button", { name: "+ Add Court" }));
    expect(await screen.findByDisplayValue("Court 1")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "+ Add Court" }));
    expect(await screen.findByDisplayValue("Court 2")).toBeInTheDocument();
  });

  it("removing a never-saved draft removes it immediately with no confirmation dialog", async () => {
    const user = userEvent.setup();
    installAuth();
    const facility = await seedFacility();
    await seedSports(facility.id, ["sport_badminton"]);
    renderWithProviders(<CourtsSetupForm />);

    await user.click(await screen.findByRole("button", { name: "+ Add Court" }));
    await screen.findByDisplayValue("Court 1");

    await user.click(screen.getByRole("button", { name: "Remove" }));

    expect(screen.queryByText(/Remove this court\?/)).not.toBeInTheDocument();
    expect(screen.queryByDisplayValue("Court 1")).not.toBeInTheDocument();
  });

  it("removing an already-saved court shows a confirm dialog, and Remove soft-deletes it", async () => {
    const user = userEvent.setup();
    installAuth();
    const facility = await seedFacility();
    const [facilitySport] = await seedSports(facility.id, ["sport_badminton"]);
    if (!facilitySport) throw new Error("facilitySport not seeded");
    const saved = await MockPlayingAreaService.createPlayingArea({
      facilityId: facility.id,
      facilitySportId: facilitySport.id,
      sportId: "sport_badminton",
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
      const remaining = await MockPlayingAreaService.getPlayingAreas(facility.id);
      expect(remaining).toHaveLength(0);
    });
    const raw = window.localStorage.getItem("turf.playing-areas.mock.v1") ?? "";
    expect(raw).toContain(saved.id);
  });

  it("blocks Continue and shows an error when a selected sport has zero playing areas", async () => {
    const user = userEvent.setup();
    installAuth();
    const facility = await seedFacility();
    await seedSports(facility.id, ["sport_badminton"]);
    renderWithProviders(<CourtsSetupForm />);

    await screen.findByText("Badminton");
    await user.click(screen.getByRole("button", { name: /Continue/ }));

    expect(await screen.findByText(/Add at least one court for Badminton/)).toBeInTheDocument();
    expect(routerMock.push).not.toHaveBeenCalled();
  });

  it("blocks Continue on duplicate names within the same sport", async () => {
    const user = userEvent.setup();
    installAuth();
    const facility = await seedFacility();
    await seedSports(facility.id, ["sport_badminton"]);
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

  it("saves playing areas and navigates to the operating-hours placeholder on Continue", async () => {
    const user = userEvent.setup();
    installAuth();
    const facility = await seedFacility();
    await seedSports(facility.id, ["sport_badminton"]);
    renderWithProviders(<CourtsSetupForm />);

    await user.click(await screen.findByRole("button", { name: "+ Add Court" }));
    await screen.findByDisplayValue("Court 1");

    await user.click(screen.getByRole("button", { name: /Continue/ }));

    await waitFor(() => expect(routerMock.push).toHaveBeenCalledWith("/onboarding/operating-hours"));
    expect(useOnboardingStore.getState().courtsCompleted).toBe(true);

    const saved = await MockPlayingAreaService.getPlayingAreas(facility.id);
    expect(saved.map((a) => a.name)).toEqual(["Court 1"]);
  });

  it("restores previously saved playing areas after remounting", async () => {
    installAuth();
    const facility = await seedFacility();
    const [facilitySport] = await seedSports(facility.id, ["sport_badminton"]);
    if (!facilitySport) throw new Error("facilitySport not seeded");
    await MockPlayingAreaService.createPlayingArea({
      facilityId: facility.id,
      facilitySportId: facilitySport.id,
      sportId: "sport_badminton",
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