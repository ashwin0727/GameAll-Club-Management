"use client";

import type { SupabaseClient, PostgrestError } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import type {
  MembershipBatch,
  MembershipBatchInput,
  MembershipBatchMember,
  MembershipSessionActivity,
  MembershipSessionBooking,
  MembershipSessionBookingRow,
  MembershipSessionCapacity,
  MembershipSessionDetail,
  MembershipSessionListParams,
  MembershipSessionListResult,
  MembershipSessionMemberRow,
  MembershipSessionOccurrence,
  MembershipSessionSlot,
  MembershipSessionsSummary,
} from "@/features/membership-sessions/types";
import type { MembershipSessionService } from "@/services/membership-sessions/membership-session.service";
import { ServiceError, mapSupabaseError } from "@/services/shared/service-error";
import type { Database } from "@/types/database.types";

type BatchRow = Database["public"]["Tables"]["membership_batches"]["Row"];
type BatchMemberRow = Database["public"]["Tables"]["membership_batch_members"]["Row"];
type SessionBookingRow = Database["public"]["Tables"]["membership_session_bookings"]["Row"];

function toBatch(row: BatchRow): MembershipBatch {
  return {
    id: row.id,
    facilityId: row.facility_id,
    planId: row.plan_id,
    facilitySportId: row.facility_sport_id,
    courtId: row.court_id,
    name: row.name,
    daysOfWeek: row.days_of_week,
    startTime: row.start_time,
    endTime: row.end_time,
    capacity: row.capacity,
    isActive: row.is_active,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function toBatchMember(row: BatchMemberRow): MembershipBatchMember {
  return {
    id: row.id,
    batchId: row.batch_id,
    memberId: row.member_id,
    membershipId: row.membership_id,
    createdAt: row.created_at,
  };
}

function toSessionBooking(row: SessionBookingRow): MembershipSessionBooking {
  return {
    id: row.id,
    sessionId: row.session_id,
    facilityId: row.facility_id,
    participantType: row.participant_type,
    memberId: row.member_id,
    guestPlayerId: row.guest_player_id,
    status: row.status,
    slotSource: row.slot_source,
    amountMinor: row.amount_minor,
    currency: row.currency,
    createdBy: row.created_by,
    createdAt: row.created_at,
  };
}

/**
 * These RPCs raise 23514 with an already-polished, specific message for
 * every business-rule violation (capacity full, nothing to release, a
 * released slot already guest-booked, etc.) — surfaced verbatim rather than
 * collapsed into one generic string, since a real caller needs to know
 * exactly which rule was hit.
 */
function mapCapacityError(error: PostgrestError): ServiceError {
  console.error("[service-error]", error.code, error.message, error.details);
  if (error.code === "23514") return new ServiceError("MEMBERSHIP_CAPACITY_ERROR", error.message);
  if (error.code === "23503") return new ServiceError("INVALID_MEMBERSHIP_BATCH");
  if (error.code === "P0002") return new ServiceError("MEMBERSHIP_SESSION_NOT_FOUND");
  if (error.code === "42501") return new ServiceError("UNAUTHORIZED");
  return new ServiceError("DATABASE_ERROR");
}

export class SupabaseMembershipSessionService implements MembershipSessionService {
  private readonly supabase: SupabaseClient<Database>;

  constructor(client?: SupabaseClient<Database>) {
    this.supabase = client ?? createClient();
  }

  async getFacilityBatches(facilityId: string): Promise<MembershipBatch[]> {
    const { data, error } = await this.supabase
      .from("membership_batches")
      .select("*")
      .eq("facility_id", facilityId)
      .order("start_time", { ascending: true });
    if (error) throw mapSupabaseError(error);
    return (data ?? []).map(toBatch);
  }

  async createBatch(input: MembershipBatchInput): Promise<MembershipBatch> {
    const { data, error } = await this.supabase.rpc("create_membership_batch", {
      p_facility_id: input.facilityId,
      p_plan_id: input.planId,
      p_facility_sport_id: input.facilitySportId,
      p_court_id: input.courtId,
      p_name: input.name,
      p_days_of_week: input.daysOfWeek,
      p_start_time: input.startTime,
      p_end_time: input.endTime,
      p_capacity: input.capacity,
    });
    if (error) throw mapCapacityError(error);
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return toBatch(data);
  }

  async updateBatch(
    batchId: string,
    patch: Partial<Omit<MembershipBatchInput, "facilityId" | "planId" | "facilitySportId">> & { isActive?: boolean },
  ): Promise<MembershipBatch> {
    const { data: existing, error: existingError } = await this.supabase
      .from("membership_batches")
      .select("*")
      .eq("id", batchId)
      .maybeSingle();
    if (existingError) throw mapSupabaseError(existingError);
    if (!existing) throw new ServiceError("MEMBERSHIP_BATCH_NOT_FOUND");

    const { data, error } = await this.supabase.rpc("update_membership_batch", {
      p_batch_id: batchId,
      p_name: patch.name ?? existing.name,
      p_court_id: patch.courtId ?? existing.court_id,
      p_days_of_week: patch.daysOfWeek ?? existing.days_of_week,
      p_start_time: patch.startTime ?? existing.start_time,
      p_end_time: patch.endTime ?? existing.end_time,
      p_capacity: patch.capacity ?? existing.capacity,
      p_is_active: patch.isActive ?? existing.is_active,
    });
    if (error) throw mapCapacityError(error);
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return toBatch(data);
  }

  async getBatchMembers(batchId: string): Promise<MembershipBatchMember[]> {
    const { data, error } = await this.supabase
      .from("membership_batch_members")
      .select("*")
      .eq("batch_id", batchId)
      .order("created_at", { ascending: true });
    if (error) throw mapSupabaseError(error);
    return (data ?? []).map(toBatchMember);
  }

  async assignBatchMember(batchId: string, memberId: string, membershipId: string | null = null): Promise<MembershipBatchMember> {
    const { data, error } = await this.supabase.rpc("assign_batch_member", {
      p_batch_id: batchId,
      p_member_id: memberId,
      p_membership_id: membershipId,
    });
    if (error) throw mapCapacityError(error);
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return toBatchMember(data);
  }

  async removeBatchMember(batchId: string, memberId: string): Promise<void> {
    const { error } = await this.supabase.rpc("remove_batch_member", { p_batch_id: batchId, p_member_id: memberId });
    if (error) throw mapCapacityError(error);
  }

  async listSessionsForDate(facilityId: string, date: string): Promise<MembershipSessionSlot[]> {
    const { data, error } = await this.supabase.rpc("list_membership_sessions_for_date", {
      p_facility_id: facilityId,
      p_date: date,
    });
    if (error) throw mapSupabaseError(error);
    return (data ?? []).map((row) => ({
      batchId: row.batch_id,
      sessionId: row.session_id,
      batchName: row.batch_name,
      courtId: row.court_id,
      courtName: row.court_name,
      facilitySportId: row.facility_sport_id,
      sportName: row.sport_name,
      sessionDate: row.session_date,
      startTime: row.start_time,
      endTime: row.end_time,
      capacity: row.capacity,
      releasedCapacity: row.released_capacity,
      memberBookedCount: row.member_booked_count,
      guestBookedCount: row.guest_booked_count,
    }));
  }

  async getOrCreateSession(batchId: string, sessionDate: string): Promise<string> {
    const { data, error } = await this.supabase.rpc("get_or_create_membership_session", {
      p_batch_id: batchId,
      p_session_date: sessionDate,
    });
    if (error) throw mapCapacityError(error);
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return data.id;
  }

  async getSessionCapacity(sessionId: string): Promise<MembershipSessionCapacity> {
    const { data, error } = await this.supabase.rpc("get_membership_session_capacity", { p_session_id: sessionId });
    if (error) throw mapSupabaseError(error);
    const row = data?.[0];
    if (!row) throw new ServiceError("MEMBERSHIP_SESSION_NOT_FOUND");
    return {
      capacity: row.capacity,
      releasedCapacity: row.released_capacity,
      memberBookedCount: row.member_booked_count,
      guestBookedCount: row.guest_booked_count,
      unusedCapacity: row.unused_capacity,
      guestAvailableCapacity: row.guest_available_capacity,
    };
  }

  async bookMembershipSlot(batchId: string, sessionDate: string, memberId: string): Promise<MembershipSessionBooking> {
    const { data, error } = await this.supabase.rpc("book_membership_slot", {
      p_batch_id: batchId,
      p_session_date: sessionDate,
      p_member_id: memberId,
    });
    if (error) throw mapCapacityError(error);
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return toSessionBooking(data);
  }

  async releaseCapacity(sessionId: string, count: number): Promise<void> {
    const { error } = await this.supabase.rpc("release_membership_capacity", { p_session_id: sessionId, p_count: count });
    if (error) throw mapCapacityError(error);
  }

  async restoreCapacity(sessionId: string, count: number): Promise<void> {
    const { error } = await this.supabase.rpc("restore_membership_capacity", { p_session_id: sessionId, p_count: count });
    if (error) throw mapCapacityError(error);
  }

  async bookGuestSlot(batchId: string, sessionDate: string, guestPlayerId: string): Promise<MembershipSessionBooking> {
    const { data, error } = await this.supabase.rpc("book_guest_slot", {
      p_batch_id: batchId,
      p_session_date: sessionDate,
      p_guest_player_id: guestPlayerId,
    });
    if (error) throw mapCapacityError(error);
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return toSessionBooking(data);
  }

  async cancelSlotBooking(bookingId: string): Promise<void> {
    const { error } = await this.supabase.rpc("cancel_membership_slot_booking", { p_booking_id: bookingId });
    if (error) throw mapCapacityError(error);
  }

  async getSessionsSummary(facilityId: string): Promise<MembershipSessionsSummary> {
    const { data, error } = await this.supabase.rpc("get_membership_sessions_summary", { p_facility_id: facilityId });
    if (error) throw mapSupabaseError(error);
    const d = (data ?? {}) as Record<string, number>;
    return {
      totalSessions: d.totalSessions ?? 0,
      activeSessions: d.activeSessions ?? 0,
      todaysSessions: d.todaysSessions ?? 0,
      guestSlotsReleased: d.guestSlotsReleased ?? 0,
      avgUtilizationPct: d.avgUtilizationPct ?? 0,
    };
  }

  async listSessionsAdmin(facilityId: string, params: MembershipSessionListParams): Promise<MembershipSessionListResult> {
    const { data, error } = await this.supabase.rpc("list_membership_sessions_admin", {
      p_facility_id: facilityId,
      p_search: params.search?.trim() || null,
      p_facility_sport_id: params.facilitySportId ?? null,
      p_court_id: params.courtId ?? null,
      p_status: params.status ?? null,
      p_day: params.day ?? null,
      p_limit: params.perPage,
      p_offset: (params.page - 1) * params.perPage,
    });
    if (error) throw mapSupabaseError(error);
    const rows = (data ?? []).map((r) => ({
      batchId: r.batch_id,
      name: r.name,
      courtId: r.court_id,
      courtName: r.court_name,
      facilitySportId: r.facility_sport_id,
      sportName: r.sport_name,
      daysOfWeek: r.days_of_week ?? [],
      startTime: r.start_time,
      endTime: r.end_time,
      capacity: r.capacity,
      rosterCount: r.roster_count,
      releasedToday: r.released_today,
      guestBookedToday: r.guest_booked_today,
      utilizationPct: r.utilization_pct,
      status: r.status as MembershipSessionListResult["rows"][number]["status"],
      isActive: r.is_active,
    }));
    return { rows, totalCount: data?.[0]?.total_count ?? 0 };
  }

  async getSessionDetail(batchId: string): Promise<MembershipSessionDetail> {
    const { data, error } = await this.supabase.rpc("get_membership_session_detail", { p_batch_id: batchId });
    if (error) throw mapSupabaseError(error, { notFound: "MEMBERSHIP_BATCH_NOT_FOUND" });
    if (!data) throw new ServiceError("MEMBERSHIP_BATCH_NOT_FOUND");
    const d = data as Record<string, unknown>;
    return {
      batchId: d.batchId as string,
      facilityId: d.facilityId as string,
      facilityName: (d.facilityName as string) ?? null,
      facilityAddress: (d.facilityAddress as string) ?? null,
      name: d.name as string,
      notes: (d.notes as string) ?? null,
      courtId: d.courtId as string,
      courtName: d.courtName as string,
      facilitySportId: d.facilitySportId as string,
      sportName: d.sportName as string,
      planName: (d.planName as string) ?? null,
      daysOfWeek: (d.daysOfWeek as number[]) ?? [],
      startTime: d.startTime as string,
      endTime: d.endTime as string,
      capacity: d.capacity as number,
      isActive: d.isActive as boolean,
      createdByName: (d.createdByName as string) ?? null,
      createdAt: d.createdAt as string,
      updatedAt: d.updatedAt as string,
      rosterCount: d.rosterCount as number,
      guestsBookedToday: d.guestsBookedToday as number,
      releasedToday: d.releasedToday as number,
      availableToRelease: d.availableToRelease as number,
      runsToday: d.runsToday as boolean,
      nextOccurrenceDate: (d.nextOccurrenceDate as string) ?? null,
    };
  }

  async getSessionMembers(batchId: string): Promise<MembershipSessionMemberRow[]> {
    const { data, error } = await this.supabase.rpc("list_membership_session_members", { p_batch_id: batchId });
    if (error) throw mapSupabaseError(error);
    return (data ?? []).map((r) => ({
      id: r.id,
      memberId: r.member_id,
      fullName: r.full_name,
      phone: r.phone,
      status: r.status,
      addedOn: r.added_on,
    }));
  }

  async setSessionNotes(batchId: string, notes: string): Promise<void> {
    const { error } = await this.supabase.rpc("set_membership_batch_notes", { p_batch_id: batchId, p_notes: notes });
    if (error) throw mapCapacityError(error);
  }

  async listOccurrences(batchId: string, days = 30): Promise<MembershipSessionOccurrence[]> {
    const { data, error } = await this.supabase.rpc("list_membership_session_occurrences", { p_batch_id: batchId, p_days: days });
    if (error) throw mapSupabaseError(error);
    return (data ?? []).map((r) => ({
      occurrenceDate: r.occurrence_date,
      isBlocked: r.is_blocked,
      blockReason: r.block_reason ?? null,
      materialized: r.materialized,
      memberCount: r.member_count,
      guestCount: r.guest_count,
      releasedCapacity: r.released_capacity,
    }));
  }

  async listSessionBookings(batchId: string, limit = 50): Promise<MembershipSessionBookingRow[]> {
    const { data, error } = await this.supabase.rpc("list_membership_session_bookings", { p_batch_id: batchId, p_limit: limit });
    if (error) throw mapSupabaseError(error);
    return (data ?? []).map((r) => ({
      bookingId: r.booking_id,
      sessionDate: r.session_date,
      participantType: r.participant_type as "MEMBER" | "GUEST",
      participantName: r.participant_name,
      slotSource: r.slot_source as "MEMBERSHIP" | "RELEASED",
      status: r.status as "CONFIRMED" | "CANCELLED",
      amountMinor: r.amount_minor ?? null,
      createdAt: r.created_at,
    }));
  }

  async listSessionActivity(batchId: string, limit = 30): Promise<MembershipSessionActivity[]> {
    const { data, error } = await this.supabase.rpc("list_membership_session_activity", { p_batch_id: batchId, p_limit: limit });
    if (error) throw mapSupabaseError(error);
    return (data ?? []).map((r) => ({ kind: r.kind, actor: r.actor ?? null, detail: r.detail, at: r.at }));
  }

  async blockDate(batchId: string, date: string, reason?: string): Promise<void> {
    const { error } = await this.supabase.rpc("block_membership_batch_date", { p_batch_id: batchId, p_date: date, p_reason: reason ?? null });
    if (error) throw mapSupabaseError(error);
  }

  async unblockDate(batchId: string, date: string): Promise<void> {
    const { error } = await this.supabase.rpc("unblock_membership_batch_date", { p_batch_id: batchId, p_date: date });
    if (error) throw mapSupabaseError(error);
  }

  async duplicateSession(batchId: string, newName?: string): Promise<MembershipBatch> {
    const { data, error } = await this.supabase.rpc("duplicate_membership_batch", { p_batch_id: batchId, p_new_name: newName ?? null });
    if (error) throw mapSupabaseError(error, { notFound: "MEMBERSHIP_BATCH_NOT_FOUND" });
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return toBatch(data);
  }
}