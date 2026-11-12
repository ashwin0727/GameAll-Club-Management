// src/app/onboarding/operating-hours/page.tsx
import type { Metadata } from "next";
import { OnboardingShell } from "@/features/onboarding/components/onboarding-shell";
import { SetupStepper } from "@/features/onboarding/components/setup-stepper";
import { OperatingHoursSetupForm } from "@/features/operating-hours/setup/operating-hours-setup-form";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Operating Hours — ${PRODUCT_NAME}`,
};

export default function OperatingHoursPage() {
  return (
    <OnboardingShell firstStepLabel="Facility Information" activeStep={2}>
      <main className="w-full min-w-0 flex-1 px-3 py-6 sm:px-4 lg:px-5 lg:py-6">
        <SetupStepper current={3} />
        <h1 className="mt-6 text-3xl font-bold tracking-tight lg:mt-0 lg:text-4xl">Operating Hours</h1>
        <p className="mb-6 mt-2 text-base font-normal text-[#666666]">Set your facility&apos;s working days, opening &amp; closing time, and special closures.</p>
        <OperatingHoursSetupForm />
      </main>
    </OnboardingShell>
  );
}
