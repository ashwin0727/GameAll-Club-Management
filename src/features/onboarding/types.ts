export type FacilityType =
  | "BADMINTON"
  | "PICKLEBALL"
  | "CRICKET"
  | "FOOTBALL"
  | "TENNIS"
  | "MULTI_SPORT"
  | "OTHER";

export interface FacilityAddress {
  line1: string;
  area: string;
  city: string;
  state: string;
  country: "India";
  pinCode: string;
}

/**
 * Frontend-only shape for this onboarding phase. Intentionally richer than
 * the current `facilities` table (see src/types/database.types.ts), which
 * has no `type`, `phone`, structured address, logo, or description columns
 * yet — a future migration grows the schema to match, not the other way
 * round. `ownerId` is carried from day one so the shape never blocks
 * Owner -> [Facility A, Facility B, ...] later, even though only one
 * facility per owner is created today.
 */
export interface Facility {
  id: string;
  ownerId: string;
  name: string;
  type: FacilityType;
  customType?: string;
  businessEmail: string;
  businessPhone: string;
  address: FacilityAddress;
  logoUrl?: string;
  description?: string;
  status: "ACTIVE" | "INACTIVE";
  onboardingStep:
    | "FACILITY_DETAILS"
    | "SPORTS"
    | "COURTS"
    | "OPERATING_HOURS"
    | "PRICING"
    | "COMPLETED";
  onboardingCompletedAt?: string;
  createdAt: string;
  updatedAt: string;
}

export type FacilityInput = Omit<
  Facility,
  "id" | "createdAt" | "updatedAt" | "status" | "onboardingStep" | "onboardingCompletedAt"
> & {
  status?: Facility["status"];
};
