import { describe, expect, it, vi } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { LogoutConfirm } from "@/features/auth/components/logout-confirm";
import { installFakeAuthService, renderWithProviders } from "@/test/harness";

describe("LogoutConfirm", () => {
  it("asks first: shows the question and logs nobody out until Log Out is pressed", async () => {
    const logout = vi.fn(async () => undefined);
    installFakeAuthService({ logout });
    renderWithProviders(<LogoutConfirm open onCancel={() => undefined} />);

    expect(screen.getByText("Log Out?")).toBeInTheDocument();
    expect(screen.getByText("Are you sure you want to log out of your GameAll account?")).toBeInTheDocument();
    expect(logout).not.toHaveBeenCalled();

    await userEvent.setup().click(screen.getByRole("button", { name: /Log Out/ }));
    await waitFor(() => expect(logout).toHaveBeenCalledTimes(1));
  });

  it("Cancel and the close button only dismiss it", async () => {
    const logout = vi.fn(async () => undefined);
    const onCancel = vi.fn();
    installFakeAuthService({ logout });
    renderWithProviders(<LogoutConfirm open onCancel={onCancel} />);
    const user = userEvent.setup();

    await user.click(screen.getByRole("button", { name: "Cancel" }));
    await user.click(screen.getAllByRole("button", { name: "Close" })[0]!); // the dialog's own built-in X is hidden by CSS
    expect(onCancel).toHaveBeenCalledTimes(2);
    expect(logout).not.toHaveBeenCalled();
  });

  it("shows nothing while closed", () => {
    installFakeAuthService({});
    renderWithProviders(<LogoutConfirm open={false} onCancel={() => undefined} />);
    expect(screen.queryByText("Log Out?")).not.toBeInTheDocument();
  });
});
