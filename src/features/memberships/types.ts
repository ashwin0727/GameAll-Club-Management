import type { MembershipStatus, PaymentStatus } from "@/types/database.types";

export interface MembershipPlan {
  id: string;
  facilityId: string;
  name: string;
  priceInr: number;
  durationDays: number;
  features: string[];
  isActive: boolean;
  createdAt: string;
}

export interface MembershipPlanInput {
  facilityId: string;
  name: string;
  priceInr: number;
  durationDays: number;
  features?: string[];
}

export interface Membership {
  id: string;
  facilityId: string;
  memberId: string;
  planId: string;
  planName: string;
  status: MembershipStatus;
  startDate: string;
  endDate: string;
  autoRenew: boolean;
  createdAt: string;
}

/** One row in the facility's member list — every facility member, with their most recent membership left-joined in (null when the member has never been assigned a plan). */
export interface FacilityMemberRow {
  memberId: string;
  fullName: string;
  phone: string;
  email: string | null;
  membershipId: string | null;
  planId: string | null;
  planName: string | null;
  startDate: string | null;
  endDate: string | null;
  status: MembershipStatus | null;
}

export interface CreateMembershipInput {
  memberId: string;
  facilityId: string;
  planId: string;
  /** ISO date (YYYY-MM-DD). */
  startDate: string;
  paymentStatus?: PaymentStatus;
}

export interface MemberSportPlayed {
  sportId: string;
  sportName: string;
}

/** Everything on the Member Profile screen — derived live from real bookings, never a maintained counter. */
export interface MemberStats {
  totalVisits: number;
  totalBookings: number;
  lastVisit: string | null;
  totalAmountMinor: number;
  pendingAmountMinor: number;
  sports: MemberSportPlayed[];
}