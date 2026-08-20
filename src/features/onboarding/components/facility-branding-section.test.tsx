import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { FacilityBrandingSection } from "@/features/onboarding/components/facility-branding-section";

describe("FacilityBrandingSection", () => {
  it("shows the character counter starting at 0/500", () => {
    render(
      <FacilityBrandingSection description="" onDescriptionChange={vi.fn()} logo={null} onLogoChange={vi.fn()} />,
    );
    expect(screen.getByText("0 / 500")).toBeInTheDocument();
  });

  it("updates the counter as the user types", async () => {
    const user = userEvent.setup();
    const onDescriptionChange = vi.fn();
    render(
      <FacilityBrandingSection
        description=""
        onDescriptionChange={onDescriptionChange}
        logo={null}
        onLogoChange={vi.fn()}
      />,
    );

    await user.type(screen.getByLabelText("About Your Facility"), "Great courts");
    expect(onDescriptionChange).toHaveBeenCalled();
  });

  it("renders the optional logo upload", () => {
    render(
      <FacilityBrandingSection description="" onDescriptionChange={vi.fn()} logo={null} onLogoChange={vi.fn()} />,
    );
    expect(screen.getByText("+ Upload Logo")).toBeInTheDocument();
    expect(screen.getByText(/Optional/)).toBeInTheDocument();
  });
});
