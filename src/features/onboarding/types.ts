import type { Amenities, FacilityPolicies, OwnershipType, VenueType, VerificationStatus } from "@/features/facility-profile/types";

export interface FacilityPricingSettings {
  /** One set of prices per sport, or each court on its own. */
  mode: "BY_SPORT" | "BY_COURT";
  /** Separate weekday and weekend rates (and specific days). Off = one set of prices for every day. */
  differentWeekendPricing: boolean;
  /** Collect a member rate / a coaching rate per sport or court. */
  memberPricingEnabled: boolean;
  coachingPricingEnabled: boolean;
}

export interface FacilityHoursSettings {
  /** Owner / manager / staff may create bookings outside the working hours. */
  allowBookingsOutsideHours: boolean;
  /** A fixed daily break ("HH:MM"), both or neither. */
  breakStart?: string;
  breakEnd?: string;
  /** Each sport has its own hours (stored as per-court schedules). */
  sportWiseHours: boolean;
}

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
  /** The Google Maps link the owner pasted; GameAll's admin checks it. */
  locationUrl?: string;
  locationVerification?: { status: VerificationStatus; note?: string };
  venueType?: VenueType;
  amenities?: Amenities;
  /** Owned or leased premises. */
  ownershipType?: OwnershipType;
  /** Optional WhatsApp number players/the team can reach the venue on. */
  whatsappNumber?: string;
  /** The person to reach about bookings and operations. */
  contactPerson?: { name: string; role: string; alternatePhone?: string };
  policies?: FacilityPolicies;
  /** The amenities on offer (keys from FACILITY_AMENITIES) and any the owner typed in. */
  amenityKeys?: string[];
  customAmenities?: string[];
  /** The extras on the Operating Hours step. */
  hoursSettings?: FacilityHoursSettings;
  pricingSettings?: FacilityPricingSettings;
  status: "ACTIVE" | "INACTIVE";
  onboardingStep:
    | "FACILITY_DETAILS"
    | "SPORTS"
    | "COURTS"
    | "OPERATING_HOURS"
    | "PAYMENTS"
    | "PRICING"
    | "COMPLETED";
  onboardingCompletedAt?: string;
  createdAt: string;
  updatedAt: string;
  /** Days of week (0=Sun..6=Sat) a member may use the court. Pre-fills the
   *  time-slot day picker on the Create Membership page. */
  membershipAccessDays: number[];
}

export type FacilityInput = Omit<
  Facility,
  | "id"
  | "createdAt"
  | "updatedAt"
  | "status"
  | "onboardingStep"
  | "onboardingCompletedAt"
  | "membershipAccessDays"
> & {
  status?: Facility["status"];
};
