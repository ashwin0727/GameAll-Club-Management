// src/app/onboarding/facility/page.tsx
import type { Metadata } from "next";
import { FacilityDetailsForm } from "@/features/onboarding/components/facility-details-form";
import { OnboardingShell } from "@/features/onboarding/components/onboarding-shell";
import { SetupStepper } from "@/features/onboarding/components/setup-stepper";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Facility Information — ${PRODUCT_NAME}`,
};

export default function FacilityDetailsPage() {
  return (
    <OnboardingShell firstStepLabel="Facility Information">
      <main className="w-full min-w-0 flex-1 px-4 py-6 sm:px-6 lg:px-8 lg:py-6">
        <SetupStepper current={1} />
        <h1 className="mt-6 text-3xl font-bold tracking-tight lg:mt-0 lg:text-4xl">Facility Information</h1>
        <p className="mb-6 mt-2 text-base font-normal text-[#666666]">Add the key details about your venue, amenities and owner contact.</p>
        <FacilityDetailsForm />
      </main>
    </OnboardingShell>
  );
}
