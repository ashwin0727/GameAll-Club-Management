import { beforeEach, describe, expect, it, vi } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { FacilityDetailsForm } from "@/features/onboarding/components/facility-details-form";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import { installFakeAuthService, renderWithProviders } from "@/test/harness";
import { routerMock } from "@/test/router-mock";

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
  return installFakeAuthService({ getCurrentUser: vi.fn(async () => FAKE_USER) });
}

async function fillValidForm(user: ReturnType<typeof userEvent.setup>) {
  await user.type(screen.getByLabelText("Facility Name"), VALID.facilityName);
  await user.type(screen.getByLabelText("Business Contact Number"), VALID.businessPhone);
  await user.type(screen.getByLabelText("Address"), VALID.addressLine);
  await user.type(screen.getByLabelText("Area / Locality"), VALID.area);
  await user.type(screen.getByLabelText("City"), VALID.city);
  await user.click(screen.getByRole("combobox", { name: /state/i }));
  await user.click(await screen.findByRole("option", { name: "Tamil Nadu" }));
  await user.type(screen.getByLabelText("PIN Code"), VALID.pinCode);
}

describe("FacilityDetailsForm", () => {
  beforeEach(() => {
    window.localStorage.clear();
    useOnboardingStore.getState().reset();
  });

  it("keeps Continue disabled until every required field is valid", async () => {
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    const submit = await screen.findByRole("button", { name: /Continue/ });
    expect(submit).toBeDisabled();
  });

  it("reports an empty facility name on blur", async () => {
    const user = userEvent.setup();
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    await user.click(await screen.findByLabelText("Facility Name"));
    await user.tab();

    expect(await screen.findByText("Facility name must be at least 2 characters")).toBeInTheDocument();
  });

  it("requires a custom type when Other is selected", async () => {
    const user = userEvent.setup();
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    await user.click(await screen.findByRole("combobox", { name: /facility type/i }));
    await user.click(await screen.findByRole("option", { name: "Other" }));

    expect(await screen.findByLabelText("Specify Facility Type")).toBeInTheDocument();
  });

  it("saves the facility and navigates to Sports Setup on submit", async () => {
    const user = userEvent.setup();
    installAuth();
    renderWithProviders(<FacilityDetailsForm />);

    await fillValidForm(user);
    const submit = await screen.findByRole("button", { name: /Continue/ });
    await waitFor(() => expect(submit).toBeEnabled());
    await user.click(submit);

    await waitFor(() => expect(routerMock.push).toHaveBeenCalledWith("/onboarding/sports"));
    expect(useOnboardingStore.getState().facilityDetailsCompleted).toBe(true);
  });

  it("restores a previously entered draft after remounting", async () => {
    const user = userEvent.setup();
    installAuth();
    const { unmount } = renderWithProviders(<FacilityDetailsForm />);

    await user.type(await screen.findByLabelText("Facility Name"), VALID.facilityName);
    await waitFor(() => expect(useOnboardingStore.getState().draft.facilityName).toBe(VALID.facilityName));
    unmount();

    renderWithProviders(<FacilityDetailsForm />);
    expect(await screen.findByDisplayValue(VALID.facilityName)).toBeInTheDocument();
  });
});
