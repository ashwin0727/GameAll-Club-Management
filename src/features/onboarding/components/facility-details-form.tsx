"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { SubmitButton } from "@/features/auth/components/submit-button";
import { FormMessage } from "@/features/auth/components/form-message";
import { useCurrentUser } from "@/features/auth/hooks/use-auth";
import { FacilityInformationSection } from "@/features/onboarding/components/facility-information-section";
import { FacilityLocationSection } from "@/features/onboarding/components/facility-location-section";
import { FacilityBrandingSection } from "@/features/onboarding/components/facility-branding-section";
import { SaveStatus } from "@/features/onboarding/components/save-status";
import { DEFAULT_FACILITY_TYPE } from "@/features/onboarding/constants";
import { MockFacilityService } from "@/features/onboarding/services/mock-facility-service";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import type { FacilityType } from "@/features/onboarding/types";
import { facilityDetailsSchema, type FacilityDetailsInput } from "@/features/onboarding/validation";

export function FacilityDetailsForm() {
  const router = useRouter();
  const { data: user } = useCurrentUser();
  const draft = useOnboardingStore((s) => s.draft);
  const setDraft = useOnboardingStore((s) => s.setDraft);
  const completeFacilityDetails = useOnboardingStore((s) => s.completeFacilityDetails);
  const [logo, setLogo] = useState<File | string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);

  const {
    register,
    handleSubmit,
    watch,
    setValue,
    formState: { errors, isSubmitting, isValid },
  } = useForm<FacilityDetailsInput>({
    resolver: zodResolver(facilityDetailsSchema),
    mode: "onTouched",
    defaultValues: {
      facilityName: draft.facilityName ?? "",
      facilityType: draft.facilityType ?? DEFAULT_FACILITY_TYPE,
      customFacilityType: draft.customFacilityType ?? "",
      businessPhone: draft.businessPhone ?? "",
      addressLine: draft.addressLine ?? "",
      area: draft.area ?? "",
      city: draft.city ?? "",
      state: draft.state ?? "",
      pinCode: draft.pinCode ?? "",
      description: draft.description ?? "",
    },
  });

  const values = watch();
  const facilityType = watch("facilityType");
  const state = watch("state");
  const description = watch("description") ?? "";

  // Mirrors every field change into the store as it happens. A plain
  // `onChange={() => setDraft(values)}` on the <form> element is racy: the
  // bubbled change event and RHF's own field update both run inside the same
  // synchronous dispatch, so a `values` closure from the last render is
  // always one keystroke stale (the final character typed into a field gets
  // silently dropped from the draft). Subscribing via `watch` instead gets
  // the live, up-to-date value on every change.
  useEffect(() => {
    const subscription = watch((value) => {
      setDraft(value as Partial<FacilityDetailsInput>);
    });
    return () => subscription.unsubscribe();
  }, [watch, setDraft]);

  const onSubmit = async (input: FacilityDetailsInput) => {
    if (!user) {
      setSaveError("We couldn't save your facility details. Please try again.");
      return;
    }
    setSaveError(null);

    try {
      const facility = await MockFacilityService.saveFacility({
        ownerId: user.id,
        name: input.facilityName.trim(),
        // Safe: zod validated facilityType against the same literal values as FacilityType.
        type: input.facilityType as FacilityType,
        customType: input.facilityType === "OTHER" ? input.customFacilityType : undefined,
        businessEmail: user.email,
        businessPhone: input.businessPhone.trim(),
        address: {
          line1: input.addressLine.trim(),
          area: input.area.trim(),
          city: input.city.trim(),
          state: input.state,
          country: "India",
          pinCode: input.pinCode,
        },
        logoUrl: typeof logo === "string" ? logo : undefined,
        description: input.description?.trim() || undefined,
      });

      completeFacilityDetails(facility);
      router.push("/onboarding/sports");
    } catch {
      setSaveError("We couldn't save your facility details. Please try again.");
    }
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="space-y-8" noValidate>
      {saveError && <FormMessage>{saveError}</FormMessage>}

      <section className="space-y-4 rounded-xl border border-border bg-card p-5 sm:p-6">
        <h2 className="text-sm font-semibold">Facility Information</h2>
        <FacilityInformationSection
          register={register}
          errors={errors}
          facilityType={facilityType}
          onFacilityTypeChange={(value) => {
            setValue("facilityType", value as FacilityDetailsInput["facilityType"], {
              shouldValidate: true,
            });
          }}
          businessEmail={user?.email ?? ""}
        />
      </section>

      <section className="space-y-4 rounded-xl border border-border bg-card p-5 sm:p-6">
        <h2 className="text-sm font-semibold">Facility Location</h2>
        <FacilityLocationSection
          register={register}
          errors={errors}
          state={state}
          onStateChange={(value) => {
            setValue("state", value, { shouldValidate: true });
          }}
        />
      </section>

      <section className="space-y-4 rounded-xl border border-border bg-card p-5 sm:p-6">
        <h2 className="text-sm font-semibold">Facility Branding</h2>
        <p className="text-xs text-muted-foreground">Optional — you can add these later.</p>
        <FacilityBrandingSection
          description={description}
          onDescriptionChange={(value) => {
            setValue("description", value);
          }}
          logo={logo}
          onLogoChange={setLogo}
        />
      </section>

      <div className="flex items-center justify-between gap-4">
        <SaveStatus dirtyToken={JSON.stringify(values)} />
        <SubmitButton
          pending={isSubmitting}
          disabled={!isValid}
          pendingLabel="Saving…"
          className="w-auto sm:min-w-[10rem]"
        >
          Continue →
        </SubmitButton>
      </div>
    </form>
  );
}
