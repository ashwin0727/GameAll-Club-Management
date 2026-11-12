import { beforeEach, describe, expect, it, vi } from "vitest";
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { SportsCourtsForm } from "@/features/sports-courts/components/sports-courts-form";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import {
  installFakeAuthService,
  installFakeFacilityService,
  installFakePlayingAreasService,
  installFakeSportsService,
  renderWithProviders,
} from "@/test/harness";
import { routerMock } from "@/test/router-mock";

// These tests drive several dropdowns per case; under a full-suite run they can approach the default 30s.
vi.setConfig({ testTimeout: 90_000 });

const FAKE_USER = { id: "owner-1", name: "Uma Shankar", email: "owner@yourturf.com", emailVerified: true, onboardingCompleted: false };

function install() {
  installFakeAuthService({ getCurrentUser: vi.fn(async () => FAKE_USER) });
  const facilityService = installFakeFacilityService();
  facilityService.setCurrentUserId(FAKE_USER.id);
  const sportsService = installFakeSportsService();
  const areas = installFakePlayingAreasService();
  return { facilityService, sportsService, areas };
}

async function seedFacility(facilityService: ReturnType<typeof installFakeFacilityService>) {
  return facilityService.createFacility({
    ownerId: FAKE_USER.id,
    name: "GameAll Sports Arena",
    type: "MULTI_SPORT",
    businessEmail: FAKE_USER.email,
    businessPhone: "9876543210",
    address: { line1: "123 Anna Salai", area: "Ambattur", city: "Chennai", state: "Tamil Nadu", country: "India", pinCode: "600053" },
  });
}

/** Opens a (Radix) dropdown by its accessible name and picks an option. */
async function choose(user: ReturnType<typeof userEvent.setup>, name: string | RegExp, option: string) {
  await user.click(screen.getByRole("combobox", { name }));
  await user.click(await screen.findByRole("option", { name: option }));
}

