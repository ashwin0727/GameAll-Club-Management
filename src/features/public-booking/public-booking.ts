import { createClient } from "@/lib/supabase/client";
import type {
  PublicBookingConfirmation,
  PublicBookingCourt,
  PublicBookingFacility,
  PublicGuestDetails,
} from "./types";

/**
 * Data access for the public booking flow. Reads go through anon-callable
 * SECURITY DEFINER RPCs (migration 0042) — the browser never selects from a
 * table directly, so RLS stays closed and the guest sees only what those
 * functions choose to return. The write goes through the public-guest-booking
 * Edge Function (0065), which rate-limits by IP + phone and optionally
 * verifies a CAPTCHA before calling the same booking RPC.
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

  const { data, error } = await supabase.functions.invoke<PublicBookingConfirmation & { error?: string; code?: string }>(
    "public-guest-booking",
    {
      body: {
        facilityId: input.facilityId,
        courtId: input.courtId,
        startTime: input.startTime,
        endTime: input.endTime,
        name: guest.fullName.trim(),
        phone: guest.phone.trim(),
        email: guest.email.trim() || null,
        purpose: guest.purpose || null,
        notes: notes || null,
        partySize: input.partySize ?? 1,
      },
    },
  );

  if (error) {
    // A non-2xx from the function — read the JSON body it returned. The
    // function speaks in the same friendly sentences the RPC did (0042/0065);
    // anything else is an internal fault and must not reach the screen.
    let payload: { error?: string; code?: string } = {};
    try {
      payload = await (error as { context?: Response }).context?.json?.() ?? {};
    } catch {
      // keep payload empty
    }
    const message = payload.error ?? "";
    if (payload.code === "SLOT_UNAVAILABLE" || message.toLowerCase().includes("no longer available")) {
      throw new SlotUnavailableError();
    }
    if (
      message.startsWith("Please ") ||
      message.startsWith("We could not") ||
      message.startsWith("You have unpaid") ||
      message.startsWith("That time has") ||
      message.startsWith("Too many booking")
    ) {
      throw new Error(message);
    }
    throw new Error("Something went wrong. Please try again.");
  }

  if (data && "error" in data && data.error) {
    throw new Error("Something went wrong. Please try again.");
  }
  if (!data?.bookingId) throw new Error("Something went wrong. Please try again.");
  return data as PublicBookingConfirmation;
}
