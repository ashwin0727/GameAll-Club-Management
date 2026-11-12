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

// These tests fill the whole form field by field; under a full-suite run they can approach the default 30s.
vi.setConfig({ testTimeout: 90_000 });

const MAPS_LINK = "https://maps.app.goo.gl/AbCdEf123";
const photoFile = (name = "court.jpg") => new File([name], name, { type: "image/jpeg" });

const VALID = {
  facilityName: "GameAll Sports Arena",
  businessPhone: "9876543210",
  addressLine: "123 Anna Salai",
  area: "Ambattur",
  city: "Chennai",
  pinCode: "600053",
  contactName: "Uma Shankar M",
};

const FAKE_USER_VERIFIED = { id: "user-1", name: "Ravi Kumar", email: "owner@yourturf.com", emailVerified: true, onboardingCompleted: false, verifiedMobile: "9876501234" };

const FAKE_USER = {
  id: "user-1",
  name: "Ravi Kumar",
  email: "owner@yourturf.com",
  emailVerified: true,
  onboardingCompleted: false,
};

/** Labels carry a "*" / "(Optional)" suffix, so match on how they start. */
const label = (text: string) => new RegExp(`^${text.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&")}`);

/**
 * FacilityDetailsForm reads the signed-in user via useCurrentUser(), which calls getCurrentUser() — the harness default
 * resolves to null, so every test here must override it or the submit handler's `if (!user) return;` guard would no-op.
 */
function installAuth() {
  const auth = installFakeAuthService({ getCurrentUser: vi.fn(async () => FAKE_USER) });
  const facilityService = installFakeFacilityService();
  facilityService.setCurrentUserId(FAKE_USER.id);
  return auth;
}

function installAuthVerified() {
  const auth = installFakeAuthService({ getCurrentUser: vi.fn(async () => FAKE_USER_VERIFIED) });
  const facilityService = installFakeFacilityService();
  facilityService.setCurrentUserId(FAKE_USER_VERIFIED.id);
  return auth;
}

/** Fills every required field. Values are pasted rather than typed key by key: one event per field keeps the test fast. */
async function fillValidForm(user: ReturnType<typeof userEvent.setup>) {
  async function fill(text: string, value: string) {
    const field = screen.getByLabelText(label(text));
    await user.click(field);
    await user.clear(field);
    await user.paste(value);
  }
  await fill("Facility Name", VALID.facilityName);
  await fill("Contact Number", VALID.businessPhone);
  await fill("Address", VALID.addressLine);
  await fill("Area / Locality", VALID.area);
  await fill("City", VALID.city);
  await user.click(screen.getByRole("combobox", { name: label("State") }));
  await user.click(await screen.findByRole("option", { name: "Tamil Nadu" }));
  await fill("PIN Code", VALID.pinCode);
  await fill("Set Location on Map", MAPS_LINK);
  await fill("Person Name", VALID.contactName);
}

