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
  planId: string | null;
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
  /** Owner-set recurring price; falls back to the plan price when omitted. */
  monthlyPriceInr?: number;
}

export type MembershipType = "INDIVIDUAL" | "FAMILY" | "CORPORATE";
export type MembershipPaymentMode = "PAID" | "PENDING" | "FREE";

/** The full Create Membership page — a self-contained membership (its own name / type / duration / fee). */
export interface CreateMembershipFullInput {
  facilityId: string;
  // Member
  fullName: string;
  phone: string;
  email?: string;
  dateOfBirth?: string;
  gender?: string;
  address?: string;
  // Membership details
  name?: string;
  membershipType: MembershipType;
  maxFamilyMembers: number;
  startDate: string;
  durationDays: number;
  /** Join an existing membership_batches time slot for this facility. */
  batchId?: string;
  /** Or create a new reserved court time slot. Mutually exclusive with batchId. */
  newBatch?: {
    courtId: string;
    facilitySportId: string;
    daysOfWeek: number[];
    startTime: string; // "HH:mm"
    endTime: string; // "HH:mm"
    capacity: number;
    name?: string;
  };
  description?: string;
  // Charges
  membershipFeeInr: number;
  registrationFeeInr: number;
  gstPercent: number;
  // Payment
  paymentMode: MembershipPaymentMode;
  paymentMethods?: string[];
  paymentReference?: string;
  recurring?: boolean;
  // Extras
  referralMemberId?: string;
  discoverySource?: string;
  notes?: string;
}

export type MembershipListStatus = "payment_incomplete" | "active" | "inactive";
export type MembershipListSort = "oldest" | "next_payment" | "name";

export interface MembershipSlot {
  name: string;
  daysOfWeek: number[];
  startTime: string;
  endTime: string;
  courtName: string | null;
}

export interface MembershipListRow {
  membershipId: string;
  memberId: string;
  memberName: string;
  memberPhone: string;
  memberEmail: string | null;
  planId: string;
  planName: string;
  monthlyPriceInr: number;
  status: MembershipListStatus;
  startDate: string;
  /** The date the paid period runs out — shown as "Next Payment Date". */
  endDate: string;
  slot: MembershipSlot | null;
}

export interface AssignableBatch {
  batchId: string;
  name: string;
  planId: string | null;
  courtId: string;
  courtName: string;
  sportName: string;
  daysOfWeek: number[];
  startTime: string;
  endTime: string;
  capacity: number;
  enrolledCount: number;
  spare: number;
}

export interface PublicSignupBatch {
  batchId: string;
  name: string;
  courtName: string;
  sportName: string;
  daysOfWeek: number[];
  startTime: string;
  endTime: string;
  capacity: number;
  spare: number;
}

export interface MembershipListParams {
  search?: string;
  status?: MembershipListStatus;
  planId?: string;
  sort?: MembershipListSort;
  page: number;
  perPage: number;
}

export interface MembershipListResult {
  rows: MembershipListRow[];
  totalCount: number;
}

export interface MembershipSubscriptionInfo {
  subscriptionId: string;
  /** Razorpay-hosted page where the player authorises the UPI AutoPay mandate. */
  shortUrl: string | null;
  keyId: string;
}

export type RevenueGranularity = "day" | "month" | "year";

export interface MembershipRevenuePoint {
  bucket: string;
  amountInr: number;
  paymentCount: number;
}

export interface PublicSignupPlan {
  id: string;
  name: string;
  priceInr: number;
  durationDays: number;
  features: string[];
}

export interface PublicSignupInfo {
  facilityId: string;
  facilityName: string;
  city: string;
  plans: PublicSignupPlan[];
}

export interface PublicSignupResult {
  membershipId: string;
  memberId: string;
  amountInr: number;
}

export interface MembershipPageSummary {
  totalMembers: number;
  totalMembersChangePct: number | null;
  activeMembers: number;
  activePctOfTotal: number;
  paymentIncompleteMembers: number;
  revenueInr: number;
  revenueChangePct: number | null;
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

export interface MembershipTimelineEvent {
  label: string;
  actor: string;
  at: string;
}

/** Everything the Membership Details page shows — one `get_membership_detail` read. */
export interface MembershipDetail {
  membershipId: string;
  facilityId: string;
  displayStatus: MembershipListStatus;
  member: {
    id: string;
    fullName: string;
    phone: string;
    email: string | null;
    dateOfBirth: string | null;
    gender: string | null;
    address: string | null;
    status: string;
    memberSince: string;
  };
  membership: {
    name: string;
    membershipType: string;
    rawStatus: MembershipStatus;
    startDate: string;
    endDate: string;
    durationDays: number | null;
    maxFamilyMembers: number;
    description: string | null;
    membershipFeeInr: number;
    registrationFeeInr: number;
    gstPercent: number;
    totalAmountInr: number;
    monthlyPriceInr: number;
    autoRenew: boolean;
    createdAt: string;
  };
  payment: {
    amountInr: number;
    status: PaymentStatus;
    settled: boolean;
    method: string | null;
    paidAt: string | null;
    createdAt: string;
    transactionId: string | null;
  } | null;
  referralName: string | null;
  referralMemberId: string | null;
  createdByName: string | null;
  discoverySource: string | null;
  paymentReference: string | null;
  notes: string | null;
  slot: {
    batchId: string;
    courtId: string;
    facilitySportId: string;
    courtName: string | null;
    capacity: number;
    daysOfWeek: number[];
    startTime: string;
    endTime: string;
  } | null;
  timeline: MembershipTimelineEvent[];
}

/** Edit Membership — the Create form reopened in edit mode. No payment fields. */
export interface UpdateMembershipFullInput {
  fullName: string;
  phone: string;
  email?: string;
  dateOfBirth?: string;
  gender?: string;
  address?: string;
  name?: string;
  membershipType: MembershipType;
  maxFamilyMembers: number;
  startDate: string;
  durationDays: number;
  batchId?: string;
  newBatch?: {
    courtId: string;
    facilitySportId: string;
    daysOfWeek: number[];
    startTime: string;
    endTime: string;
    capacity: number;
    name?: string;
  };
  description?: string;
  membershipFeeInr: number;
  registrationFeeInr: number;
  gstPercent: number;
  referralMemberId?: string;
  discoverySource?: string;
  notes?: string;
}