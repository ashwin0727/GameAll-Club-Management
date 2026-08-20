import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import { useForm } from "react-hook-form";
import { FacilityLocationSection } from "@/features/onboarding/components/facility-location-section";
import type { FacilityDetailsInput } from "@/features/onboarding/validation";

function Harness() {
  const { register, formState } = useForm<FacilityDetailsInput>({
    defaultValues: { addressLine: "", area: "", city: "", pinCode: "" },
  });
  return (
    <FacilityLocationSection
      register={register}
      errors={formState.errors}
      state=""
      onStateChange={vi.fn()}
    />
  );
}

describe("FacilityLocationSection", () => {
  it("renders every location field", () => {
    render(<Harness />);
    expect(screen.getByLabelText("Address")).toBeInTheDocument();
    expect(screen.getByLabelText("Area / Locality")).toBeInTheDocument();
    expect(screen.getByLabelText("City")).toBeInTheDocument();
    expect(screen.getByText("State")).toBeInTheDocument();
    expect(screen.getByLabelText("PIN Code")).toBeInTheDocument();
  });

  it("uses a numeric keyboard for PIN code", () => {
    render(<Harness />);
    expect(screen.getByLabelText("PIN Code")).toHaveAttribute("inputMode", "numeric");
  });
});
