import { describe, expect, it, vi } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { SignupForm } from "@/features/auth/components/signup-form";
import { failing, installFakeAuthService, renderWithProviders } from "@/test/harness";
import { routerMock } from "@/test/router-mock";

const VALID = {
  name: "Ravi Kumar",
  email: "owner@yourturf.com",
  password: "TurfCourt2026",
};

async function fillValidForm(user: ReturnType<typeof userEvent.setup>) {
  await user.type(screen.getByLabelText("Full name"), VALID.name);
  await user.type(screen.getByLabelText("Business email"), VALID.email);
  await user.type(screen.getByLabelText("Password"), VALID.password);
  await user.type(screen.getByLabelText("Confirm password"), VALID.password);
}

describe("SignupForm", () => {
  it("keeps Create Account disabled until every field is valid", async () => {
    const user = userEvent.setup();
    installFakeAuthService();
    renderWithProviders(<SignupForm />);

    const submit = screen.getByRole("button", { name: "Create Account" });
    expect(submit).toBeDisabled();

    await fillValidForm(user);
    await waitFor(() => expect(submit).toBeEnabled());
  });

  it("reports an empty name on blur", async () => {
    const user = userEvent.setup();
    installFakeAuthService();
    renderWithProviders(<SignupForm />);

    await user.click(screen.getByLabelText("Full name"));
    await user.tab();

    expect(await screen.findByText("Enter your full name")).toBeInTheDocument();
  });

  it("reports an invalid email before submission", async () => {
    const user = userEvent.setup();
    installFakeAuthService();
    renderWithProviders(<SignupForm />);

    await user.type(screen.getByLabelText("Business email"), "owner@");
    await user.tab();

    expect(
      await screen.findByText("Enter a valid email address, like owner@example.com"),
    ).toBeInTheDocument();
  });

  it("reports a password under the minimum length", async () => {
    const user = userEvent.setup();
    installFakeAuthService();
    renderWithProviders(<SignupForm />);

    await user.type(screen.getByLabelText("Password"), "turf12");
    await user.tab();

    expect(
      await screen.findByText("Password must be at least 8 characters"),
    ).toBeInTheDocument();
  });

  it("reports a mismatched confirmation", async () => {
    const user = userEvent.setup();
    installFakeAuthService();
    renderWithProviders(<SignupForm />);

    await user.type(screen.getByLabelText("Password"), VALID.password);
    await user.type(screen.getByLabelText("Confirm password"), "TurfCourt2027");
    await user.tab();

    expect(await screen.findByText("Passwords do not match")).toBeInTheDocument();
  });

  it("grades password strength as the user types", async () => {
    const user = userEvent.setup();
    installFakeAuthService();
    renderWithProviders(<SignupForm />);

    await user.type(screen.getByLabelText("Password"), "turf12");
    expect(await screen.findByText("Weak")).toBeInTheDocument();

    await user.clear(screen.getByLabelText("Password"));
    await user.type(screen.getByLabelText("Password"), "TurfCourt2026!");
    expect(await screen.findByText("Strong")).toBeInTheDocument();
  });

  it("registers the account and moves to email verification", async () => {
    const user = userEvent.setup();
    const service = installFakeAuthService();
    renderWithProviders(<SignupForm />);

    await fillValidForm(user);
    await user.click(await screen.findByRole("button", { name: "Create Account" }));

    await waitFor(() =>
      expect(service.register).toHaveBeenCalledWith(
        expect.objectContaining({ name: VALID.name, email: VALID.email, password: VALID.password }),
      ),
    );
    await waitFor(() =>
      expect(routerMock.push).toHaveBeenCalledWith(
        `/verify-email?email=${encodeURIComponent(VALID.email)}`,
      ),
    );
  });

  it("sends a brand-new account straight to facility setup when the session is already active", async () => {
    const user = userEvent.setup();
    const service = installFakeAuthService({
      register: vi.fn(async ({ email }) => ({ email, sessionActive: true })),
    });
    renderWithProviders(<SignupForm />);

    await fillValidForm(user);
    await user.click(await screen.findByRole("button", { name: "Create Account" }));

    await waitFor(() => expect(service.register).toHaveBeenCalled());
    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/onboarding/facility"));
  });

  it("surfaces an already-registered email inline", async () => {
    const user = userEvent.setup();
    installFakeAuthService({
      register: failing("email_taken", "An account already exists for this email address."),
    });
    renderWithProviders(<SignupForm />);

    await fillValidForm(user);
    await user.click(await screen.findByRole("button", { name: "Create Account" }));

    expect(
      await screen.findByText("An account already exists for this email address."),
    ).toBeInTheDocument();
    expect(routerMock.push).not.toHaveBeenCalled();
  });
});