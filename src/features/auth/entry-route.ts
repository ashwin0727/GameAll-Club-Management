import type { EntryRoute } from "@/features/auth/types";

/**
 * The splash screen's routing decision, kept separate from the component so the
 * rule is testable on its own:
 *
 *   signed in, onboarding incomplete → facility onboarding
 *   signed in, onboarding complete   → dashboard
 *   signed out, returning            → login
 *   signed out, first run            → welcome
 */
export function resolveEntryRoute({
  signedIn,
  deviceOnboarded,
  onboardingCompleted,
}: {
  signedIn: boolean;
  deviceOnboarded: boolean;
  onboardingCompleted: boolean;
}): EntryRoute {
  if (signedIn) return onboardingCompleted ? "/dashboard" : "/onboarding/facility";
  return deviceOnboarded ? "/login" : "/welcome";
}