import type { Facility, FacilityInput } from "@/features/onboarding/types";

export type OnboardingStep =
  | "FACILITY_DETAILS"
  | "SPORTS"
  | "COURTS"
  | "OPERATING_HOURS"
  | "PRICING"
  | "COMPLETED";

/**
 * The facility boundary the UI codes against — screens never talk to
 * Supabase directly, so the provider can change without touching a
 * component. `ownerId` on FacilityInput is accepted for shape compatibility
 * with existing callers but is never trusted: the implementation always
 * assigns the authenticated caller as owner.
 */
export interface FacilityService {
  createFacility(input: FacilityInput): Promise<Facility>;
  /** The current user's first facility, or null if they haven't created one yet. */
  getFacility(): Promise<Facility | null>;
  /** Every facility the current user owns or belongs to. */
  getFacilities(): Promise<Facility[]>;
  updateFacility(id: string, patch: Partial<FacilityInput>): Promise<Facility>;
  updateOnboardingStep(facilityId: string, step: OnboardingStep): Promise<void>;
}