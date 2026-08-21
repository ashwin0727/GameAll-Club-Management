import { LoadingSpinner } from "@/components/shared/loading-state";

/**
 * Renders inside onboarding/layout.tsx's shell (Back button + progress bar
 * stay visible) while a step's page is loading — covers /facility, /sports,
 * /courts, and any future onboarding step automatically.
 */
export default function OnboardingLoading() {
  return <LoadingSpinner className="min-h-[40vh]" />;
}