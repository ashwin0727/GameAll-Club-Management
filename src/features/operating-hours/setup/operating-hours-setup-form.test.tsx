import { beforeEach, describe, expect, it, vi } from "vitest";
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { addDays, format } from "date-fns";
import { OperatingHoursSetupForm } from "@/features/operating-hours/setup/operating-hours-setup-form";
import { scheduleFromPlans, defaultPlans } from "@/features/operating-hours/setup-model";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import {
  installFakeAuthService,
  installFakeFacilityService,
  installFakeOperatingHoursService,
  installFakePlayingAreasService,
  installFakeSportsService,
  renderWithProviders,
} from "@/test/harness";
import { routerMock } from "@/test/router-mock";

// Each case drives several dropdowns; under a full-suite run they can approach the default 30s.
vi.setConfig({ testTimeout: 90_000 });

const FAKE_USER = { id: "owner-1", name: "Uma Shankar", email: "owner@yourturf.com", emailVerified: true, onboardingCompleted: false };

async function setup(opts: { twoSports?: boolean } = {}) {
  installFakeAuthService({ getCurrentUser: vi.fn(async () => FAKE_USER) });
  const facilityService = installFakeFacilityService();
  facilityService.setCurrentUserId(FAKE_USER.id);
  const sportsService = installFakeSportsService();
  const areas = installFakePlayingAreasService();
  const hours = installFakeOperatingHoursService();

  const facility = await facilityService.createFacility({
    ownerId: FAKE_USER.id,
    name: "GameAll Sports Arena",
    type: "MULTI_SPORT",
    businessEmail: FAKE_USER.email,
    businessPhone: "9876543210",
    address: { line1: "123 Anna Salai", area: "Ambattur", city: "Chennai", state: "Tamil Nadu", country: "India", pinCode: "600053" },
  });
  const sportIds = opts.twoSports ? ["sport-badminton", "sport-football"] : ["sport-badminton"];
  const saved = await sportsService.saveFacilitySports(
    facility.id,
    sportIds.map((sportId) => ({ facilityId: facility.id, sportId, enabled: true })),
  );
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
  return { facilityService, hours, facility, areas };
}

/** Opens a (Radix) dropdown by its accessible name and picks an option. */
async function choose(user: ReturnType<typeof userEvent.setup>, name: string | RegExp, option: string) {
  await user.click(screen.getByRole("combobox", { name }));
  await user.click(await screen.findByRole("option", { name: option }));
}

