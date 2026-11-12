// src/app/onboarding/pricing/page.tsx
import type { Metadata } from "next";
import { OnboardingShell } from "@/features/onboarding/components/onboarding-shell";
import { SetupStepper } from "@/features/onboarding/components/setup-stepper";
import { PricingSetupForm } from "@/features/pricing/setup/pricing-setup-form";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Pricing — ${PRODUCT_NAME}`,
};

export default function PricingPage() {
  return (
    <OnboardingShell firstStepLabel="Facility Information" activeStep={3}>
      <main className="w-full min-w-0 flex-1 px-3 py-6 sm:px-4 lg:px-5 lg:py-6">
        <SetupStepper current={4} />
        <h1 className="mt-6 text-3xl font-bold tracking-tight lg:mt-0 lg:text-4xl">Pricing</h1>
        <p className="mb-6 mt-2 text-base font-normal text-[#666666]">Set the booking rates for your courts. You can add different pricing for each sport, court, or time slot.</p>
        <PricingSetupForm />
      </main>
    </OnboardingShell>
  );
}
