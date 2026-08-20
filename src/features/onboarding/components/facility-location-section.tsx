"use client";

import type { FieldErrors, UseFormRegister } from "react-hook-form";
import { SelectField } from "@/components/form/select-field";
import { TextField } from "@/features/auth/components/text-field";
import { INDIAN_STATES } from "@/features/onboarding/constants";
import type { FacilityDetailsInput } from "@/features/onboarding/validation";

const STATE_OPTIONS = INDIAN_STATES.map((state) => ({ value: state, label: state }));

export interface FacilityLocationSectionProps {
  register: UseFormRegister<FacilityDetailsInput>;
  errors: FieldErrors<FacilityDetailsInput>;
  state: string;
  onStateChange: (value: string) => void;
}

export function FacilityLocationSection({
  register,
  errors,
  state,
  onStateChange,
}: FacilityLocationSectionProps) {
  return (
    <div className="space-y-5">
      <TextField
        id="address-line"
        label="Address"
        placeholder="Enter your facility address"
        maxLength={250}
        error={errors.addressLine?.message}
        {...register("addressLine")}
      />

      <div className="grid gap-5 sm:grid-cols-2">
        <TextField
          id="area"
          label="Area / Locality"
          placeholder="e.g. Ambattur"
          maxLength={100}
          error={errors.area?.message}
          {...register("area")}
        />
        <TextField
          id="city"
          label="City"
          placeholder="e.g. Chennai"
          error={errors.city?.message}
          {...register("city")}
        />
      </div>

      <div className="grid gap-5 sm:grid-cols-2">
        <SelectField
          id="state"
          label="State"
          options={STATE_OPTIONS}
          value={state}
          onValueChange={onStateChange}
          placeholder="Select a state"
          error={errors.state?.message as string | undefined}
        />
        <TextField
          id="pin-code"
          label="PIN Code"
          inputMode="numeric"
          placeholder="600053"
          maxLength={6}
          error={errors.pinCode?.message}
          {...register("pinCode")}
        />
      </div>
    </div>
  );
}
