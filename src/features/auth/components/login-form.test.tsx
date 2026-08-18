import { describe, expect, it } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { LoginForm } from "@/features/auth/components/login-form";
import { failing, installFakeAuthService, renderWithProviders } from "@/test/harness";
import { routerMock, setSearchParams } from "@/test/router-mock";

async function signIn(user: ReturnType<typeof userEvent.setup>, password = "TurfCourt2026") {
  await user.type(screen.getByLabelText("Email address"), "owner@yourturf.com");
  await user.type(screen.getByLabelText("Password"), password);
  await user.click(screen.getByRole("button", { name: "Sign In" }));
}

describe("LoginForm", () => {
  it("requires an email address", async () => {
    const user = userEvent.setup();
    installFakeAuthService();
    renderWithProviders(<LoginForm />);

    await user.click(screen.getByLabelText("Email address"));
    await user.tab();

    expect(await screen.findByText("Email address is required")).toBeInTheDocument();
  });

  it("signs in and opens the dashboard", async () => {
    const user = userEvent.setup();
    const service = installFakeAuthService();
    renderWithProviders(<LoginForm />);

    await signIn(user);

    await waitFor(() =>
      expect(service.login).toHaveBeenCalledWith({
        email: "owner@yourturf.com",
        password: "TurfCourt2026",
      }),
    );
    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/dashboard"));
  });

  it("reports invalid credentials without saying which field was wrong", async () => {
    const user = userEvent.setup();
    installFakeAuthService({
      login: failing("invalid_credentials", "Invalid email or password."),
    });
    renderWithProviders(<LoginForm />);

    await signIn(user, "WrongPassword1");

    expect(await screen.findByText(/Invalid email or password\./)).toBeInTheDocument();
    expect(routerMock.replace).not.toHaveBeenCalled();
  });

  it("blocks an unverified account and offers to resend the link", async () => {
    const user = userEvent.setup();
    installFakeAuthService({
      login: failing("email_not_verified", "Please verify your email before signing in."),
    });
    renderWithProviders(<LoginForm />);

    await signIn(user);

    expect(
      await screen.findByText(/Please verify your email before signing in\./),
    ).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Resend the verification email" })).toHaveAttribute(
      "href",
      "/verify-email?email=owner%40yourturf.com",
    );
  });

  it("confirms a completed verification when arriving from the email link", () => {
    setSearchParams({ verified: "1" });
    installFakeAuthService();
    renderWithProviders(<LoginForm />);

    expect(screen.getByText(/Email verified\./)).toBeInTheDocument();
  });
});