"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
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
  MembershipListStatus,
  MembershipPageSummary,
  MembershipPlan,
  MembershipPlanInput,
  MembershipRevenuePoint,
  MembershipSubscriptionInfo,
  MemberStats,
  RevenueGranularity,
} from "@/features/memberships/types";
import { toBooking } from "@/services/bookings/supabase-booking.service";
import type { MembershipService } from "@/services/memberships/membership.service";
import { ServiceError, mapSupabaseError } from "@/services/shared/service-error";
import type { Database } from "@/types/database.types";

type PlanRow = Database["public"]["Tables"]["membership_plans"]["Row"];
type MembershipRow = Database["public"]["Tables"]["memberships"]["Row"];
type MemberRow = Database["public"]["Tables"]["members"]["Row"];

/** Thrown when the facility already has a member with this phone number — carries the existing id so the UI can offer "View Existing Member" instead of a dead-end error. */
export class MemberAlreadyExistsError extends ServiceError {
  readonly existingMemberId: string;
  constructor(existingMemberId: string) {
    super("MEMBER_ALREADY_EXISTS");
    this.existingMemberId = existingMemberId;
  }
}

function toMember(row: MemberRow): Member {
  return {
    id: row.id,
    facilityId: row.facility_id,
    fullName: row.full_name,
    phone: row.phone,
    email: row.email,
    dateOfBirth: row.date_of_birth,
    gender: row.gender,
    notes: row.notes,
    status: row.status,
    userId: row.user_id,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function toPlan(row: PlanRow): MembershipPlan {
  return {
    id: row.id,
    facilityId: row.facility_id,
    name: row.name,
    priceInr: row.price_inr,
    durationDays: row.duration_days,
    features: row.features ?? [],
    isActive: row.is_active,
    createdAt: row.created_at,
  };
}

function toMembership(row: MembershipRow, planName: string): Membership {
  return {
    id: row.id,
    facilityId: row.facility_id,
    memberId: row.member_id,
    planId: row.plan_id,
    planName,
    status: row.status,
    startDate: row.start_date,
    endDate: row.end_date,
    autoRenew: row.auto_renew,
    createdAt: row.created_at,
  };
}

export class SupabaseMembershipService implements MembershipService {
  private readonly supabase: SupabaseClient<Database>;

  constructor(client?: SupabaseClient<Database>) {
    this.supabase = client ?? createClient();
  }

  async createMember(input: MemberInput): Promise<Member> {
    const phone = input.phone.trim();

    // Pre-check by (facility, phone) so a duplicate surfaces as "Member
    // already exists" with the existing member's id, instead of a bare
    // unique-violation the UI can't act on.
    const { data: existing } = await this.supabase
      .from("members")
      .select("id")
      .eq("facility_id", input.facilityId)
      .eq("phone", phone)
      .maybeSingle();
    if (existing) throw new MemberAlreadyExistsError(existing.id);

    const { data, error } = await this.supabase.rpc("create_member", {
      p_facility_id: input.facilityId,
      p_full_name: input.fullName,
      p_phone: phone,
      p_email: input.email ?? null,
      p_date_of_birth: input.dateOfBirth ?? null,
      p_gender: input.gender ?? null,
      p_notes: input.notes ?? null,
    });

    if (error) throw mapSupabaseError(error, { duplicate: "MEMBER_ALREADY_EXISTS", invalid: "INVALID_MEMBER" });
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return toMember(data);
  }

  async updateMember(
    memberId: string,
    patch: Partial<MemberInput> & { status?: "ACTIVE" | "INACTIVE" },
  ): Promise<Member> {
    const existing = await this.getMember(memberId);
    if (!existing) throw new ServiceError("MEMBER_NOT_FOUND");

    const { data, error } = await this.supabase.rpc("update_member", {
      p_member_id: memberId,
      p_full_name: patch.fullName ?? existing.fullName,
      p_phone: patch.phone ?? existing.phone,
      p_email: patch.email !== undefined ? patch.email : existing.email,
      p_date_of_birth: patch.dateOfBirth !== undefined ? patch.dateOfBirth : existing.dateOfBirth,
      p_gender: patch.gender !== undefined ? patch.gender : existing.gender,
      p_notes: patch.notes !== undefined ? patch.notes : existing.notes,
      p_status: patch.status ?? existing.status,
    });

    if (error) throw mapSupabaseError(error, { duplicate: "MEMBER_ALREADY_EXISTS", invalid: "INVALID_MEMBER", notFound: "MEMBER_NOT_FOUND" });
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return toMember(data);
  }

  async getMember(memberId: string): Promise<Member | null> {
    const { data, error } = await this.supabase.from("members").select("*").eq("id", memberId).maybeSingle();
    if (error) throw mapSupabaseError(error);
    return data ? toMember(data) : null;
  }

  async searchMembers(facilityId: string, query: string): Promise<Pick<Member, "id" | "fullName" | "phone" | "email">[]> {
    const trimmed = query.trim();
    if (trimmed.length < 2) return [];

    const { data, error } = await this.supabase.rpc("search_members", { p_facility_id: facilityId, p_query: trimmed });
    if (error) throw mapSupabaseError(error);
    return (data ?? []).map((row) => ({
      id: row.id,
      fullName: row.full_name,
      phone: row.phone,
      email: row.email,
    }));
  }

  async searchFacilityMembers(
    facilityId: string,
    opts: { query?: string; limit?: number; offset?: number } = {},
  ): Promise<FacilityMemberRow[]> {
    const { data, error } = await this.supabase.rpc("search_facility_members", {
      p_facility_id: facilityId,
      p_query: opts.query?.trim() || null,
      p_limit: opts.limit ?? 50,
      p_offset: opts.offset ?? 0,
    });

    if (error) throw mapSupabaseError(error);
    return (data ?? []).map((row) => ({
      memberId: row.member_id,
      fullName: row.full_name,
      phone: row.phone,
      email: row.email,
      membershipId: row.membership_id,
      planId: row.plan_id,
      planName: row.plan_name,
      startDate: row.start_date,
      endDate: row.end_date,
      status: row.status,
    }));
  }

  async getFacilityPlans(facilityId: string, opts: { activeOnly?: boolean } = {}): Promise<MembershipPlan[]> {
    let query = this.supabase.from("membership_plans").select("*").eq("facility_id", facilityId);
    if (opts.activeOnly) query = query.eq("is_active", true);
    const { data, error } = await query.order("price_inr", { ascending: true });
    if (error) throw mapSupabaseError(error);
    return (data ?? []).map(toPlan);
  }

  async createPlan(input: MembershipPlanInput): Promise<MembershipPlan> {
    const { data, error } = await this.supabase
      .from("membership_plans")
      .insert({
        facility_id: input.facilityId,
        name: input.name,
        price_inr: input.priceInr,
        duration_days: input.durationDays,
        features: input.features ?? [],
      })
      .select("*")
      .single();

    if (error) throw mapSupabaseError(error, { duplicate: "MEMBERSHIP_PLAN_NOT_FOUND" });
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return toPlan(data);
  }

  async updatePlan(
    planId: string,
    patch: Partial<MembershipPlanInput> & { isActive?: boolean },
  ): Promise<MembershipPlan> {
    const update: Database["public"]["Tables"]["membership_plans"]["Update"] = {};
    if (patch.name !== undefined) update.name = patch.name;
    if (patch.priceInr !== undefined) update.price_inr = patch.priceInr;
    if (patch.durationDays !== undefined) update.duration_days = patch.durationDays;
    if (patch.features !== undefined) update.features = patch.features;
    if (patch.isActive !== undefined) update.is_active = patch.isActive;

    const { data, error } = await this.supabase
      .from("membership_plans")
      .update(update)
      .eq("id", planId)
      .select("*")
      .maybeSingle();

    if (error) throw mapSupabaseError(error);
    if (!data) throw new ServiceError("MEMBERSHIP_PLAN_NOT_FOUND");
    return toPlan(data);
  }

  async createMembership(input: CreateMembershipInput): Promise<Membership> {
    const { data, error } = await this.supabase.rpc("create_membership", {
      p_member_id: input.memberId,
      p_facility_id: input.facilityId,
      p_plan_id: input.planId,
      p_start_date: input.startDate,
      p_payment_status: input.paymentStatus ?? "created",
      p_monthly_price_inr: input.monthlyPriceInr ?? null,
    });

    if (error) throw mapSupabaseError(error, { notFound: "MEMBERSHIP_PLAN_NOT_FOUND", invalid: "INVALID_MEMBERSHIP" });
    if (!data) throw new ServiceError("DATABASE_ERROR");

    return toMembership(data, await this.planName(data.plan_id, data.name));
  }

  private async planName(planId: string | null, ownName: string | null): Promise<string> {
    if (!planId) return ownName ?? "Membership";
    const { data } = await this.supabase.from("membership_plans").select("name").eq("id", planId).maybeSingle();
    return data?.name ?? ownName ?? "Membership";
  }

  async cancelMembership(membershipId: string): Promise<Membership> {
    const { data, error } = await this.supabase.rpc("cancel_membership", { p_membership_id: membershipId });
    if (error) throw mapSupabaseError(error, { notFound: "MEMBERSHIP_NOT_FOUND" });
    if (!data) throw new ServiceError("MEMBERSHIP_NOT_FOUND");

    return toMembership(data, await this.planName(data.plan_id, data.name));
  }

  async listMemberships(facilityId: string, params: MembershipListParams): Promise<MembershipListResult> {
    const { data, error } = await this.supabase.rpc("list_memberships", {
      p_facility_id: facilityId,
      p_search: params.search?.trim() || null,
      p_status: params.status ?? null,
      p_plan_id: params.planId ?? null,
      p_sort: params.sort ?? "newest",
      p_limit: params.perPage,
      p_offset: (params.page - 1) * params.perPage,
    });
    if (error) throw mapSupabaseError(error);

    const rows = (data ?? []).map((row) => ({
      membershipId: row.membership_id,
      memberId: row.member_id,
      memberName: row.member_name,
      memberPhone: row.member_phone,
      memberEmail: row.member_email,
      planId: row.plan_id,
      planName: row.plan_name,
      monthlyPriceInr: row.monthly_price_inr,
      status: row.display_status as MembershipListStatus,
      startDate: row.start_date,
      endDate: row.end_date,
      daysLeft: row.days_left,
      createdById: row.created_by,
      createdByName: row.created_by_name,
      slot: row.batch_name
        ? {
            name: row.batch_name,
            daysOfWeek: row.batch_days ?? [],
            startTime: row.batch_start ?? "",
            endTime: row.batch_end ?? "",
            courtName: row.batch_court,
          }
        : null,
    }));
    return { rows, totalCount: data?.[0]?.total_count ?? 0 };
  }

  async getMembershipPageSummary(facilityId: string): Promise<MembershipPageSummary> {
    const { data, error } = await this.supabase.rpc("get_membership_page_summary", { p_facility_id: facilityId });
    if (error) throw mapSupabaseError(error);
    const row = data?.[0];
    const totalMembers = row?.total_members ?? 0;
    const prev = row?.total_members_prev ?? 0;
    const revenue = row?.revenue_inr ?? 0;
    const revenuePrev = row?.revenue_prev_inr ?? 0;
    const pctChange = (cur: number, before: number) => (before === 0 ? null : ((cur - before) / before) * 100);
    return {
      totalMembers,
      totalMembersChangePct: pctChange(totalMembers, prev),
      activeMembers: row?.active_members ?? 0,
      activePctOfTotal: totalMembers === 0 ? 0 : ((row?.active_members ?? 0) / totalMembers) * 100,
      expiringSoon: row?.expiring_soon ?? 0,
      expiredMembers: row?.expired_members ?? 0,
      revenueInr: revenue,
      revenueChangePct: pctChange(revenue, revenuePrev),
    };
  }

  async createMembershipSubscription(membershipId: string): Promise<MembershipSubscriptionInfo> {
    const { data, error } = await this.supabase.functions.invoke<
      { subscriptionId: string; shortUrl: string | null; keyId: string } | { error: string }
    >("create-membership-subscription", { body: { membershipId } });
    if (error) throw new ServiceError("PAYMENT_GATEWAY_ERROR");
    if (!data || "error" in data) throw new ServiceError("PAYMENT_GATEWAY_ERROR");
    return { subscriptionId: data.subscriptionId, shortUrl: data.shortUrl, keyId: data.keyId };
  }

  async getMembershipRevenueTimeseries(
    facilityId: string,
    granularity: RevenueGranularity,
    range?: { from?: string; to?: string },
  ): Promise<MembershipRevenuePoint[]> {
    const { data, error } = await this.supabase.rpc("get_membership_revenue_timeseries", {
      p_facility_id: facilityId,
      p_granularity: granularity,
      p_from: range?.from ?? null,
      p_to: range?.to ?? null,
    });
    if (error) throw mapSupabaseError(error);
    return (data ?? []).map((row) => ({
      bucket: row.bucket,
      amountInr: row.amount_inr,
      paymentCount: row.payment_count,
    }));
  }

  async createMembershipFull(input: CreateMembershipFullInput): Promise<Membership> {
    const { data, error } = await this.supabase.rpc("create_membership_full", {
      p_facility_id: input.facilityId,
      p_full_name: input.fullName,
      p_phone: input.phone,
      p_email: input.email ?? null,
      p_date_of_birth: input.dateOfBirth ?? null,
      p_gender: input.gender ?? null,
      p_address: input.address ?? null,
      p_name: input.name ?? null,
      p_membership_type: input.membershipType,
      p_max_family_members: input.maxFamilyMembers,
      p_start_date: input.startDate,
      p_duration_days: input.durationDays,
      p_description: input.description ?? null,
      p_membership_fee_inr: input.membershipFeeInr,
      p_registration_fee_inr: input.registrationFeeInr,
      p_gst_percent: input.gstPercent,
      p_payment_mode: input.paymentMode,
      p_payment_methods: input.paymentMethods?.join(", ") || null,
      p_payment_reference: input.paymentReference ?? null,
      p_referral_member_id: input.referralMemberId ?? null,
      p_discovery_source: input.discoverySource ?? null,
      p_notes: input.notes ?? null,
      p_monthly_price_inr: input.membershipFeeInr,
      p_batch_id: input.batchId ?? null,
      p_new_batch: input.newBatch ?? null,
    });
    if (error) throw mapSupabaseError(error, { invalid: "INVALID_MEMBERSHIP" });
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return toMembership(data, data.name ?? "Membership");
  }

  async setMembershipAccessDays(facilityId: string, days: number[]): Promise<number[]> {
    const { data, error } = await this.supabase.rpc("set_facility_membership_access_days", {
      p_facility_id: facilityId,
      p_days: days,
    });
    if (error) throw mapSupabaseError(error, { invalid: "INVALID_MEMBERSHIP" });
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return (data as { membership_access_days: number[] }).membership_access_days;
  }

  async listAssignableBatches(facilityId: string, planId?: string): Promise<AssignableBatch[]> {
    const { data, error } = await this.supabase.rpc("list_assignable_batches", {
      p_facility_id: facilityId,
      p_plan_id: planId ?? null,
    });
    if (error) throw mapSupabaseError(error);
    return (data ?? []).map((row) => ({
      batchId: row.batch_id,
      name: row.name,
      planId: row.plan_id,
      courtId: row.court_id,
      courtName: row.court_name,
      sportName: row.sport_name,
      daysOfWeek: row.days_of_week,
      startTime: row.start_time,
      endTime: row.end_time,
      capacity: row.capacity,
      enrolledCount: row.enrolled_count,
      spare: row.spare,
    }));
  }

  async assignMembershipToBatch(batchId: string, memberId: string, membershipId: string): Promise<void> {
    const { error } = await this.supabase.rpc("assign_batch_member", {
      p_batch_id: batchId,
      p_member_id: memberId,
      p_membership_id: membershipId,
    });
    if (error) throw mapSupabaseError(error, { invalid: "INVALID_MEMBERSHIP" });
  }

  async getMemberStats(memberId: string, facilityId: string): Promise<MemberStats> {
    const { data, error } = await this.supabase.rpc("get_member_stats", {
      p_member_id: memberId,
      p_facility_id: facilityId,
    });
    if (error) throw mapSupabaseError(error);
    const row = data?.[0];
    return {
      totalVisits: row?.total_visits ?? 0,
      totalBookings: row?.total_bookings ?? 0,
      lastVisit: row?.last_visit ?? null,
      totalAmountMinor: row?.total_amount_minor ?? 0,
      pendingAmountMinor: row?.pending_amount_minor ?? 0,
      sports: row?.sports ?? [],
    };
  }

  async getMembershipHistory(memberId: string, facilityId: string): Promise<Membership[]> {
    const { data, error } = await this.supabase
      .from("memberships")
      .select("*, membership_plans(name)")
      .eq("member_id", memberId)
      .eq("facility_id", facilityId)
      .order("start_date", { ascending: false });

    if (error) throw mapSupabaseError(error);
    return (data ?? []).map((row) => toMembership(row, (row as { membership_plans?: { name?: string } }).membership_plans?.name ?? ""));
  }

  async getMemberBookings(
    memberId: string,
    facilityId: string,
    opts: { limit?: number; offset?: number } = {},
  ): Promise<Booking[]> {
    const limit = opts.limit ?? 20;
    const offset = opts.offset ?? 0;
    const { data, error } = await this.supabase
      .from("bookings")
      .select("*")
      .eq("member_id", memberId)
      .eq("facility_id", facilityId)
      .order("start_time", { ascending: false })
      .range(offset, offset + limit - 1);

    if (error) throw mapSupabaseError(error);
    return (data ?? []).map(toBooking);
  }
}