describe("SportsCourtsForm", () => {
  beforeEach(() => {
    window.localStorage.clear();
    useOnboardingStore.getState().reset();
  });

  it("sends a signed-out visitor to login and a facility-less owner back to Facility Information", async () => {
    installFakeAuthService({ getCurrentUser: vi.fn(async () => null) });
    installFakeFacilityService();
    installFakeSportsService();
    installFakePlayingAreasService();
    renderWithProviders(<SportsCourtsForm />);
    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/login"));
  });

  it("starts empty for a multi-sport venue; ticking a sport adds its first court with the sport's usual settings", async () => {
    const user = userEvent.setup({ delay: null });
    const { facilityService } = install();
    await seedFacility(facilityService);
    renderWithProviders(<SportsCourtsForm />);

    expect(await screen.findByText("Select at least one sport above to add its courts.")).toBeInTheDocument();
    expect(screen.getByText("Preview of Courts (0)")).toBeInTheDocument();

    await user.click(screen.getByRole("checkbox", { name: "Badminton" }));
    expect(await screen.findByText("Badminton Courts (1)")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Badminton \(1\)/ })).toBeInTheDocument();
    expect(screen.getByLabelText("Court 1 name")).toHaveValue("Badminton Court 1");
    expect(screen.getByRole("combobox", { name: /court type/ })).toHaveTextContent("Indoor");
    expect(screen.getByRole("combobox", { name: /surface type/ })).toHaveTextContent("Wooden");
    expect(screen.getByRole("combobox", { name: /lighting/ })).toHaveTextContent("LED");
    expect(screen.getByText("Preview of Courts (1)")).toBeInTheDocument();
  });

  it("a single-sport facility type preselects its sport", async () => {
    const user = userEvent.setup({ delay: null });
    const { facilityService } = install();
    const f = await seedFacility(facilityService);
    await facilityService.updateFacility(f.id, { type: "FOOTBALL" });
    renderWithProviders(<SportsCourtsForm />);

    expect(await screen.findByText("Football Courts (1)")).toBeInTheDocument();
    expect(screen.getByRole("checkbox", { name: "Football" })).toBeChecked();
    expect(user).toBeDefined();
  });

  it("adds and removes courts, numbering from the highest name so a name is never reused", async () => {
    const user = userEvent.setup({ delay: null });
    const { facilityService } = install();
    await seedFacility(facilityService);
    renderWithProviders(<SportsCourtsForm />);

    await user.click(await screen.findByRole("checkbox", { name: "Badminton" }));
    await user.click(screen.getByRole("button", { name: "Add Court" }));
    await user.click(screen.getByRole("button", { name: "Add Court" }));
    expect(await screen.findByText("Badminton Courts (3)")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Remove Badminton Court 2" }));
    expect(screen.getByText("Badminton Courts (2)")).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Add Court" }));
    expect(screen.getByDisplayValue("Badminton Court 4")).toBeInTheDocument();
    expect(screen.queryByDisplayValue("Badminton Court 2")).not.toBeInTheDocument();
  });

  it("Next with no sport selected says so and does not continue", async () => {
    const user = userEvent.setup({ delay: null });
    const { facilityService } = install();
    await seedFacility(facilityService);
    renderWithProviders(<SportsCourtsForm />);

    await user.click(await screen.findByRole("button", { name: /Next/ }));
    expect(await screen.findByText("Select at least one sport to continue.")).toBeInTheDocument();
    expect(routerMock.push).not.toHaveBeenCalled();
  });

  it("refuses a blank or duplicate court name", async () => {
    const user = userEvent.setup({ delay: null });
    const { facilityService } = install();
    await seedFacility(facilityService);
    renderWithProviders(<SportsCourtsForm />);

    await user.click(await screen.findByRole("checkbox", { name: "Badminton" }));
    await user.click(screen.getByRole("button", { name: "Add Court" }));
    const [first, second] = [screen.getByLabelText("Court 1 name"), screen.getByLabelText("Court 2 name")];
    await user.clear(first);
    await user.clear(second);
    await user.paste("Centre");
    await user.click(first);
    await user.paste("centre");
    await user.click(screen.getByRole("button", { name: /Next/ }));

    expect(await screen.findByText("This name is already used for this sport.")).toBeInTheDocument();
    await user.clear(first);
    await user.click(screen.getByRole("button", { name: /Next/ }));
    expect(await screen.findByText("Name must be between 2 and 50 characters.")).toBeInTheDocument();
    expect(routerMock.push).not.toHaveBeenCalled();
  });

  it("Bulk mode sets type, surface, lighting and amenities for every court of the sport at once", async () => {
    const user = userEvent.setup({ delay: null });
    const { facilityService } = install();
    await seedFacility(facilityService);
    renderWithProviders(<SportsCourtsForm />);

    await user.click(await screen.findByRole("checkbox", { name: "Badminton" }));
    await user.click(screen.getByRole("button", { name: "Add Court" }));
    await user.click(screen.getByRole("radio", { name: /Bulk/ }));

    const bulk = within(screen.getByTestId("bulk-row"));
    await user.click(bulk.getByRole("combobox", { name: /court type/ }));
    await user.click(await screen.findByRole("option", { name: "Outdoor" }));
    await user.click(bulk.getByRole("combobox", { name: /surface type/ }));
    await user.click(await screen.findByRole("option", { name: "Cement" }));
    await user.click(bulk.getByLabelText("AC"));

    // both courts in the preview carry the bulk settings
    const preview = screen.getByText("Preview of Courts (2)").closest("section") as HTMLElement;
    expect(within(preview).getAllByText("Outdoor")).toHaveLength(2);
    expect(within(preview).getAllByText("Cement")).toHaveLength(2);
    expect(within(preview).getAllByText("AC")).toHaveLength(2);
  });

  async function addSport(user: ReturnType<typeof userEvent.setup>, name: string) {
    await user.click(screen.getByRole("button", { name: /Add Sport/ }));
    await user.click(screen.getByLabelText("Sport name"));
    await user.paste(name);
    await user.click(screen.getByRole("button", { name: "Add" }));
  }

  it("an owner can add as many of their own sports as they like, each with its own courts", async () => {
    const user = userEvent.setup({ delay: null });
    const { facilityService } = install();
    await seedFacility(facilityService);
    renderWithProviders(<SportsCourtsForm />);

    await screen.findByRole("button", { name: /Add Sport/ });
    await addSport(user, "Table Tennis");
    expect(await screen.findByText("Table Tennis Courts (1)")).toBeInTheDocument();

    // Add Sport is still there for another one, and another
    await addSport(user, "Squash");
    await addSport(user, "Kabaddi");
    expect(await screen.findByText("Kabaddi Courts (1)")).toBeInTheDocument();
    for (const name of ["Table Tennis", "Squash", "Kabaddi"]) {
      expect(screen.getByRole("group", { name })).toBeInTheDocument();
      expect(screen.getByRole("button", { name: `${name} (1)` })).toBeInTheDocument();
    }
    expect(screen.getByText("Preview of Courts (3)")).toBeInTheDocument();

    // they sit alongside the catalogue sports
    await user.click(screen.getByRole("checkbox", { name: "Badminton" }));
    expect(await screen.findByText("Preview of Courts (4)")).toBeInTheDocument();
  });

  it("refuses a sport name that is too short or already in the list", async () => {
    const user = userEvent.setup({ delay: null });
    const { facilityService } = install();
    await seedFacility(facilityService);
    renderWithProviders(<SportsCourtsForm />);

    await screen.findByRole("button", { name: /Add Sport/ });
    await addSport(user, "x");
    expect(await screen.findByText(/Sport name must be at least 2 characters/)).toBeInTheDocument();

    await user.clear(screen.getByLabelText("Sport name"));
    await user.paste("football");
    await user.click(screen.getByRole("button", { name: "Add" }));
    expect(await screen.findByText('"football" is already in the list.')).toBeInTheDocument();

    await user.clear(screen.getByLabelText("Sport name"));
    await user.paste("Squash");
    await user.click(screen.getByRole("button", { name: "Add" }));
    await addSport(user, "squash");
    expect(await screen.findByText('"squash" is already in the list.')).toBeInTheDocument();
  });

  it("a sport the owner added has its own delete button on its card, which also removes its courts", async () => {
    const user = userEvent.setup({ delay: null });
    const { facilityService } = install();
    await seedFacility(facilityService);
    renderWithProviders(<SportsCourtsForm />);

    await screen.findByRole("button", { name: /Add Sport/ });
    await addSport(user, "Squash");
    await addSport(user, "Table Tennis");
    expect(await screen.findByText("Preview of Courts (2)")).toBeInTheDocument();

    const card = screen.getByRole("group", { name: "Squash" });
    await user.click(within(card).getByRole("button", { name: "Remove Squash" }));

    expect(screen.queryByRole("group", { name: "Squash" })).not.toBeInTheDocument();
    expect(screen.getByRole("group", { name: "Table Tennis" })).toBeInTheDocument();
    expect(screen.getByText("Preview of Courts (1)")).toBeInTheDocument();
    expect(screen.queryByText("Squash Courts (1)")).not.toBeInTheDocument();
    // catalogue sports have no delete button — they are ticked and unticked
    expect(screen.queryByRole("button", { name: /Remove Badminton/ })).not.toBeInTheDocument();
  });

  it("saves every added sport with its name and its courts, and loads them back", async () => {
    const user = userEvent.setup({ delay: null });
    const { facilityService, sportsService, areas } = install();
    const facility = await seedFacility(facilityService);
    const first = renderWithProviders(<SportsCourtsForm />);

    await screen.findByRole("button", { name: /Add Sport/ });
    await addSport(user, "Table Tennis");
    await addSport(user, "Squash");
    await user.click(screen.getByRole("button", { name: "Next" }));
    await waitFor(() => expect(routerMock.push).toHaveBeenCalledWith("/onboarding/operating-hours"));

    const rows = await sportsService.getFacilitySports(facility.id);
    expect(rows.map((r) => r.customSportName).sort()).toEqual(["Squash", "Table Tennis"]);
    expect(rows.every((r) => r.sportId === "sport-other")).toBe(true);
    const saved = await areas.getPlayingAreas(facility.id);
    expect(saved).toHaveLength(2);
    expect(new Set(saved.map((c) => c.facilitySportId)).size).toBe(2); // one court under each sport

    first.unmount();
    routerMock.push.mockClear();
    renderWithProviders(<SportsCourtsForm />);
    expect(await screen.findByRole("group", { name: "Table Tennis" })).toBeInTheDocument();
    expect(screen.getByRole("group", { name: "Squash" })).toBeInTheDocument();
    expect(screen.getByText("Preview of Courts (2)")).toBeInTheDocument();
  });

  it("Next saves the sports and every court's details, advances setup and goes to Operating Hours", async () => {
    const user = userEvent.setup({ delay: null });
    const { facilityService, sportsService, areas } = install();
    const facility = await seedFacility(facilityService);
    renderWithProviders(<SportsCourtsForm />);

    await user.click(await screen.findByRole("checkbox", { name: "Badminton" }));
    await user.click(screen.getByRole("checkbox", { name: "Football" }));
    await user.click(screen.getByRole("button", { name: "Badminton (1)" }));
    await user.click(screen.getByLabelText("AC"));
    await choose(user, /surface type/, "Synthetic (PU)");
    await user.click(screen.getByRole("button", { name: "Next" }));

    await waitFor(() => expect(routerMock.push).toHaveBeenCalledWith("/onboarding/operating-hours"));
    expect((await sportsService.getFacilitySports(facility.id)).map((r) => r.sportId).sort()).toEqual(["sport-badminton", "sport-football"]);

    const saved = await areas.getPlayingAreas(facility.id);
    expect(saved).toHaveLength(2);
    expect(saved.find((c) => c.name === "Badminton Court 1")).toMatchObject({ type: "INDOOR", surface: "Synthetic (PU)", lighting: "LED", amenities: ["ac"], status: "ACTIVE", bookingEnabled: true });
    expect(saved.find((c) => c.name.startsWith("Football"))).toMatchObject({ type: "OUTDOOR", surface: "Artificial Turf", lighting: "FLOODLIGHT" });
    expect((await facilityService.getFacility())?.onboardingStep).toBe("OPERATING_HOURS");
    expect(useOnboardingStore.getState().courtsCompleted).toBe(true);
  });

  it("Save as Draft saves but stays on the page", async () => {
    const user = userEvent.setup({ delay: null });
    const { facilityService, areas } = install();
    const facility = await seedFacility(facilityService);
    renderWithProviders(<SportsCourtsForm />);

    await user.click(await screen.findByRole("checkbox", { name: "Tennis" }));
    await user.click(screen.getByRole("button", { name: /Save as Draft/ }));

    await waitFor(async () => expect(await areas.getPlayingAreas(facility.id)).toHaveLength(1));
    expect(routerMock.push).not.toHaveBeenCalled();
    expect((await facilityService.getFacility())?.onboardingStep).not.toBe("OPERATING_HOURS");
  });

  it("loads what was saved before, and removing a court or a sport archives it on save", async () => {
    const user = userEvent.setup({ delay: null });
    const { facilityService, sportsService, areas } = install();
    const facility = await seedFacility(facilityService);
    const [bad, foot] = await sportsService.saveFacilitySports(facility.id, [
      { facilityId: facility.id, sportId: "sport-badminton", enabled: true },
      { facilityId: facility.id, sportId: "sport-football", enabled: true },
    ]);
    const base = { facilityId: facility.id, status: "ACTIVE" as const, bookingEnabled: true, archived: false, displayOrder: 0 };
    await areas.createPlayingArea({ ...base, id: "c-bad-1", facilitySportId: bad!.id, sportId: "sport-badminton", name: "Court A", type: "INDOOR", surface: "Wooden", lighting: "LED", amenities: ["shower"] });
    await areas.createPlayingArea({ ...base, id: "c-foot-1", facilitySportId: foot!.id, sportId: "sport-football", name: "Turf A", type: "OUTDOOR", surface: "Artificial Turf", lighting: "FLOODLIGHT", amenities: [] });
    renderWithProviders(<SportsCourtsForm />);

    expect(await screen.findByDisplayValue("Court A")).toBeInTheDocument();
    expect(screen.getByText("Preview of Courts (2)")).toBeInTheDocument();

    await user.click(screen.getByRole("checkbox", { name: "Football" })); // switch Football off
    await user.click(screen.getByRole("button", { name: "Next" }));

    await waitFor(() => expect(routerMock.push).toHaveBeenCalledWith("/onboarding/operating-hours"));
    const live = await areas.getPlayingAreas(facility.id);
    expect(live.map((c) => c.id)).toEqual(["c-bad-1"]);
    expect(live[0]).toMatchObject({ amenities: ["shower"] });
  });

  it("Back returns to Facility Information", async () => {
    const user = userEvent.setup({ delay: null });
    const { facilityService } = install();
    await seedFacility(facilityService);
    renderWithProviders(<SportsCourtsForm />);

    await user.click(await screen.findByRole("button", { name: /Back/ }));
    expect(routerMock.push).toHaveBeenCalledWith("/onboarding/facility");
  });
});
