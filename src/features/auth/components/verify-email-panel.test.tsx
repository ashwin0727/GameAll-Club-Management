import { describe, expect, it } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { VerifyEmailPanel } from "@/features/auth/components/verify-email-panel";
import { failing, installFakeAuthService, renderWithProviders } from "@/test/harness";
import { routerMock, setSearchParams } from "@/test/router-mock";

const EMAIL = "owner@yourturf.com";

describe("VerifyEmailPanel", () => {
  it("shows the address the verification link went to", () => {
    setSearchParams({ email: EMAIL });
    installFakeAuthService();
    renderWithProviders(<VerifyEmailPanel />);

    expect(screen.getByText("We've sent a verification link to")).toBeInTheDocument();
    expect(screen.getByText(EMAIL)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Continue to Sign In" })).toHaveAttribute(
      "href",
      `/login?email=${encodeURIComponent(EMAIL)}`,
    );
  });

  it("sends people to signup when there is no address to verify", () => {
    installFakeAuthService();
    renderWithProviders(<VerifyEmailPanel />);

    expect(screen.getByRole("link", { name: "Create Account" })).toHaveAttribute(
      "href",
      "/signup",
    );
  });

  it("resends the email and then blocks repeat clicks with a countdown", async () => {
    const user = userEvent.setup();
    setSearchParams({ email: EMAIL });
    const service = installFakeAuthService();
    renderWithProviders(<VerifyEmailPanel />);

    await user.click(screen.getByRole("button", { name: /Resend Verification Email/ }));

    await waitFor(() => expect(service.resendVerificationEmail).toHaveBeenCalledWith(EMAIL));
    expect(await screen.findByText("Verification email sent again.")).toBeInTheDocument();

    const resend = screen.getByRole("button", { name: /Resend available in \d+s/ });
    expect(resend).toBeDisabled();
  });

  it("surfaces a rate-limited resend", async () => {
    const user = userEvent.setup();
    setSearchParams({ email: EMAIL });
    installFakeAuthService({
      resendVerificationEmail: failing("rate_limited", "Too many attempts. Please wait a moment and try again."),
    });
    renderWithProviders(<VerifyEmailPanel />);

    await user.click(screen.getByRole("button", { name: /Resend Verification Email/ }));

    expect(
      await screen.findByText("Too many attempts. Please wait a moment and try again."),
    ).toBeInTheDocument();
  });

  it("offers a change-email form showing the current address", async () => {
    const user = userEvent.setup();
    setSearchParams({ email: EMAIL });
    installFakeAuthService();
    renderWithProviders(<VerifyEmailPanel />);

    await user.click(screen.getByRole("button", { name: "Change Email" }));

    expect(screen.getByText("Current email")).toBeInTheDocument();
    expect(screen.getByText(EMAIL)).toBeInTheDocument();
    expect(screen.getByLabelText("New email address")).toBeInTheDocument();
  });

  it("restarts at signup when the password is no longer in memory", async () => {
    const user = userEvent.setup();
    setSearchParams({ email: EMAIL });
    installFakeAuthService();
    renderWithProviders(<VerifyEmailPanel />);

    await user.click(screen.getByRole("button", { name: "Change Email" }));
    await user.type(screen.getByLabelText("New email address"), "new@yourturf.com");
    await user.click(screen.getByRole("button", { name: "Update Email" }));

    // A reload clears the in-memory signup, so the correction cannot be
    // re-submitted silently — the user is sent back to signup with it prefilled.
    await waitFor(() =>
      expect(routerMock.push).toHaveBeenCalledWith(
        `/signup?email=${encodeURIComponent("new@yourturf.com")}`,
      ),
    );
  });

  it("validates the new address before submitting", async () => {
    const user = userEvent.setup();
    setSearchParams({ email: EMAIL });
    const service = installFakeAuthService();
    renderWithProviders(<VerifyEmailPanel />);

    await user.click(screen.getByRole("button", { name: "Change Email" }));
    await user.type(screen.getByLabelText("New email address"), "owner@");
    await user.click(screen.getByRole("button", { name: "Update Email" }));

    expect(
      await screen.findByText("Enter a valid email address, like owner@example.com"),
    ).toBeInTheDocument();
    expect(service.changeEmail).not.toHaveBeenCalled();
    expect(routerMock.push).not.toHaveBeenCalled();
  });
});