import { createClient } from "@/lib/supabase/client";
import type {
  PublicBookingConfirmation,
  PublicBookingCourt,
  PublicBookingFacility,
  PublicGuestDetails,
} from "./types";

/**
 * Data access for the public booking flow. Every call goes through an
 * anon-callable SECURITY DEFINER RPC (migration 0042) — the browser never
 * selects from a table directly, so RLS stays closed and the guest sees only
 * what those functions choose to return.
 *
 * Server errors are never surfaced verbatim; each function maps failures to
 * a message a player can act on.
 */

/** Public: the venue and the sports it offers. `null` when the link is bad. */
export async function getPublicBookingFacility(facilityId: string): Promise<PublicBookingFacility | null> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_public_booking_facility", { p_facility_id: facilityId });
  if (error || !data || !data.facilityId) return null;
  return {
    facilityId: data.facilityId,
    facilityName: data.facilityName,
    city: data.city ?? "",
    currency: data.currency ?? "INR",
    helpPhone: data.helpPhone ?? null,
    logoUrl: data.logoUrl ?? null,
    heroImageUrl: data.heroImageUrl ?? null,
    sports: data.sports ?? [],
  };
}

/**
 * Public: bookable slots per court for one sport on one date.
 *
 * This is the server's answer, not the browser's — availability accounts for
 * existing bookings, court operating hours, membership-protected capacity and
 * any capacity the owner released for guest play.
 */
export async function getPublicCourtAvailability(
  facilityId: string,
  facilitySportId: string,
  date: string,
): Promise<PublicBookingCourt[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_public_court_availability", {
    p_facility_id: facilityId,
    p_facility_sport_id: facilitySportId,
    p_date: date,
  });
  if (error || !Array.isArray(data)) return [];
  return data as PublicBookingCourt[];
}

export class SlotUnavailableError extends Error {
  constructor() {
    super("Sorry, this court is no longer available.");
    this.name = "SlotUnavailableError";
  }
}

/**
 * Public: create the booking.
 *
 * The server re-checks availability at write time and rejects the loser of a
 * race for the last slot, so a stale view in the browser cannot double-book.
 * That specific failure is raised as [SlotUnavailableError] so the caller can
 * send the player back to slot selection rather than showing a dead end.
 */
export async function createPublicGuestBooking(input: {
  facilityId: string;
  courtId: string;
  startTime: string;
  endTime: string;
  guest: PublicGuestDetails;
  partySize?: number;
}): Promise<PublicBookingConfirmation> {
  const supabase = createClient();
  const { guest } = input;

  const notes = [
    guest.specialRequest.trim(),
    guest.altPhone.trim() ? `Alt phone: ${guest.altPhone.trim()}` : "",
    guest.address.trim() ? `Address: ${guest.address.trim()}` : "",
  ]
    .filter(Boolean)
    .join(" | ");

  const { data, error } = await supabase.rpc("public_create_guest_booking", {
    p_facility_id: input.facilityId,
    p_court_id: input.courtId,
    p_start_time: input.startTime,
    p_end_time: input.endTime,
    p_name: guest.fullName.trim(),
    p_phone: guest.phone.trim(),
    p_email: guest.email.trim() || null,
    p_purpose: guest.purpose || null,
    p_notes: notes || null,
    p_party_size: input.partySize ?? 1,
  });

  if (error) {
    // The database speaks in friendly sentences for the cases a player can
    // act on (see 0042); anything else is an internal fault and must not
    // reach the screen.
    if (error.message?.toLowerCase().includes("no longer available")) {
      throw new SlotUnavailableError();
    }
    if (error.message?.startsWith("Please ") || error.message?.startsWith("We could not")) {
      throw new Error(error.message);
    }
    throw new Error("Something went wrong. Please try again.");
  }

  if (!data?.bookingId) throw new Error("Something went wrong. Please try again.");
  return data as PublicBookingConfirmation;
}
