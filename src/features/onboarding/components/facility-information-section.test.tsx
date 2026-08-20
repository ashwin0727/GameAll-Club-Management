import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import { useForm } from "react-hook-form";
import { FacilityInformationSection } from "@/features/onboarding/components/facility-information-section";
import type { FacilityDetailsInput } from "@/features/onboarding/validation";

function Harness({ facilityType = "MULTI_SPORT" }: { facilityType?: string }) {
  const { register, formState } = useForm<FacilityDetailsInput>({
    defaultValues: { facilityName: "", businessPhone: "" },
  });
  return (
    <FacilityInformationSection
      register={register}
      errors={formState.errors}
      facilityType={facilityType}
      onFacilityTypeChange={vi.fn()}
      businessEmail="owner@yourturf.com"
    />
  );
}

describe("FacilityInformationSection", () => {
  it("renders the core fields", () => {
    render(<Harness />);
    expect(screen.getByLabelText("Facility Name")).toBeInTheDocument();
    expect(screen.getByText("Facility Type")).toBeInTheDocument();
    expect(screen.getByLabelText("Business Contact Number")).toBeInTheDocument();
  });

  it("shows the business email as verified and not editable", () => {
    render(<Harness />);
    expect(screen.getByText("owner@yourturf.com")).toBeInTheDocument();
    expect(screen.getByText("Verified")).toBeInTheDocument();
    expect(screen.queryByLabelText("Business Email")).not.toBeInTheDocument();
  });

  it("shows the custom type field only when facility type is Other", () => {
    const { rerender } = render(<Harness facilityType="MULTI_SPORT" />);
    expect(screen.queryByLabelText("Specify Facility Type")).not.toBeInTheDocument();

    rerender(<Harness facilityType="OTHER" />);
    expect(screen.getByLabelText("Specify Facility Type")).toBeInTheDocument();
  });
});
