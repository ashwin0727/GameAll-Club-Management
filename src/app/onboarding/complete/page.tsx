import type { Metadata } from "next";
import { SetupSummaryPage } from "@/features/onboarding-summary/components/setup-summary-page";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Setup Complete — ${PRODUCT_NAME}`,
};

export default function OnboardingCompletePage() {
  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">Your facility is ready</h1>
        <p className="mt-2 text-sm text-muted-foreground sm:text-base">
          Review your setup before you start managing your facility.
        </p>
      </div>

      <SetupSummaryPage />
    </div>
  );
}