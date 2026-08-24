"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import type { Booking, NewBookingInput, RescheduleBookingInput } from "@/features/bookings/types";
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
    });

    if (error) throw mapSupabaseError(error, { notFound: "COURT_NOT_FOUND", invalid: "INVALID_BOOKING" });
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return toBooking(data);
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

  async searchMembers(facilityId: string, query: string): Promise<{ id: string; fullName: string; phone: string; email: string | null }[]> {
    const trimmed = query.trim();
    if (trimmed.length < 2) return [];

    const { data, error } = await this.supabase.rpc("search_members", { p_facility_id: facilityId, p_query: trimmed });
    if (error) throw mapSupabaseError(error);
    return (data ?? []).map((row) => ({ id: row.id, fullName: row.full_name, phone: row.phone, email: row.email }));
  }
}