// src/app/onboarding/sports/page.tsx
import type { Metadata } from "next";
import { OnboardingShell } from "@/features/onboarding/components/onboarding-shell";
import { SetupStepper } from "@/features/onboarding/components/setup-stepper";
import { SportsCourtsForm } from "@/features/sports-courts/components/sports-courts-form";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Sports & Courts — ${PRODUCT_NAME}`,
};

export default function SportsAndCourtsPage() {
  return (
    <OnboardingShell firstStepLabel="Facility Information" activeStep={1}>
      <main className="w-full min-w-0 flex-1 px-3 py-6 sm:px-4 lg:px-5 lg:py-6">
        <SetupStepper current={2} />
        <h1 className="mt-6 text-3xl font-bold tracking-tight lg:mt-0 lg:text-4xl">Sports &amp; Courts</h1>
        <p className="mb-6 mt-2 text-base font-normal text-[#666666]">Select the sports available at your facility and add court details easily.</p>
        <SportsCourtsForm />
      </main>
    </OnboardingShell>
  );
}
