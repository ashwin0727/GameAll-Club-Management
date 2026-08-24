import type { Booking } from "@/features/bookings/types";
import type { Member, MemberInput } from "@/features/members/types";
import type {
  CreateMembershipInput,
  FacilityMemberRow,
  Membership,
  MembershipPlan,
  MembershipPlanInput,
  MemberStats,
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
  cancelMembership(membershipId: string): Promise<Membership>;
  getMemberStats(memberId: string, facilityId: string): Promise<MemberStats>;
  /** Every membership a member has held at this facility, most recent first — never overwritten by renewal. */
  getMembershipHistory(memberId: string, facilityId: string): Promise<Membership[]>;
  getMemberBookings(memberId: string, facilityId: string, opts?: { limit?: number; offset?: number }): Promise<Booking[]>;
}