describe("OperatingHoursSetupForm", () => {
  beforeEach(() => {
    window.localStorage.clear();
    useOnboardingStore.getState().reset();
  });

  it("starts with Standard Hours: Monday to Saturday, 6 AM to 11 PM, Sunday closed", async () => {
    await setup();
    renderWithProviders(<OperatingHoursSetupForm />);

    expect(await screen.findByRole("radio", { name: /Standard Hours/ })).toBeChecked();
    for (const day of ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]) expect(screen.getByLabelText(day)).toBeChecked();
    expect(screen.getByLabelText("Sun")).not.toBeChecked();
    expect(screen.getByRole("combobox", { name: "Opens at" })).toHaveTextContent("6:00 AM");
    expect(screen.getByRole("combobox", { name: "Closes at" })).toHaveTextContent("11:00 PM");
    expect(screen.getByTestId("daily-total")).toHaveTextContent("17 Hours");
    expect(screen.getByText("Weekly Schedule Preview")).toBeInTheDocument();
  });

  it("changing the times updates the total and the weekly preview", async () => {
    const user = userEvent.setup({ delay: null });
    await setup();
    renderWithProviders(<OperatingHoursSetupForm />);

    await screen.findByRole("radio", { name: /Standard Hours/ });
    await choose(user, "Closes at", "10:00 PM");
    expect(screen.getByTestId("daily-total")).toHaveTextContent("16 Hours");
    expect(screen.getAllByText("6:00 AM – 10:00 PM")).toHaveLength(6);
  });

  it("an overnight close counts past midnight and says so", async () => {
    const user = userEvent.setup({ delay: null });
    await setup();
    renderWithProviders(<OperatingHoursSetupForm />);

    await screen.findByRole("radio", { name: /Standard Hours/ });
    await choose(user, "Closes at", "12:00 AM");
    expect(screen.getByTestId("daily-total")).toHaveTextContent("18 Hours");
    expect(screen.getAllByText("6:00 AM – 12:00 AM (next day)").length).toBeGreaterThan(0);
  });

  it("days can be switched off, and with none open Next refuses", async () => {
    const user = userEvent.setup({ delay: null });
    await setup();
    renderWithProviders(<OperatingHoursSetupForm />);

    await screen.findByRole("radio", { name: /Standard Hours/ });
    await user.click(screen.getByLabelText("Sat"));
    const preview = screen.getByText("Weekly Schedule Preview").closest("section") as HTMLElement;
    expect(within(preview).getAllByText("Closed")).toHaveLength(2); // Sat and Sun

    for (const day of ["Mon", "Tue", "Wed", "Thu", "Fri"]) await user.click(screen.getByLabelText(day));
    await user.click(screen.getByRole("button", { name: /Next/ }));
    expect(await screen.findByText("Select at least one operating day.")).toBeInTheDocument();
    expect(routerMock.push).not.toHaveBeenCalled();
  });

  it("Custom Hours: each day has its own times and status, with a weekly total", async () => {
    const user = userEvent.setup({ delay: null });
    await setup();
    renderWithProviders(<OperatingHoursSetupForm />);

    await user.click(await screen.findByRole("radio", { name: /Custom Hours/ }));
    expect(screen.getByText("Set Custom Operating Hours")).toBeInTheDocument();
    expect(screen.getByTestId("weekly-total")).toHaveTextContent("102 Hours"); // 6 days x 17 h

    await choose(user, "Wednesday closes at", "10:00 PM");
    expect(screen.getByTestId("weekly-total")).toHaveTextContent("101 Hours");

    await user.click(screen.getByLabelText("Friday"));
    expect(screen.getByTestId("weekly-total")).toHaveTextContent("84 Hours");
    expect(screen.getAllByText("Closed").length).toBeGreaterThanOrEqual(2);
  });

  it("switching to Custom keeps the standard hours, and back to Standard takes the first open day's hours", async () => {
    const user = userEvent.setup({ delay: null });
    await setup();
    renderWithProviders(<OperatingHoursSetupForm />);

    await screen.findByRole("radio", { name: /Standard Hours/ });
    await choose(user, "Opens at", "7:00 AM");
    await user.click(screen.getByRole("radio", { name: /Custom Hours/ }));
    expect(screen.getByRole("combobox", { name: "Monday opens at" })).toHaveTextContent("7:00 AM");
    await user.click(screen.getByRole("radio", { name: /Standard Hours/ }));
    expect(screen.getByRole("combobox", { name: "Opens at" })).toHaveTextContent("7:00 AM");
  });

  it("a break must be a real range inside the working hours, shows in the preview and takes hours off", async () => {
    const user = userEvent.setup({ delay: null });
    await setup();
    renderWithProviders(<OperatingHoursSetupForm />);

    await screen.findByRole("radio", { name: /Standard Hours/ });
    await user.click(screen.getByRole("switch", { name: /Set a break time/ }));
    expect(screen.getByRole("combobox", { name: "Break starts at" })).toHaveTextContent("1:00 PM");
    expect(screen.getByTestId("daily-total")).toHaveTextContent("16 Hours");
    expect(screen.getByText(/Daily break: 1:00 PM – 2:00 PM/)).toBeInTheDocument();

    await choose(user, "Break starts at", "5:00 AM");
    await choose(user, "Break ends at", "5:30 AM");
    await user.click(screen.getByRole("button", { name: /Next/ }));
    expect(await screen.findByText("The break must fall inside the working hours of every open day.")).toBeInTheDocument();
    expect(routerMock.push).not.toHaveBeenCalled();
  });

  it("adds, edits and removes a holiday", async () => {
    const user = userEvent.setup({ delay: null });
    await setup();
    renderWithProviders(<OperatingHoursSetupForm />);

    await screen.findByRole("radio", { name: /Standard Hours/ });
    const tomorrow = addDays(new Date(), 1);
    await user.click(screen.getByRole("button", { name: /Add Holiday \/ Closure/ }));
    const dialog = await screen.findByRole("dialog");
    await user.click(within(dialog).getByLabelText(/^Name/));
    await user.paste("Diwali");
    await user.click(within(dialog).getByRole("gridcell", { name: format(tomorrow, "d MMMM yyyy") }));
    expect(within(dialog).getByText(/^Selected:/)).toBeInTheDocument();
    await user.click(within(dialog).getByRole("button", { name: "Add" }));

    expect(await screen.findByText("Diwali")).toBeInTheDocument();
    expect(screen.getByText(new RegExp(format(tomorrow, "yyyy")))).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Edit Diwali" }));
    const edit = await screen.findByRole("dialog");
    const nameBox = within(edit).getByLabelText(/^Name/);
    await user.clear(nameBox);
    await user.paste("Deepavali");
    await user.click(within(edit).getByRole("button", { name: "Save" }));
    expect(await screen.findByText("Deepavali")).toBeInTheDocument();
    expect(screen.queryByText("Diwali")).not.toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Remove Deepavali" }));
    expect(screen.queryByText("Deepavali")).not.toBeInTheDocument();
  });

  it("refuses a holiday without a name or a date, or on a date already marked", async () => {
    const user = userEvent.setup({ delay: null });
    await setup();
    renderWithProviders(<OperatingHoursSetupForm />);

    await screen.findByRole("radio", { name: /Standard Hours/ });
    const day = format(addDays(new Date(), 2), "d MMMM yyyy");

    await user.click(screen.getByRole("button", { name: /Add Holiday \/ Closure/ }));
    let dialog = await screen.findByRole("dialog");
    await user.click(within(dialog).getByRole("button", { name: "Add" }));
    expect(await within(dialog).findByText("Select a date.")).toBeInTheDocument();

    await user.click(within(dialog).getByRole("gridcell", { name: day }));
    await user.click(within(dialog).getByRole("button", { name: "Add" }));
    expect(await within(dialog).findByText("Enter a name of at least 2 characters.")).toBeInTheDocument();

    await user.click(within(dialog).getByLabelText(/^Name/));
    await user.paste("Event");
    await user.click(within(dialog).getByRole("button", { name: "Add" }));
    expect(await screen.findByText("Event")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: /Add Holiday \/ Closure/ }));
    dialog = await screen.findByRole("dialog");
    await user.click(within(dialog).getByLabelText(/^Name/));
    await user.paste("Another");
    await user.click(within(dialog).getByRole("gridcell", { name: day }));
    await user.click(within(dialog).getByRole("button", { name: "Add" }));
    expect(await within(dialog).findByText("This date is already marked as closed.")).toBeInTheDocument();
  });

  it("past dates cannot be chosen", async () => {
    const user = userEvent.setup({ delay: null });
    await setup();
    renderWithProviders(<OperatingHoursSetupForm />);

    await screen.findByRole("radio", { name: /Standard Hours/ });
    await user.click(screen.getByRole("button", { name: /Add Holiday \/ Closure/ }));
    const dialog = await screen.findByRole("dialog");
    const yesterday = addDays(new Date(), -1);
    if (yesterday.getMonth() === new Date().getMonth()) {
      expect(within(dialog).getByRole("gridcell", { name: format(yesterday, "d MMMM yyyy") })).toBeDisabled();
    }
    expect(within(dialog).getByRole("gridcell", { name: format(new Date(), "d MMMM yyyy") })).toBeEnabled();
  });

  it("Next saves the schedule, closures and settings, advances setup and goes to Pricing", async () => {
    const user = userEvent.setup({ delay: null });
    const { hours, facilityService, facility } = await setup();
    renderWithProviders(<OperatingHoursSetupForm />);

    await screen.findByRole("radio", { name: /Standard Hours/ });
    await choose(user, "Closes at", "10:00 PM");
    await user.click(screen.getByRole("switch", { name: /Allow bookings outside operating hours/ })); // on by default -> off
    await user.click(screen.getByRole("switch", { name: /Set a break time/ }));
    await user.click(screen.getByRole("button", { name: /Next/ }));

    await waitFor(() => expect(routerMock.push).toHaveBeenCalledWith("/onboarding/pricing"));
    const saved = await hours.getFacilitySchedule(facility.id);
    const mon = saved!.days.find((d) => d.dayOfWeek === 1)!;
    expect(mon.slots.map((s) => [s.startTime, s.endTime])).toEqual([["06:00", "13:00"], ["14:00", "22:00"]]);
    expect(saved!.days.find((d) => d.dayOfWeek === 0)).toMatchObject({ isClosed: true });

    const f = await facilityService.getFacility();
    expect(f?.hoursSettings).toMatchObject({ allowBookingsOutsideHours: false, breakStart: "13:00", breakEnd: "14:00", sportWiseHours: false });
    expect(f?.onboardingStep).toBe("PRICING");
    expect(useOnboardingStore.getState().operatingHoursCompleted).toBe(true);
  });

  it("Save as Draft saves but stays on the page", async () => {
    const user = userEvent.setup({ delay: null });
    const { hours, facility } = await setup();
    renderWithProviders(<OperatingHoursSetupForm />);

    await screen.findByRole("radio", { name: /Standard Hours/ });
    await user.click(screen.getByRole("button", { name: /Save as Draft/ }));
    await waitFor(async () => expect(await hours.getFacilitySchedule(facility.id)).not.toBeNull());
    expect(routerMock.push).not.toHaveBeenCalled();
  });

  it("Sport-wise hours: each sport gets its own hours, applied to each of its courts", async () => {
    const user = userEvent.setup({ delay: null });
    const { hours } = await setup({ twoSports: true });
    renderWithProviders(<OperatingHoursSetupForm />);

    await screen.findByRole("radio", { name: /Standard Hours/ });
    await user.click(screen.getByRole("switch", { name: /Apply sport-wise operating hours/ }));
    const badminton = await screen.findByRole("region", { name: "Badminton hours" });
    expect(within(badminton).getByRole("combobox", { name: "Badminton opens at" })).toHaveTextContent("6:00 AM");

    await user.click(within(badminton).getByRole("combobox", { name: "Badminton closes at" }));
    await user.click(await screen.findByRole("option", { name: "10:00 PM" }));
    await user.click(screen.getByRole("button", { name: /Next/ }));

    await waitFor(() => expect(routerMock.push).toHaveBeenCalledWith("/onboarding/pricing"));
    const court1 = await hours.getPlayingAreaSchedule("court-1"); // badminton
    const court2 = await hours.getPlayingAreaSchedule("court-2"); // football keeps the venue's 11 PM
    expect(court1!.days.find((d) => d.dayOfWeek === 1)!.slots[0]).toMatchObject({ startTime: "06:00", endTime: "22:00" });
    expect(court2!.days.find((d) => d.dayOfWeek === 1)!.slots[0]).toMatchObject({ startTime: "06:00", endTime: "23:00" });
  });

  it("Sport-wise hours hides the venue-wide hours and lets a sport be open 24 hours", async () => {
    const user = userEvent.setup({ delay: null });
    const { hours } = await setup({ twoSports: true });
    renderWithProviders(<OperatingHoursSetupForm />);

    await screen.findByRole("radio", { name: /Standard Hours/ });
    await user.click(screen.getByRole("switch", { name: /Apply sport-wise operating hours/ }));
    const badminton = await screen.findByRole("region", { name: "Badminton hours" });
    expect(screen.queryByRole("radio", { name: /Standard Hours/ })).not.toBeInTheDocument();
    expect(screen.queryByText("Weekly Schedule Preview")).not.toBeInTheDocument();
    expect(screen.queryByText("Set Operating Days & Hours")).not.toBeInTheDocument();

    await user.click(within(badminton).getByLabelText("Open 24 hours"));
    expect(within(badminton).queryByRole("combobox", { name: "Badminton opens at" })).not.toBeInTheDocument();
    expect(within(badminton).getByText("Open 24 hours", { selector: "span" })).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: /Next/ }));
    await waitFor(() => expect(routerMock.push).toHaveBeenCalledWith("/onboarding/pricing"));
    const court1 = await hours.getPlayingAreaSchedule("court-1");
    expect(court1!.days.find((d) => d.dayOfWeek === 1)).toMatchObject({ is24Hours: true });
  });

  it("turning sport-wise hours off clears the courts' own hours", async () => {
    const user = userEvent.setup({ delay: null });
    const { hours, facility, facilityService } = await setup();
    await facilityService.updateFacility(facility.id, { hoursSettings: { allowBookingsOutsideHours: true, sportWiseHours: true } });
    await hours.savePlayingAreaSchedule("court-1", facility.id, scheduleFromPlans(defaultPlans()));
    renderWithProviders(<OperatingHoursSetupForm />);

    await screen.findByRole("region", { name: "Badminton hours" });
    await user.click(screen.getByRole("switch", { name: /Apply sport-wise operating hours/ }));
    await user.click(screen.getByRole("button", { name: /Next/ }));

    await waitFor(() => expect(routerMock.push).toHaveBeenCalledWith("/onboarding/pricing"));
    expect(hours.deletedOverrides).toContain("court-1");
    expect(await hours.getPlayingAreaSchedule("court-1")).toBeNull();
  });

  it("loads what was saved: custom hours, a break, closures and the settings", async () => {
    const { hours, facility, facilityService } = await setup();
    const plans = defaultPlans().map((p) => (p.dayOfWeek === 2 ? { ...p, close: "21:00" } : p));
    await hours.saveFacilitySchedule(facility.id, scheduleFromPlans(plans, { start: "12:00", end: "13:00" }));
    await hours.replaceClosures(facility.id, [{ date: "2099-08-15", name: "Independence Day" }]);
    await facilityService.updateFacility(facility.id, { hoursSettings: { allowBookingsOutsideHours: false, breakStart: "12:00", breakEnd: "13:00", sportWiseHours: false } });
    renderWithProviders(<OperatingHoursSetupForm />);

    expect(await screen.findByRole("radio", { name: /Custom Hours/ })).toBeChecked(); // Tuesday differs
    expect(screen.getByRole("combobox", { name: "Tuesday closes at" })).toHaveTextContent("9:00 PM");
    expect(screen.getByText("Independence Day")).toBeInTheDocument();
    expect(screen.getByRole("switch", { name: /Set a break time/ })).toHaveAttribute("aria-checked", "true");
    expect(screen.getByRole("switch", { name: /Allow bookings outside operating hours/ })).toHaveAttribute("aria-checked", "false");
  });

  it("Back returns to Sports & Courts", async () => {
    const user = userEvent.setup({ delay: null });
    await setup();
    renderWithProviders(<OperatingHoursSetupForm />);

    await user.click(await screen.findByRole("button", { name: /Back/ }));
    expect(routerMock.push).toHaveBeenCalledWith("/onboarding/sports");
  });

  it("sends a venue with no courts back to Sports & Courts", async () => {
    installFakeAuthService({ getCurrentUser: vi.fn(async () => FAKE_USER) });
    const facilityService = installFakeFacilityService();
    facilityService.setCurrentUserId(FAKE_USER.id);
    installFakeSportsService();
    installFakePlayingAreasService();
    installFakeOperatingHoursService();
    await facilityService.createFacility({
      ownerId: FAKE_USER.id,
      name: "Arena",
      type: "MULTI_SPORT",
      businessEmail: FAKE_USER.email,
      businessPhone: "9876543210",
      address: { line1: "a", area: "b", city: "c", state: "Tamil Nadu", country: "India", pinCode: "600001" },
    });
    renderWithProviders(<OperatingHoursSetupForm />);
    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/onboarding/sports"));
  });
});
