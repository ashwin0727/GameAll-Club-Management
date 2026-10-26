import type { EntryRoute } from "@/features/auth/types";

/**
 * The splash screen's routing decision, kept separate from the component so the
 * rule is testable on its own:
 *
 *   signed in as the platform admin → admin back office
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
  isPlatformAdmin = false,
}: {
  signedIn: boolean;
  deviceOnboarded: boolean;
  onboardingCompleted: boolean;
  mobileVerificationPending?: boolean;
  isPlatformAdmin?: boolean;
}): EntryRoute {
  if (signedIn && isPlatformAdmin) return "/admin";
  if (signedIn && mobileVerificationPending) return "/verify-mobile";
  if (signedIn) return onboardingCompleted ? "/dashboard" : "/onboarding/facility";
  return deviceOnboarded ? "/login" : "/welcome";
}