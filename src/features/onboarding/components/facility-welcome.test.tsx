import { describe, expect, it, vi } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { FacilityWelcome } from "@/features/onboarding/components/facility-welcome";
import { renderWithProviders } from "@/test/harness";
import { routerMock } from "@/test/router-mock";

vi.mock("next/font/google", () => ({ Inter: () => ({ className: "font-inter" }) }));

describe("FacilityWelcome", () => {
  it("shows the intro, the five setup steps and the checklist", () => {
    renderWithProviders(<FacilityWelcome />);
    expect(screen.getByRole("heading", { name: "Set Up Your Facility" })).toBeInTheDocument();
    expect(screen.getByAltText("GameAll")).toBeInTheDocument();
    for (const label of ["Basic Details", "Sports & Courts", "Operating Hours", "Pricing", "Payout"]) {
      expect(screen.getByText(label)).toBeInTheDocument();
    }
    expect(screen.getByText("Choose a plan and go live")).toBeInTheDocument();
  });

  it("Get Started continues to Facility Details", async () => {
    renderWithProviders(<FacilityWelcome />);
    await userEvent.setup().click(screen.getByRole("button", { name: /Get Started/ }));
    await waitFor(() => expect(routerMock.push).toHaveBeenCalledWith("/onboarding/facility"));
  });
});
