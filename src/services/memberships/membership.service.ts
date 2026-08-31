import type { Booking } from "@/features/bookings/types";
import type { Member, MemberInput } from "@/features/members/types";
import type {
  AssignableBatch,
  CreateMembershipFullInput,
  CreateMembershipInput,
  FacilityMemberRow,
  Membership,
  MembershipListParams,
  MembershipListResult,
  MembershipPageSummary,
  MembershipPlan,
  MembershipPlanInput,
  MembershipRevenuePoint,
  MembershipSubscriptionInfo,
  MemberStats,
  RevenueGranularity,
} from "@/features/memberships/types";

export interface MembershipService {
  /**
   * Creates a facility CUSTOMER/PLAYER record — never a Supabase Auth
   * account. Throws MemberAlreadyExistsError when the facility already has
   * a member with this phone number.
   */
  createMember(input: MemberInput): Promise<Member>;
  updateMember(memberId: string, patch: Partial<MemberInput> & { status?: "ACTIVE" | "INACTIVE" }): Promise<Member>;
  getMember(memberId: string): Promise<Member | null>;
  /** Facility-scoped, no membership required — a member can be booked with or without an active plan. */
  searchMembers(facilityId: string, query: string): Promise<Pick<Member, "id" | "fullName" | "phone" | "email">[]>;
  /** One row per member, their most recent membership at this facility — facility-scoped via the memberships relationship. */
  searchFacilityMembers(
    facilityId: string,
    opts?: { query?: string; limit?: number; offset?: number },
  ): Promise<FacilityMemberRow[]>;
  getFacilityPlans(facilityId: string, opts?: { activeOnly?: boolean }): Promise<MembershipPlan[]>;
  createPlan(input: MembershipPlanInput): Promise<MembershipPlan>;
  updatePlan(planId: string, patch: Partial<MembershipPlanInput> & { isActive?: boolean }): Promise<MembershipPlan>;
  /** The single write path for both "assign a plan" and "renew" — renewal is just calling this again with a new start date. */
  createMembership(input: CreateMembershipInput): Promise<Membership>;
  /** The full Create Membership page — get-or-create the member and record a self-contained membership + payment. */
  createMembershipFull(input: CreateMembershipFullInput): Promise<Membership>;
  /** Owner/manager sets the facility's default membership access days (0=Sun..6=Sat); returns the saved set. */
  setMembershipAccessDays(facilityId: string, days: number[]): Promise<number[]>;
  /** Paginated, filterable, sortable list for the Memberships page. */
  listMemberships(facilityId: string, params: MembershipListParams): Promise<MembershipListResult>;
  /** The five KPI tiles on the Memberships page, with month-over-month deltas. */
  getMembershipPageSummary(facilityId: string): Promise<MembershipPageSummary>;
  /** Starts (or reuses) a Razorpay Subscription for recurring UPI AutoPay on this membership. */
  createMembershipSubscription(membershipId: string): Promise<MembershipSubscriptionInfo>;
  /** Membership revenue actually received, bucketed by day / month / year. */
  getMembershipRevenueTimeseries(
    facilityId: string,
    granularity: RevenueGranularity,
    range?: { from?: string; to?: string },
  ): Promise<MembershipRevenuePoint[]>;
  /** Time-slot batches with current roster counts, for assigning a membership to a per-hour slot. */
  listAssignableBatches(facilityId: string, planId?: string): Promise<AssignableBatch[]>;
  /** Places a member into a batch (per-hour slot); throws when the slot is full. */
  assignMembershipToBatch(batchId: string, memberId: string, membershipId: string): Promise<void>;
  cancelMembership(membershipId: string): Promise<Membership>;
  getMemberStats(memberId: string, facilityId: string): Promise<MemberStats>;
  /** Every membership a member has held at this facility, most recent first — never overwritten by renewal. */
  getMembershipHistory(memberId: string, facilityId: string): Promise<Membership[]>;
  getMemberBookings(memberId: string, facilityId: string, opts?: { limit?: number; offset?: number }): Promise<Booking[]>;
}