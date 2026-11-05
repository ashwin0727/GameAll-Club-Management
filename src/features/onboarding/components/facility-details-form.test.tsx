import { beforeEach, describe, expect, it, vi } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { FacilityDetailsForm } from "@/features/onboarding/components/facility-details-form";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import { installFakeAuthService, installFakeFacilityService, renderWithProviders } from "@/test/harness";
import { routerMock } from "@/test/router-mock";

// The photo uploads talk to Supabase storage; the form only needs to know they were asked for.
const photoMock = vi.hoisted(() => ({ addAll: vi.fn(async () => undefined), upload: vi.fn(async () => "https://img.test/logo.png") }));
vi.mock("@/features/facility-profile/photos", async (importOriginal) => {
  const real = await importOriginal<typeof import("@/features/facility-profile/photos")>();
  return {
    ...real,
    FacilityPhotos: class {
      addAll = photoMock.addAll;
      upload = photoMock.upload;
    },
  };
});

const MAPS_LINK = "https://maps.app.goo.gl/AbCdEf123";
const photoFile = () => new File(["x"], "court.jpg", { type: "image/jpeg" });

const VALID = {
  facilityName: "GameAll Sports Arena",
  businessPhone: "9876543210",
  addressLine: "123 Anna Salai",
  area: "Ambattur",
  city: "Chennai",
  pinCode: "600053",
};

const FAKE_USER = {
  id: "user-1",
  name: "Ravi Kumar",
  email: "owner@yourturf.com",
  emailVerified: true,
  onboardingCompleted: false,
};

/**
 * FacilityDetailsForm reads the signed-in user via useCurrentUser(), which
 * calls getCurrentUser() — the harness default for that method resolves to
 * null, so every test here must override it or the submit handler's
 * `if (!user) return;` guard will silently no-op.
 */
function installAuth() {
  const auth = installFakeAuthService({ getCurrentUser: vi.fn(async () => FAKE_USER) });
  const facilityService = installFakeFacilityService();
  facilityService.setCurrentUserId(FAKE_USER.id);
  return auth;
}

/** Fills every required field. Values are pasted rather than typed key by key: one event per field keeps the test
 *  fast (and independent of how busy the machine is), and the form's own field handling still runs on each paste. */
async function fillValidForm(user: ReturnType<typeof userEvent.setup>) {
  async function fill(label: string, value: string) {
    await user.click(screen.getByLabelText(label));
    await user.paste(value);
  }
  await fill("Facility Name", VALID.facilityName);
  await fill("Business Contact Number", VALID.businessPhone);
  await fill("Address", VALID.addressLine);
  await fill("Area / Locality", VALID.area);
  await fill("City", VALID.city);
  await user.click(screen.getByRole("combobox", { name: /state/i }));
  await user.click(await screen.findByRole("option", { name: "Tamil Nadu" }));
  await fill("PIN Code", VALID.pinCode);
  await fill("Google Map Location Link", MAPS_LINK);
  await user.click(screen.getByRole("radio", { name: /Indoor/ }));
}

/** The required photo. */
async function addPhoto(user: ReturnType<typeof userEvent.setup>) {
  await user.upload(screen.getByLabelText("Facility Photos"), photoFile());
}

/** The facility the fake service holds after submit. */
async function fakeFacilityOf() {
  const { getFacilityService } = await import("@/services/facility");
  return getFacilityService().getFacility();
}

describe("FacilityDetailsForm", () => {
  beforeEach(() => {
    window.localStorage.clear();
    useOnboardingStore.getState().reset();
    photoMock.addAll.mockClear();
    photoMock.upload.mockClear();
  });

  it("keeps Continue disabled until every required field is valid", async () => {
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    const submit = await screen.findByRole("button", { name: /Continue/ });
    expect(submit).toBeDisabled();
  });

  it("reports an empty facility name on blur", async () => {
    const user = userEvent.setup({ delay: null });
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    await user.click(await screen.findByLabelText("Facility Name"));
    await user.tab();

    expect(await screen.findByText("Facility name must be at least 2 characters")).toBeInTheDocument();
  });

  it("requires a custom type when Other is selected", async () => {
    const user = userEvent.setup({ delay: null });
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    await user.click(await screen.findByRole("combobox", { name: /facility type/i }));
    await user.click(await screen.findByRole("option", { name: "Other" }));

    expect(await screen.findByLabelText("Specify Facility Type")).toBeInTheDocument();
  });

  it("saves the facility and navigates to Sports Setup on submit", async () => {
    const user = userEvent.setup({ delay: null });
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    await fillValidForm(user);
    await addPhoto(user);
    await user.click(screen.getByRole("switch", { name: "Free Parking" }));
    const submit = await screen.findByRole("button", { name: /Continue/ });
    await waitFor(() => expect(submit).toBeEnabled());
    await user.click(submit);

    await waitFor(() => expect(routerMock.push).toHaveBeenCalledWith("/onboarding/sports"));
    expect(useOnboardingStore.getState().facilityDetailsCompleted).toBe(true);
    // the photo went up for the admin to check
    expect(photoMock.addAll).toHaveBeenCalledTimes(1);
    const saved = await fakeFacilityOf();
    expect(saved?.locationUrl).toBe(MAPS_LINK);
    expect(saved?.venueType).toBe("INDOOR");
    expect(saved?.amenities).toMatchObject({ parking: true, cafeteria: false });
  });

  it("will not continue without a photo, even when everything else is filled in", async () => {
    const user = userEvent.setup({ delay: null });
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    await fillValidForm(user);
    const submit = await screen.findByRole("button", { name: /Continue/ });
    await waitFor(() => expect(submit).toBeDisabled());
    await addPhoto(user);
    await waitFor(() => expect(submit).toBeEnabled());
  });

  it("asks for a real Google Maps link, and for indoor or outdoor", async () => {
    const user = userEvent.setup({ delay: null });
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    const link = await screen.findByLabelText("Google Map Location Link");
    await user.click(link);
    await user.paste("https://example.com/not-a-map");
    await user.tab();
    expect(await screen.findByText(/Paste a Google Maps link/)).toBeInTheDocument();
    await user.clear(link);
    await user.tab();
    expect(await screen.findByText("Google Maps location link is required")).toBeInTheDocument();
    expect(screen.getByRole("radio", { name: /Indoor/ })).toBeInTheDocument();
    expect(screen.getByRole("radio", { name: /Outdoor/ })).toBeInTheDocument();
  });

  it("offers the five amenities as toggles, and no longer asks for a description", async () => {
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    for (const name of ["Free Parking", "Changing Rooms", "Toilets / Rest Room", "Cafeteria", "Equipment Rental"]) {
      const toggle = await screen.findByRole("switch", { name });
      expect(toggle).toHaveAttribute("aria-checked", "false");
    }
    expect(screen.queryByLabelText("About Your Facility")).not.toBeInTheDocument();
    expect(screen.queryByText(/About Your Facility/i)).not.toBeInTheDocument();
  });

  it("restores a previously entered draft after remounting", async () => {
    const user = userEvent.setup({ delay: null });
    installAuth();
    const { unmount } = renderWithProviders(<FacilityDetailsForm />);

    await user.type(await screen.findByLabelText("Facility Name"), VALID.facilityName);
    await waitFor(() => expect(useOnboardingStore.getState().draft.facilityName).toBe(VALID.facilityName));
    unmount();

    renderWithProviders(<FacilityDetailsForm />);
    expect(await screen.findByDisplayValue(VALID.facilityName)).toBeInTheDocument();
  });
});
