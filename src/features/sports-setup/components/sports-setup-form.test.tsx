import { beforeEach, describe, expect, it, vi } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { SportsSetupForm } from "@/features/sports-setup/components/sports-setup-form";
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

async function seedFacility(type: "MULTI_SPORT" | "BADMINTON" = "MULTI_SPORT") {
  return MockFacilityService.saveFacility({
    ownerId: FAKE_USER.id,
    name: "GameAll Sports Arena",
    type,
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

describe("SportsSetupForm", () => {
  beforeEach(() => {
    window.localStorage.clear();
    useOnboardingStore.getState().reset();
  });

  it("redirects to /login when there is no signed-in user", async () => {
    installFakeAuthService({ getCurrentUser: vi.fn(async () => null) });
    renderWithProviders(<SportsSetupForm />);

    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/login"));
  });

  it("redirects to /onboarding/facility when the user has no facility yet", async () => {
    installAuth();
    renderWithProviders(<SportsSetupForm />);

    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/onboarding/facility"));
  });

  it("shows the facility name once loaded", async () => {
    installAuth();
    await seedFacility();
    renderWithProviders(<SportsSetupForm />);

    expect(await screen.findByText("GameAll Sports Arena")).toBeInTheDocument();
  });

  it("preselects the matching sport for a single-sport facility type on first visit", async () => {
    installAuth();
    await seedFacility("BADMINTON");
    renderWithProviders(<SportsSetupForm />);

    await screen.findByText("GameAll Sports Arena");
    expect(screen.getByRole("checkbox", { name: /Badminton/ })).toHaveAttribute("aria-checked", "true");
  });

  it("keeps Continue disabled until at least one sport is selected", async () => {
    installAuth();
    await seedFacility();
    renderWithProviders(<SportsSetupForm />);

    await screen.findByText("GameAll Sports Arena");
    expect(screen.getByRole("button", { name: /Continue/ })).toBeDisabled();
  });

  it("allows selecting multiple sports and updates the summary count", async () => {
    const user = userEvent.setup();
    installAuth();
    await seedFacility();
    renderWithProviders(<SportsSetupForm />);

    await screen.findByText("GameAll Sports Arena");
    await user.click(screen.getByText("Indoor racket sport"));
    await user.click(screen.getByText("Court-based paddle sport"));

    expect(await screen.findByText("2 sports selected")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Continue/ })).toBeEnabled();
  });

  it("deselecting a sport removes it from the count", async () => {
    const user = userEvent.setup();
    installAuth();
    await seedFacility();
    renderWithProviders(<SportsSetupForm />);

    await screen.findByText("GameAll Sports Arena");
    await user.click(screen.getByText("Indoor racket sport"));
    expect(await screen.findByText("1 sport selected")).toBeInTheDocument();

    await user.click(screen.getByText("Indoor racket sport"));
    expect(await screen.findByText("No sports selected")).toBeInTheDocument();
  });

  it("shows the sport-name input only when Other is selected, and requires a valid name to continue", async () => {
    const user = userEvent.setup();
    installAuth();
    await seedFacility();
    renderWithProviders(<SportsSetupForm />);

    await screen.findByText("GameAll Sports Arena");
    expect(screen.queryByLabelText("Sport Name")).not.toBeInTheDocument();

    await user.click(screen.getByText("A sport not listed here"));
    expect(await screen.findByLabelText("Sport Name")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: /Continue/ }));
    expect(await screen.findByText("Sport name must be at least 2 characters")).toBeInTheDocument();
    expect(routerMock.push).not.toHaveBeenCalled();
  });

  it("saves the selected sports and navigates to the courts placeholder on submit", async () => {
    const user = userEvent.setup();
    installAuth();
    const facility = await seedFacility();
    renderWithProviders(<SportsSetupForm />);

    await screen.findByText("GameAll Sports Arena");
    await user.click(screen.getByText("Indoor racket sport"));
    await user.click(screen.getByText("Court-based paddle sport"));
    await user.click(screen.getByRole("button", { name: /Continue/ }));

    await waitFor(() => expect(routerMock.push).toHaveBeenCalledWith("/onboarding/courts"));

    const saved = await MockSportService.getFacilitySports(facility.id);
    expect(saved.map((row) => row.sportId).sort()).toEqual(["sport_badminton", "sport_pickleball"]);
    expect(useOnboardingStore.getState().sportsCompleted).toBe(true);
  });

  it("restores a previously saved selection scoped to the correct facility", async () => {
    installAuth();
    const facility = await seedFacility();
    await MockSportService.saveFacilitySports(facility.id, [
      { facilityId: facility.id, sportId: "sport_cricket", enabled: true },
    ]);

    renderWithProviders(<SportsSetupForm />);

    await screen.findByText("GameAll Sports Arena");
    expect(screen.getByRole("checkbox", { name: /Cricket/ })).toHaveAttribute("aria-checked", "true");
    expect(screen.getByRole("checkbox", { name: /Badminton/ })).toHaveAttribute("aria-checked", "false");
  });
});