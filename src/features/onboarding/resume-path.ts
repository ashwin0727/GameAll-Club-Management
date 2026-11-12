import type { Facility } from "@/features/onboarding/types";

/** Where "Get Started" should open for someone who already began setup: the step they stopped at. */
export function onboardingResumePath(step: Facility["onboardingStep"] | undefined): string {
  switch (step) {
    case "SPORTS":
    case "COURTS":
      return "/onboarding/sports";
    case "OPERATING_HOURS":
      return "/onboarding/operating-hours";
    case "PRICING":
      return "/onboarding/pricing";
    case "PAYMENTS":
      return "/onboarding/payments";
    case "COMPLETED":
      return "/dashboard";
    default:
      return "/onboarding/facility";
  }
}
