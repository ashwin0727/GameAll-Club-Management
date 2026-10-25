import type { Metadata } from "next";
import { OnboardingPlanStep } from "@/features/plans/components/onboarding-plan-step";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Choose Your Plan — ${PRODUCT_NAME}`,
};

export default function OnboardingPlanPage() {
  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">Choose Your Plan</h1>
        <p className="mt-2 text-sm text-muted-foreground sm:text-base">
          Try it free for 90 days. You authorise Auto Pay now and are charged only when the trial ends.
        </p>
      </div>

      <OnboardingPlanStep />
    </div>
  );
}
