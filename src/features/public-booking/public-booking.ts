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
  // Court time held for an advance that never arrived goes back on sale before availability is read.
  await supabase.rpc("release_expired_booking_holds" as never).then(() => undefined, () => undefined);
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

export class HoldExpiredError extends Error {
  constructor() {
    super("That booking has expired. Please book again.");
    this.name = "HoldExpiredError";
  }
}

/** What the confirmation page and the invoice show for one booking. Money is in minor units (paise). */
export interface PublicBookingReceipt {
  found: boolean;
  bookingId: string;
  code: string;
  confirmed: boolean;
  cancelled: boolean;
  holdExpiresAt: string | null;
  facilityName: string;
  sportName: string;
  courtName: string;
  startTime: string;
  endTime: string;
  guestName: string;
  guestPhone: string;
  partySize: number;
  currency: string;
  amountMinor: number;
  paidMinor: number;
  outstandingMinor: number;
  paymentStatus: "PAID" | "PARTIALLY_PAID" | "PENDING";
  paymentMethod: string | null;
  paymentReference: string | null;
  paidAt: string | null;
}

/** Public: the booking's details and how much of it is paid. Needs the phone number the booking was made with. */
export async function getPublicBookingReceipt(bookingId: string, phone: string): Promise<PublicBookingReceipt | null> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("public_booking_receipt" as never, { p_booking_id: bookingId, p_phone: phone } as never);
  const d = data as unknown as (Partial<PublicBookingReceipt> & { found?: boolean }) | null;
  if (error || !d || !d.found) return null;
  return d as PublicBookingReceipt;
}

async function readFunctionError(error: unknown): Promise<{ error?: string; code?: string }> {
  try {
    return (await (error as { context?: Response }).context?.json?.()) ?? {};
  } catch {
    return {};
  }
}

export interface PublicCheckout {
  /** Already paid and confirmed — nothing more to pay. */
  paid?: boolean;
  keyId?: string;
  razorpayOrderId?: string;
  amount?: number;
  currency?: string;
  paymentOrderId?: string;
  receipt?: string;
}

/**
 * Public: start the 50% advance for every held booking in ONE payment. Returns what Razorpay Checkout needs to open —
 * the amount is decided on the server from the bookings, never sent from here.
 */
export async function createPublicCheckout(input: { bookingIds: string[]; phone: string }): Promise<PublicCheckout> {
  const supabase = createClient();
  const { data, error } = await supabase.functions.invoke<PublicCheckout & { error?: string }>("public-booking-checkout", {
    body: { action: "create", bookingIds: input.bookingIds, phone: input.phone },
  });
  if (error) {
    const payload = await readFunctionError(error);
    if (payload.code === "HOLD_EXPIRED") throw new HoldExpiredError();
    throw new Error(payload.error ?? "We couldn't start the payment. Please try again.");
  }
  if (!data || (!data.paid && !(data.razorpayOrderId && data.keyId))) throw new Error("We couldn't start the payment. Please try again.");
  return data;
}

/** Public: hand the server the Checkout result to verify; it confirms the booking only once Razorpay agrees. */
export async function verifyPublicCheckout(input: {
  bookingIds: string[];
  phone: string;
  paymentOrderId: string;
  razorpayOrderId: string;
  razorpayPaymentId: string;
  razorpaySignature: string;
}): Promise<{ confirmed: boolean }> {
  const supabase = createClient();
  const { data, error } = await supabase.functions.invoke<{ confirmed?: boolean; error?: string }>("public-booking-checkout", {
    body: { action: "verify", ...input },
  });
  if (error) {
    const payload = await readFunctionError(error);
    throw new Error(payload.error ?? "We couldn't verify that payment. Please contact the venue.");
  }
  return { confirmed: data?.confirmed === true };
}

/** Public: the booking's invoice as a PDF, saved by the browser. */
export async function downloadPublicBookingInvoice(bookingId: string, phone: string, fileName: string): Promise<void> {
  const supabase = createClient();
  const { data, error } = await supabase.functions.invoke("public-booking-checkout", {
    body: { action: "invoice", bookingId, phone },
  });
  if (error || !(data instanceof Blob)) throw new Error("We couldn't build the invoice. Please try again.");
  const url = URL.createObjectURL(data);
  const a = document.createElement("a");
  a.href = url;
  a.download = fileName;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
