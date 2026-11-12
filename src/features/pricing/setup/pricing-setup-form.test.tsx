import { beforeEach, describe, expect, it, vi } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { PricingSetupForm } from "@/features/pricing/setup/pricing-setup-form";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import {
  installFakeAuthService,
  installFakeFacilityService,
  installFakeOperatingHoursService,
  installFakePlayingAreasService,
  installFakePricingService,
  installFakeSportsService,
  renderWithProviders,
} from "@/test/harness";
import { routerMock } from "@/test/router-mock";

vi.setConfig({ testTimeout: 90_000 });

const FAKE_USER = { id: "owner-1", name: "Uma Shankar", email: "owner@yourturf.com", emailVerified: true, onboardingCompleted: false };

async function setup() {
  installFakeAuthService({ getCurrentUser: vi.fn(async () => FAKE_USER) });
  const facilityService = installFakeFacilityService();
  facilityService.setCurrentUserId(FAKE_USER.id);
  const sportsService = installFakeSportsService();
  const areas = installFakePlayingAreasService();
  installFakeOperatingHoursService();
  const pricing = installFakePricingService();

  const facility = await facilityService.createFacility({
    ownerId: FAKE_USER.id,
    name: "GameAll Sports Arena",
    type: "MULTI_SPORT",
    businessEmail: FAKE_USER.email,
    businessPhone: "9876543210",
    address: { line1: "123 Anna Salai", area: "Ambattur", city: "Chennai", state: "Tamil Nadu", country: "India", pinCode: "600053" },
  });
  const saved = await sportsService.saveFacilitySports(facility.id, [{ facilityId: facility.id, sportId: "sport-badminton", enabled: true }]);
  for (const [i, fs] of saved.entries()) {
    await areas.createPlayingArea({
      id: `court-${i + 1}`,
      facilityId: facility.id,
      facilitySportId: fs.id,
      sportId: fs.sportId,
      name: `Court ${i + 1}`,
      type: "INDOOR",
      status: "ACTIVE",
      bookingEnabled: true,
      archived: false,
      displayOrder: 0,
    });
  }
  return { pricing, facility, facilityService };
}

describe("PricingSetupForm", () => {
  beforeEach(() => {
    window.localStorage.clear();
    useOnboardingStore.getState().reset();
  });

  it("opens on By Sport with the first unpriced sport expanded", async () => {
    await setup();
    renderWithProviders(<PricingSetupForm />);
    expect(await screen.findByRole("radio", { name: /By Sport/ })).toBeChecked();
    expect(screen.getByText("Sport Pricing")).toBeInTheDocument();
    expect(screen.getByLabelText(/Base price per hour/)).toBeInTheDocument();
    expect(screen.getByText("Pricing Settings")).toBeInTheDocument();
  });

  it("Next without a price is refused and nothing is saved", async () => {
    const user = userEvent.setup({ delay: null });
    const { pricing } = await setup();
    renderWithProviders(<PricingSetupForm />);
    await screen.findByLabelText(/Base price per hour/);
    await user.click(screen.getByRole("button", { name: /Next/ }));
    expect(await screen.findByText(/Please fix the highlighted fields/)).toBeInTheDocument();
    expect(pricing.saved).toHaveLength(0);
    expect(routerMock.push).not.toHaveBeenCalled();
  });

  it("saves a base price and moves on to Payments", async () => {
    const user = userEvent.setup({ delay: null });
    const { pricing, facility } = await setup();
    renderWithProviders(<PricingSetupForm />);
    await user.type(await screen.findByLabelText(/Base price per hour/), "400");
    await user.click(screen.getByRole("button", { name: /Next/ }));
    await waitFor(() => expect(routerMock.push).toHaveBeenCalledWith("/onboarding/payments"));
    expect(pricing.saved).toHaveLength(1);
    expect(pricing.saved[0]!.some((r) => r.amountMinor === 40000)).toBe(true);
    const plan = await pricing.getPricingPlan(facility.id);
    expect(plan?.rules.length).toBeGreaterThan(0);
  });

  it("Save as Draft stays on the page", async () => {
    const user = userEvent.setup({ delay: null });
    const { pricing } = await setup();
    renderWithProviders(<PricingSetupForm />);
    await user.type(await screen.findByLabelText(/Base price per hour/), "350");
    await user.click(screen.getByRole("button", { name: /Save as Draft/ }));
    await waitFor(() => expect(pricing.saved).toHaveLength(1));
    expect(routerMock.push).not.toHaveBeenCalled();
  });

  it("switching to By Court shows the court list and that court's editor", async () => {
    const user = userEvent.setup({ delay: null });
    await setup();
    renderWithProviders(<PricingSetupForm />);
    await user.click(await screen.findByRole("radio", { name: /By Court/ }));
    expect(await screen.findByText("Select Court")).toBeInTheDocument();
    expect(screen.getByText(/This pricing applies only to/)).toBeInTheDocument();
    expect(screen.getByText(/Pricing Preview – Court 1/)).toBeInTheDocument();
  });

  it("Back returns to Operating Hours", async () => {
    const user = userEvent.setup({ delay: null });
    await setup();
    renderWithProviders(<PricingSetupForm />);
    await user.click(await screen.findByRole("button", { name: /Back/ }));
    expect(routerMock.replace).toHaveBeenCalledWith("/onboarding/operating-hours");
  });
});
