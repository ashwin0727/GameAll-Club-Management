import type { EntryRoute } from "@/features/auth/types";

/**
 * The splash screen's routing decision, kept separate from the component so the
 * rule is testable on its own:
 *
 *   signed in, mobile not yet verified → mobile verification
 *   signed in, onboarding incomplete → facility onboarding
 *   signed in, onboarding complete   → dashboard
 *   signed out, returning            → login
 *   signed out, first run            → welcome
 */
export function resolveEntryRoute({
  signedIn,
  deviceOnboarded,
  onboardingCompleted,
  mobileVerificationPending = false,
}: {
  signedIn: boolean;
  deviceOnboarded: boolean;
  onboardingCompleted: boolean;
  mobileVerificationPending?: boolean;
}): EntryRoute {
  if (signedIn && mobileVerificationPending) return "/verify-mobile";
  if (signedIn) return onboardingCompleted ? "/dashboard" : "/onboarding/facility";
  return deviceOnboarded ? "/login" : "/welcome";
}