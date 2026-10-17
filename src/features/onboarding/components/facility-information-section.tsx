"use client";

import type { FieldErrors, UseFormRegister } from "react-hook-form";
import { BadgeCheck } from "lucide-react";
import { Label } from "@/components/ui/label";
import { SelectField } from "@/components/form/select-field";
import { TextField } from "@/features/auth/components/text-field";
import { sanitizePhoneDigits } from "@/features/coaching/add-coach-validation";
import { FACILITY_TYPE_OPTIONS } from "@/features/onboarding/constants";
import type { FacilityDetailsInput } from "@/features/onboarding/validation";

export interface FacilityInformationSectionProps {
  register: UseFormRegister<FacilityDetailsInput>;
  errors: FieldErrors<FacilityDetailsInput>;
  facilityType: string;
  onFacilityTypeChange: (value: string) => void;
  businessEmail: string;
}

export function FacilityInformationSection({
  register,
  errors,
  facilityType,
  onFacilityTypeChange,
  businessEmail,
}: FacilityInformationSectionProps) {
  return (
    <div className="space-y-5">
      <div className="grid gap-5 sm:grid-cols-2">
        <TextField
          id="facility-name"
          label="Facility Name"
          placeholder="e.g. GameAll Sports Arena"
          hint="Use the name your customers know your facility by."
          error={errors.facilityName?.message}
          {...register("facilityName")}
        />
        <SelectField
          id="facility-type"
          label="Facility Type"
          options={FACILITY_TYPE_OPTIONS}
          value={facilityType}
          onValueChange={onFacilityTypeChange}
          error={errors.facilityType?.message as string | undefined}
        />
      </div>

      {facilityType === "OTHER" && (
        <TextField
          id="custom-facility-type"
          label="Specify Facility Type"
          placeholder="e.g. Basketball Court"
          maxLength={50}
          error={errors.customFacilityType?.message}
          {...register("customFacilityType")}
        />
      )}

      <TextField
        id="business-phone"
        label="Business Contact Number"
        type="tel"
        inputMode="numeric"
        maxLength={10}
        placeholder="98765 43210"
        hint="The facility's own contact number — it doesn't have to match your personal number."
        error={errors.businessPhone?.message}
        {...register("businessPhone", {
          // Digits only, capped at 10 — a pasted "+91 98765-43210" or a stray letter never lands in the field.
          onChange: (e) => {
            e.target.value = sanitizePhoneDigits(e.target.value.replace(/^\s*\+?91(?=\d{10}\s*$)/, ""));
          },
        })}
      />

      <div className="space-y-2">
        <Label>Business Email</Label>
        <div className="flex h-11 items-center justify-between rounded-md border border-input bg-secondary/60 px-3 text-sm">
          <span>{businessEmail}</span>
          <span className="flex items-center gap-1 text-xs font-medium text-success">
            <BadgeCheck className="h-3.5 w-3.5" aria-hidden="true" />
            Verified
          </span>
        </div>
        <p className="text-xs text-muted-foreground">This email is linked to your account.</p>
      </div>
    </div>
  );
}
