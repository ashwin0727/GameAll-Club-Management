// src/app/onboarding/payments/page.tsx
import type { Metadata } from "next";
import { OnboardingShell } from "@/features/onboarding/components/onboarding-shell";
import { SetupStepper } from "@/features/onboarding/components/setup-stepper";
import { PayoutSetupForm } from "@/features/onboarding/components/payout-setup-form";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Payout — ${PRODUCT_NAME}`,
};

export default function PaymentsPage() {
  return (
    <OnboardingShell firstStepLabel="Facility Information" activeStep={4}>
      <main className="w-full min-w-0 flex-1 px-3 py-6 sm:px-4 lg:px-5 lg:py-6">
        <SetupStepper current={5} />
        <h1 className="mt-6 text-3xl font-bold tracking-tight lg:mt-0 lg:text-4xl">Payout</h1>
        <p className="mb-6 mt-2 text-base font-normal text-[#666666]">Set up how you receive your earnings from bookings, memberships, and coaching at your facility.</p>
        <PayoutSetupForm />
      </main>
    </OnboardingShell>
  );
}
