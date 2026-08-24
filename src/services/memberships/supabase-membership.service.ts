"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
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
    });

    if (error) throw mapSupabaseError(error, { notFound: "MEMBERSHIP_PLAN_NOT_FOUND", invalid: "INVALID_MEMBERSHIP" });
    if (!data) throw new ServiceError("DATABASE_ERROR");

    const { data: plan } = await this.supabase
      .from("membership_plans")
      .select("name")
      .eq("id", data.plan_id)
      .maybeSingle();

    return toMembership(data, plan?.name ?? "");
  }

  async cancelMembership(membershipId: string): Promise<Membership> {
    const { data, error } = await this.supabase.rpc("cancel_membership", { p_membership_id: membershipId });
    if (error) throw mapSupabaseError(error, { notFound: "MEMBERSHIP_NOT_FOUND" });
    if (!data) throw new ServiceError("MEMBERSHIP_NOT_FOUND");

    const { data: plan } = await this.supabase
      .from("membership_plans")
      .select("name")
      .eq("id", data.plan_id)
      .maybeSingle();

    return toMembership(data, plan?.name ?? "");
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