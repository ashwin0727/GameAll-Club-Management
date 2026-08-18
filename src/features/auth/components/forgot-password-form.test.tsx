import { describe, expect, it } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ForgotPasswordForm } from "@/features/auth/components/forgot-password-form";
import { failing, installFakeAuthService, renderWithProviders } from "@/test/harness";

describe("ForgotPasswordForm", () => {
  it("requires an email address", async () => {
    const user = userEvent.setup();
    const service = installFakeAuthService();
    renderWithProviders(<ForgotPasswordForm />);

    await user.click(screen.getByRole("button", { name: "Send Reset Link" }));

    expect(await screen.findByText("Email address is required")).toBeInTheDocument();
    expect(service.resetPassword).not.toHaveBeenCalled();
  });

  it("rejects a malformed email address", async () => {
    const user = userEvent.setup();
    const service = installFakeAuthService();
    renderWithProviders(<ForgotPasswordForm />);

    await user.type(screen.getByLabelText("Registered email address"), "owner.com");
    await user.click(screen.getByRole("button", { name: "Send Reset Link" }));

    expect(
      await screen.findByText("Enter a valid email address, like owner@example.com"),
    ).toBeInTheDocument();
    expect(service.resetPassword).not.toHaveBeenCalled();
  });

  it("confirms without revealing whether the account exists", async () => {
    const user = userEvent.setup();
    const service = installFakeAuthService();
    renderWithProviders(<ForgotPasswordForm />);

    await user.type(screen.getByLabelText("Registered email address"), "owner@yourturf.com");
    await user.click(screen.getByRole("button", { name: "Send Reset Link" }));

    await waitFor(() =>
      expect(service.resetPassword).toHaveBeenCalledWith({ email: "owner@yourturf.com" }),
    );
    expect(await screen.findByText("Check your inbox")).toBeInTheDocument();
    expect(screen.getByText(/If an account exists for/)).toBeInTheDocument();
  });

  it("reports a delivery failure instead of a false confirmation", async () => {
    const user = userEvent.setup();
    installFakeAuthService({
      resetPassword: failing("network", "Network error. Check your connection and try again."),
    });
    renderWithProviders(<ForgotPasswordForm />);

    await user.type(screen.getByLabelText("Registered email address"), "owner@yourturf.com");
    await user.click(screen.getByRole("button", { name: "Send Reset Link" }));

    expect(
      await screen.findByText("Network error. Check your connection and try again."),
    ).toBeInTheDocument();
    expect(screen.queryByText("Check your inbox")).not.toBeInTheDocument();
  });
});