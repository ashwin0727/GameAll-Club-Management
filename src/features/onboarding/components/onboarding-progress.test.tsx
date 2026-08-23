import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { OnboardingProgress } from "@/features/onboarding/components/onboarding-progress";

describe("OnboardingProgress", () => {
  it("lists all six steps", () => {
    render(<OnboardingProgress currentStep={1} />);

    for (const step of ["Facility Details", "Sports", "Courts", "Operating Hours", "Pricing", "Setup"]) {
      expect(screen.getAllByText(step).length).toBeGreaterThan(0);
    }
  });

  it("marks the current step for assistive tech", () => {
    render(<OnboardingProgress currentStep={1} />);
    const matches = screen.getAllByText("Facility Details");
    expect(matches.length).toBeGreaterThan(0);
    for (const el of matches) {
      expect(el).toHaveAttribute("aria-current", "step");
    }
  });

  it("shows the compact mobile summary", () => {
    render(<OnboardingProgress currentStep={1} />);
    expect(screen.getByText("Step 1 of 6")).toBeInTheDocument();
  });

  it("renders no clickable step controls", () => {
    render(<OnboardingProgress currentStep={1} />);
    expect(screen.queryAllByRole("button")).toHaveLength(0);
  });
});
