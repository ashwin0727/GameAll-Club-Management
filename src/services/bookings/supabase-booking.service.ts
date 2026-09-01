"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import type {
  Booking,
  BookingStatus,
  GuestBookingListParams,
  GuestBookingListResult,
  GuestBookingsSummary,
  NewBookingInput,
  PaymentStatus,
  RescheduleBookingInput,
} from "@/features/bookings/types";
import type { BookingService } from "@/services/bookings/booking.service";
import { ServiceError, mapSupabaseError } from "@/services/shared/service-error";
import type { Database } from "@/types/database.types";

type BookingRow = Database["public"]["Tables"]["bookings"]["Row"];

export function toBooking(row: BookingRow): Booking {
  return {
    id: row.id,
    facilityId: row.facility_id,
    courtId: row.court_id,
    facilitySportId: row.facility_sport_id,
    memberId: row.member_id,
    customerType: row.customer_type,
    guestPlayerId: row.guest_player_id,
    guestName: row.guest_name,
    guestPhone: row.guest_phone,
    startTime: row.start_time,
    endTime: row.end_time,
    status: row.status,
    amountMinor: row.amount_minor,
    currency: row.currency,
    paymentStatus: row.payment_status,
    cancellationReason: row.cancellation_reason,
    notes: row.notes,
    partySize: row.party_size ?? 1,
    paymentMethod: row.payment_method,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export class SupabaseBookingService implements BookingService {
  private readonly supabase: SupabaseClient<Database>;

  constructor(client?: SupabaseClient<Database>) {
    this.supabase = client ?? createClient();
  }

  async getBookingsForCourtOnDate(courtId: string, date: Date): Promise<Booking[]> {
    const dayStart = new Date(date);
    dayStart.setHours(0, 0, 0, 0);
    const dayEnd = new Date(dayStart);
    dayEnd.setDate(dayEnd.getDate() + 1);

    const { data, error } = await this.supabase
      .from("bookings")
      .select("*")
      .eq("court_id", courtId)
      .in("status", ["pending", "confirmed"])
      .gte("start_time", dayStart.toISOString())
      .lt("start_time", dayEnd.toISOString())
      .order("start_time", { ascending: true });

    if (error) throw mapSupabaseError(error);
    return (data ?? []).map(toBooking);
  }

  async getBookingsForFacility(facilityId: string, from: Date, to: Date): Promise<Booking[]> {
    const { data, error } = await this.supabase
      .from("bookings")
      .select("*")
      .eq("facility_id", facilityId)
      .gte("start_time", from.toISOString())
      .lt("start_time", to.toISOString())
      .order("start_time", { ascending: true });

    if (error) throw mapSupabaseError(error);
    return (data ?? []).map(toBooking);
  }

  async createBooking(input: NewBookingInput): Promise<Booking> {
    const { data, error } = await this.supabase.rpc("create_booking", {
      p_facility_id: input.facilityId,
      p_court_id: input.courtId,
      p_start_time: input.startTime,
      p_end_time: input.endTime,
      p_customer_type: input.customerType,
      p_member_id: input.memberId ?? null,
      p_guest_name: input.guestName ?? null,
      p_guest_phone: input.guestPhone ?? null,
      p_notes: input.notes ?? null,
      p_payment_status: input.paymentStatus ?? "PENDING",
      p_guest_player_id: input.guestPlayerId ?? null,
      p_party_size: input.partySize ?? 1,
      p_payment_method: input.paymentMethod ?? null,
    });

    if (error) throw mapSupabaseError(error, { notFound: "COURT_NOT_FOUND", invalid: "INVALID_BOOKING" });
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return toBooking(data);
  }

  async getBooking(bookingId: string): Promise<Booking | null> {
    const { data, error } = await this.supabase.from("bookings").select("*").eq("id", bookingId).maybeSingle();
    if (error) throw mapSupabaseError(error);
    return data ? toBooking(data) : null;
  }

  async updateGuestBooking(
    bookingId: string,
    patch: { guestName: string; guestPhone?: string | null; partySize: number; notes?: string | null },
  ): Promise<Booking> {
    const { data, error } = await this.supabase.rpc("update_guest_booking", {
      p_booking_id: bookingId,
      p_guest_name: patch.guestName,
      p_guest_phone: patch.guestPhone ?? null,
      p_party_size: patch.partySize,
      p_notes: patch.notes ?? null,
    });
    if (error) throw mapSupabaseError(error, { notFound: "BOOKING_NOT_FOUND", invalid: "INVALID_BOOKING" });
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return toBooking(data);
  }

  async completeGuestBooking(bookingId: string): Promise<Booking> {
    const { data, error } = await this.supabase.rpc("complete_guest_booking", { p_booking_id: bookingId });
    if (error) throw mapSupabaseError(error, { notFound: "BOOKING_NOT_FOUND", invalid: "INVALID_BOOKING" });
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return toBooking(data);
  }

  async recordGuestBookingPayment(bookingId: string, method: string, amountMinor: number): Promise<Booking> {
    const { data, error } = await this.supabase.rpc("record_guest_booking_payment", {
      p_booking_id: bookingId,
      p_method: method,
      p_amount_minor: amountMinor,
    });
    if (error) throw mapSupabaseError(error, { notFound: "BOOKING_NOT_FOUND", invalid: "INVALID_BOOKING" });
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return toBooking(data);
  }

  async duplicateGuestBooking(bookingId: string, newStart: string, newEnd: string): Promise<Booking> {
    const { data, error } = await this.supabase.rpc("duplicate_guest_booking", {
      p_booking_id: bookingId,
      p_new_start: newStart,
      p_new_end: newEnd,
    });
    if (error) throw mapSupabaseError(error, { notFound: "BOOKING_NOT_FOUND", invalid: "INVALID_BOOKING" });
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return toBooking(data);
  }

  async deleteGuestBooking(bookingId: string): Promise<void> {
    const { error } = await this.supabase.rpc("delete_guest_booking", { p_booking_id: bookingId });
    if (error) throw mapSupabaseError(error, { notFound: "BOOKING_NOT_FOUND", invalid: "INVALID_BOOKING" });
  }

  async sendBookingReceipt(bookingId: string, email: string): Promise<void> {
    const { data, error } = await this.supabase.functions.invoke<{ sent?: boolean; error?: string }>("send-booking-receipt", {
      body: { bookingId, email },
    });
    if (error || !data || "error" in data) {
      throw new ServiceError("DATABASE_ERROR", (data as { error?: string })?.error ?? "Could not send the receipt email.");
    }
  }

  async rescheduleBooking(input: RescheduleBookingInput): Promise<Booking> {
    const { data, error } = await this.supabase.rpc("reschedule_booking", {
      p_booking_id: input.bookingId,
      p_new_court_id: input.courtId,
      p_new_start_time: input.startTime,
      p_new_end_time: input.endTime,
    });

    if (error) throw mapSupabaseError(error, { notFound: "BOOKING_NOT_FOUND", invalid: "INVALID_BOOKING" });
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return toBooking(data);
  }

  async cancelBooking(bookingId: string, reason?: string): Promise<void> {
    const { data, error } = await this.supabase
      .from("bookings")
      .update({ status: "cancelled", cancellation_reason: reason ?? null })
      .eq("id", bookingId)
      .select("id")
      .maybeSingle();

    if (error) throw mapSupabaseError(error);
    if (!data) throw new ServiceError("BOOKING_NOT_FOUND");
  }

  async getGuestBookingsSummary(facilityId: string, from: string, to: string): Promise<GuestBookingsSummary> {
    const { data, error } = await this.supabase.rpc("get_guest_bookings_summary", {
      p_facility_id: facilityId,
      p_from: from,
      p_to: to,
    });
    if (error) throw mapSupabaseError(error);
    const d = (data ?? {}) as Record<string, unknown>;
    return {
      total: Number(d.total ?? 0),
      confirmed: Number(d.confirmed ?? 0),
      completed: Number(d.completed ?? 0),
      cancelled: Number(d.cancelled ?? 0),
      pending: Number(d.pending ?? 0),
      totalRevenueMinor: Number(d.totalRevenueMinor ?? 0),
      avgPerBookingMinor: Number(d.avgPerBookingMinor ?? 0),
      highestBookingMinor: Number(d.highestBookingMinor ?? 0),
      totalChangePct: d.totalChangePct == null ? null : Number(d.totalChangePct),
      revenueChangePct: d.revenueChangePct == null ? null : Number(d.revenueChangePct),
      trend: Array.isArray(d.trend)
        ? (d.trend as { date: string; amountMinor: number }[]).map((t) => ({ date: t.date, amountMinor: Number(t.amountMinor) }))
        : [],
    };
  }

  async listGuestBookings(facilityId: string, params: GuestBookingListParams): Promise<GuestBookingListResult> {
    const { data, error } = await this.supabase.rpc("list_guest_bookings_admin", {
      p_facility_id: facilityId,
      p_search: params.search?.trim() || null,
      p_facility_sport_id: params.facilitySportId ?? null,
      p_court_id: params.courtId ?? null,
      p_status: params.status ?? null,
      p_payment_status: params.paymentStatus ?? null,
      p_from: params.from ?? null,
      p_to: params.to ?? null,
      p_limit: params.perPage,
      p_offset: (params.page - 1) * params.perPage,
    });
    if (error) throw mapSupabaseError(error);
    const rows: GuestBookingListResult["rows"] = (data ?? []).map((r) => ({
      bookingId: r.booking_id,
      code: r.code,
      guestName: r.guest_name,
      guestPhone: r.guest_phone,
      sportName: r.sport_name,
      courtName: r.court_name,
      startTime: r.start_time,
      endTime: r.end_time,
      partySize: r.party_size,
      amountMinor: r.amount_minor,
      currency: r.currency,
      paymentStatus: r.payment_status as PaymentStatus,
      paymentMethod: r.payment_method,
      status: r.status as BookingStatus,
    }));
    return { rows, totalCount: data?.[0]?.total_count ?? 0 };
  }

  async searchMembers(facilityId: string, query: string): Promise<{ id: string; fullName: string; phone: string; email: string | null }[]> {
    const trimmed = query.trim();
    if (trimmed.length < 2) return [];

    const { data, error } = await this.supabase.rpc("search_members", { p_facility_id: facilityId, p_query: trimmed });
    if (error) throw mapSupabaseError(error);
    return (data ?? []).map((row) => ({ id: row.id, fullName: row.full_name, phone: row.phone, email: row.email }));
  }
}