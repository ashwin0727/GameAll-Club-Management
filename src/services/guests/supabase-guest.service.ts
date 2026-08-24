"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import type { Booking } from "@/features/bookings/types";
import type { GuestInput, GuestPlayer, GuestStats } from "@/features/guests/types";
import { toBooking } from "@/services/bookings/supabase-booking.service";
import type { GuestService } from "@/services/guests/guest.service";
import { ServiceError, mapSupabaseError } from "@/services/shared/service-error";
import type { Database } from "@/types/database.types";

type GuestRow = Database["public"]["Tables"]["guest_players"]["Row"];

function toGuest(row: GuestRow): GuestPlayer {
  return {
    id: row.id,
    facilityId: row.facility_id,
    name: row.name,
    phone: row.phone,
    email: row.email,
    notes: row.notes,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export class SupabaseGuestService implements GuestService {
  private readonly supabase: SupabaseClient<Database>;

  constructor(client?: SupabaseClient<Database>) {
    this.supabase = client ?? createClient();
  }

  async searchGuests(facilityId: string, query: string): Promise<GuestPlayer[]> {
    const trimmed = query.trim();
    if (trimmed.length < 2) return [];

    const { data, error } = await this.supabase
      .from("guest_players")
      .select("*")
      .eq("facility_id", facilityId)
      .or(`name.ilike.%${trimmed}%,phone.ilike.%${trimmed}%`)
      .order("name", { ascending: true })
      .limit(20);

    if (error) throw mapSupabaseError(error);
    return (data ?? []).map(toGuest);
  }

  async listGuests(
    facilityId: string,
    opts: { status?: "ACTIVE" | "INACTIVE"; limit?: number; offset?: number } = {},
  ): Promise<GuestPlayer[]> {
    const limit = opts.limit ?? 50;
    const offset = opts.offset ?? 0;
    let query = this.supabase.from("guest_players").select("*").eq("facility_id", facilityId);
    if (opts.status) query = query.eq("status", opts.status);
    const { data, error } = await query.order("updated_at", { ascending: false }).range(offset, offset + limit - 1);

    if (error) throw mapSupabaseError(error);
    return (data ?? []).map(toGuest);
  }

  async getGuest(guestId: string): Promise<GuestPlayer | null> {
    const { data, error } = await this.supabase.from("guest_players").select("*").eq("id", guestId).maybeSingle();
    if (error) throw mapSupabaseError(error);
    return data ? toGuest(data) : null;
  }

  async findOrCreateGuest(input: GuestInput): Promise<GuestPlayer> {
    const { data, error } = await this.supabase.rpc("find_or_create_guest", {
      p_facility_id: input.facilityId,
      p_name: input.name,
      p_phone: input.phone ?? null,
      p_email: input.email ?? null,
      p_notes: input.notes ?? null,
    });

    if (error) throw mapSupabaseError(error, { invalid: "INVALID_GUEST" });
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return toGuest(data);
  }

  async updateGuest(
    guestId: string,
    patch: Partial<GuestInput> & { status?: "ACTIVE" | "INACTIVE" },
  ): Promise<GuestPlayer> {
    const existing = await this.getGuest(guestId);
    if (!existing) throw new ServiceError("GUEST_NOT_FOUND");

    const { data, error } = await this.supabase.rpc("update_guest", {
      p_guest_id: guestId,
      p_name: patch.name ?? existing.name,
      p_phone: patch.phone !== undefined ? patch.phone : existing.phone,
      p_email: patch.email !== undefined ? patch.email : existing.email,
      p_notes: patch.notes !== undefined ? patch.notes : existing.notes,
      p_status: patch.status ?? existing.status,
    });

    if (error) throw mapSupabaseError(error, { invalid: "INVALID_GUEST", notFound: "GUEST_NOT_FOUND" });
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return toGuest(data);
  }

  async getGuestStats(guestId: string): Promise<GuestStats> {
    const { data, error } = await this.supabase.rpc("get_guest_stats", { p_guest_id: guestId });
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

  async getGuestBookings(guestId: string, opts: { limit?: number; offset?: number } = {}): Promise<Booking[]> {
    const limit = opts.limit ?? 20;
    const offset = opts.offset ?? 0;
    const { data, error } = await this.supabase
      .from("bookings")
      .select("*")
      .eq("guest_player_id", guestId)
      .order("start_time", { ascending: false })
      .range(offset, offset + limit - 1);

    if (error) throw mapSupabaseError(error);
    return (data ?? []).map(toBooking);
  }
}