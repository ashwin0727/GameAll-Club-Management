import type { EntryRoute } from "@/features/auth/types";

/**
 * The splash screen's routing decision, kept separate from the component so the
 * rule is testable on its own:
 *
 *   signed in            → dashboard
 *   signed out, returning → login
 *   signed out, first run → welcome
 */
export function resolveEntryRoute({
  signedIn,
  deviceOnboarded,
}: {
  signedIn: boolean;
  deviceOnboarded: boolean;
}): EntryRoute {
  if (signedIn) return "/dashboard";
  return deviceOnboarded ? "/login" : "/welcome";
}