/** The required photo. */
async function addPhoto(user: ReturnType<typeof userEvent.setup>) {
  await user.upload(screen.getByLabelText("Upload facility photos"), photoFile());
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

  it("shows every problem at once when Next is pressed on an empty form, and does not continue", async () => {
    const user = userEvent.setup({ delay: null });
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    await user.click(await screen.findByRole("button", { name: /Next/ }));

    expect(await screen.findByText("Facility name must be at least 2 characters")).toBeInTheDocument();
    expect(screen.getByText("Contact number is required")).toBeInTheDocument();
    expect(screen.getByText("Address is required")).toBeInTheDocument();
    expect(screen.getByText("Area / locality is required")).toBeInTheDocument();
    expect(screen.getByText("City is required")).toBeInTheDocument();
    expect(screen.getByText("State is required")).toBeInTheDocument();
    expect(screen.getByText("PIN code must be exactly 6 digits")).toBeInTheDocument();
    expect(screen.getByText("Google Maps location link is required")).toBeInTheDocument();
    expect(screen.getByText("Enter the contact person's name")).toBeInTheDocument();
    expect(screen.getByText("Add at least one photo of your facility.")).toBeInTheDocument();
    expect(routerMock.push).not.toHaveBeenCalledWith("/onboarding/sports");
  });

  it("uses the mobile verified at signup as the contact number: locked, with a Verified badge, and saved", async () => {
    const user = userEvent.setup({ delay: null });
    installAuthVerified();
    renderWithProviders(<FacilityDetailsForm />);

    expect(await screen.findByLabelText("Verified contact number")).toHaveTextContent(/\+91\s*9876501234/);
    expect(screen.queryByLabelText(label("Contact Number"))).not.toBeInTheDocument();
    expect(screen.getAllByText("Verified").length).toBeGreaterThanOrEqual(2); // email + contact number

    // fill everything except the contact number, which must not be asked for again
    async function fill(text: string, value: string) {
      const field = screen.getByLabelText(label(text));
      await user.click(field);
      await user.clear(field);
      await user.paste(value);
    }
    await fill("Facility Name", VALID.facilityName);
    await fill("Address", VALID.addressLine);
    await fill("Area / Locality", VALID.area);
    await fill("City", VALID.city);
    await user.click(screen.getByRole("combobox", { name: label("State") }));
    await user.click(await screen.findByRole("option", { name: "Tamil Nadu" }));
    await fill("PIN Code", VALID.pinCode);
    await fill("Set Location on Map", MAPS_LINK);
      await fill("Person Name", VALID.contactName);
    await addPhoto(user);
    await user.click(screen.getByRole("button", { name: /Next/ }));

    await waitFor(() => expect(routerMock.push).toHaveBeenCalledWith("/onboarding/sports"));
    expect((await fakeFacilityOf())?.businessPhone).toBe("9876501234");
  });

  it("reports an empty facility name on blur", async () => {
    const user = userEvent.setup({ delay: null });
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    await user.click(await screen.findByLabelText(label("Facility Name")));
    await user.tab();

    expect(await screen.findByText("Facility name must be at least 2 characters")).toBeInTheDocument();
  });

  it("requires a custom type when Other is selected", async () => {
    const user = userEvent.setup({ delay: null });
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    await user.click(await screen.findByRole("combobox", { name: label("Facility Type") }));
    await user.click(await screen.findByRole("option", { name: "Other" }));
    const custom = await screen.findByLabelText(label("Specify Facility Type"));
    await user.click(custom);
    await user.tab();
    expect(await screen.findByText("Specify your facility type")).toBeInTheDocument();
  });

  it("saves the facility, the contact person, policies and amenities, then goes to Sports Setup", async () => {
    const user = userEvent.setup({ delay: null });
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    await fillValidForm(user);
    await user.click(screen.getByRole("radio", { name: "Leased" }));
    await user.click(screen.getByLabelText(label("WhatsApp Number")));
    await user.paste("9123456780");
    await user.click(screen.getByLabelText("Advance Payment Required"));
    await user.click(screen.getByLabelText("Allow Cancellations"));
    await user.click(screen.getByLabelText("Wi-Fi"));
    await user.click(screen.getByLabelText("Car Parking"));
    await addPhoto(user);
    await user.click(screen.getByRole("button", { name: /Next/ }));

    await waitFor(() => expect(routerMock.push).toHaveBeenCalledWith("/onboarding/sports"));
    expect(useOnboardingStore.getState().facilityDetailsCompleted).toBe(true);
    expect(photoMock.addAll).toHaveBeenCalledTimes(1);

    const saved = await fakeFacilityOf();
    expect(saved?.locationUrl).toBe(MAPS_LINK);
    expect(saved?.ownershipType).toBe("LEASED");
    expect(saved?.whatsappNumber).toBe("9123456780");
    expect(saved?.contactPerson).toMatchObject({ name: VALID.contactName, role: "Facility Owner" });
    expect(saved?.policies).toMatchObject({ advancePaymentRequired: true, allowCancellations: false, allowOnlineBooking: true });
    expect(saved?.amenityKeys).toEqual(expect.arrayContaining(["wifi", "car_parking"]));
  });

  it("will not continue without a photo, even when everything else is filled in", async () => {
    const user = userEvent.setup({ delay: null });
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    await fillValidForm(user);
    await user.click(screen.getByRole("button", { name: /Next/ }));
    expect(await screen.findByText("Add at least one photo of your facility.")).toBeInTheDocument();
    expect(routerMock.push).not.toHaveBeenCalledWith("/onboarding/sports");

    await addPhoto(user);
    await waitFor(() => expect(screen.queryByText("Add at least one photo of your facility.")).not.toBeInTheDocument());
  });

  it("allows at most five photos", async () => {
    const user = userEvent.setup({ delay: null });
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    const input = await screen.findByLabelText("Upload facility photos");
    await user.upload(input, [1, 2, 3, 4, 5, 6].map((n) => photoFile(`court-${n}.jpg`)));
    expect(await screen.findByText("You can add up to 5 photos.")).toBeInTheDocument();
    expect(screen.getAllByRole("img", { name: /Facility photo/ })).toHaveLength(5);
  });

  it("rejects a file that is not an image", async () => {
    const user = userEvent.setup({ delay: null, applyAccept: false });
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    await user.upload(await screen.findByLabelText("Upload facility photos"), new File(["x"], "notes.pdf", { type: "application/pdf" }));
    expect(await screen.findByText("Upload a JPG, PNG or WebP image.")).toBeInTheDocument();
  });

  it("does not ask for indoor or outdoor here (that is set per sport on the Sports step)", async () => {
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);
    await screen.findByLabelText(label("Facility Name"));
    expect(screen.queryByText(/Venue Type/)).not.toBeInTheDocument();
    expect(screen.queryByRole("radio", { name: /Indoor/ })).not.toBeInTheDocument();
    expect(screen.queryByRole("radio", { name: /Outdoor/ })).not.toBeInTheDocument();
  });

  it("asks for a real Google Maps link", async () => {
    const user = userEvent.setup({ delay: null });
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    const link = await screen.findByLabelText(label("Set Location on Map"));
    await user.click(link);
    await user.paste("https://example.com/not-a-map");
    await user.tab();
    expect(await screen.findByText(/Paste a Google Maps link/)).toBeInTheDocument();
    await user.clear(link);
    await user.tab();
    expect(await screen.findByText("Google Maps location link is required")).toBeInTheDocument();
  });

  it("validates the phone numbers: 10 digits, starting 6-9, and the alternate differs from the contact number", async () => {
    const user = userEvent.setup({ delay: null });
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    const contact = await screen.findByLabelText(label("Contact Number"));
    await user.click(contact);
    await user.paste("12345");
    await user.tab();
    expect(await screen.findByText("Enter a valid 10-digit mobile number")).toBeInTheDocument();
    await user.clear(contact);
    await user.paste("1234567890");
    await user.tab();
    expect(await screen.findByText("Mobile number must start with 6, 7, 8 or 9")).toBeInTheDocument();
    await user.clear(contact);
    await user.paste("9876543210");

    const whatsapp = screen.getByLabelText(label("WhatsApp Number"));
    await user.click(whatsapp);
    await user.paste("98765");
    await user.tab();
    expect(await screen.findAllByText("Enter a valid 10-digit mobile number")).not.toHaveLength(0);

    const alt = screen.getByLabelText(label("Alternate Number"));
    await user.click(alt);
    await user.paste("9876543210");
    await user.tab();
    expect(await screen.findByText("Use a different number from the contact number")).toBeInTheDocument();
  });

  it("caps the description at 500 characters and shows the count", async () => {
    const user = userEvent.setup({ delay: null });
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    const box = await screen.findByLabelText(label("Facility Description"));
    await user.click(box);
    await user.paste("Floodlit courts");
    expect(screen.getByText("15 / 500")).toBeInTheDocument();
    expect(box).toHaveAttribute("maxlength", "500");
  });

  it("offers the 12 amenities as checkboxes, all unticked to start", async () => {
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    for (const name of [
      "Car Parking",
      "Two-Wheeler Parking",
      "Restroom",
      "Changing Room",
      "Shower",
      "Drinking Water",
      "Seating Area",
      "Cafeteria / Food",
      "Wi-Fi",
      "Lockers",
      "Equipment Rental",
      "First Aid",
    ]) {
      expect(await screen.findByLabelText(name)).not.toBeChecked();
    }
  });

  it("adds a custom amenity, refuses a duplicate or a too-short name, and lets it be removed", async () => {
    const user = userEvent.setup({ delay: null });
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    await user.click(await screen.findByRole("button", { name: /Add Custom Amenity/ }));
    const box = screen.getByLabelText("Custom amenity name");

    await user.type(box, "x{Enter}");
    expect(await screen.findByText("Amenity name must be at least 2 characters")).toBeInTheDocument();

    await user.clear(box);
    await user.type(box, "wi-fi{Enter}");
    expect(await screen.findByText('"wi-fi" is already in the list')).toBeInTheDocument();

    await user.clear(box);
    await user.type(box, "Physio room{Enter}");
    expect(await screen.findByText("Physio room")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Remove Physio room" }));
    expect(screen.queryByText("Physio room")).not.toBeInTheDocument();
  });

  it("starts with the standard policy defaults", async () => {
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    expect(await screen.findByLabelText("Allow Online Booking")).toBeChecked();
    expect(screen.getByLabelText("Allow Walk-in / Offline Booking")).toBeChecked();
    expect(screen.getByLabelText("Advance Payment Required")).not.toBeChecked();
    expect(screen.getByLabelText("Allow Cancellations")).toBeChecked();
    expect(screen.getByLabelText("Require Player Details")).toBeChecked();
  });

  it("Back returns to the welcome page, and Save as Draft stores what was typed", async () => {
    const user = userEvent.setup({ delay: null });
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    await user.click(await screen.findByLabelText(label("Facility Name")));
    await user.paste("Champz Turf");
    await user.click(screen.getByRole("button", { name: /Save as Draft/ }));
    expect(useOnboardingStore.getState().draft.facilityName).toBe("Champz Turf");

    await user.click(screen.getByRole("button", { name: /Back/ }));
    expect(routerMock.push).toHaveBeenCalledWith("/onboarding/welcome");
  });

  it("restores a previously entered draft after remounting", async () => {
    const user = userEvent.setup({ delay: null });
    installAuth();
    const { unmount } = renderWithProviders(<FacilityDetailsForm />);

    await user.type(await screen.findByLabelText(label("Facility Name")), VALID.facilityName);
    await waitFor(() => expect(useOnboardingStore.getState().draft.facilityName).toBe(VALID.facilityName));
    unmount();

    renderWithProviders(<FacilityDetailsForm />);
    expect(await screen.findByDisplayValue(VALID.facilityName)).toBeInTheDocument();
  });
});
