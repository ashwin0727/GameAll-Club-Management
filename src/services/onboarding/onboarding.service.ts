import type { Facility } from "@/features/onboarding/types";
import type { SetupStatus, SetupSummary } from "@/features/onboarding-summary/types";

/**
 * The setup-summary boundary the UI codes against. Aggregates the facility,
 * sports, playing areas, operating hours, and pricing already exposed by
 * their own services into one structured object rather than the page
 * issuing five separate uncontrolled requests itself.
 */
export interface OnboardingService {
  getSetupSummary(facilityId: string): Promise<SetupSummary>;
  validateSetup(facilityId: string): Promise<SetupStatus>;
  /** Re-validates server-side and atomically marks the facility COMPLETED. Idempotent. */
  completeSetup(facilityId: string): Promise<Facility>;
  getOnboardingStatus(facilityId: string): Promise<Facility["onboardingStep"]>;
}