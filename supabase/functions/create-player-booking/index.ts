// ═══════════════════════════════════════════════════════════════════════════
// create-player-booking — "Book Now" on the Player app's Guest Booking page, for a SIGNED-IN player.
//
// The public /book/<venue> page is for anonymous guests: it makes them verify their mobile number by SMS (public-guest-booking).
// A signed-in player has already done that when they signed in (their phone IS their login), so this is the same booking, made
// for them without asking again:
//
//   1. who is asking: the caller's own session → get_my_player() gives their name and verified phone — never read from the request;
//   2. the same abuse limit the public page has (record_and_check_public_booking_attempt);
//   3. public_create_guest_booking — the one routine that makes a guest booking (a booking over an hour is held PENDING for 30
//      minutes until its 50% advance is paid; shorter ones are confirmed and paid at the venue or online);
//   4. answers { bookingId, ... }; the app then asks create-player-booking-payment-link for the Razorpay page to pay on.
//
// Identity comes from the caller's JWT; the booking itself is made with the anon key, like the public page (a signed-in session would hit
// the staff page-access check). No service role is held.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } });
}

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return jsonResponse({ error: "Please sign in to book." }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const ipSalt = Deno.env.get("PUBLIC_BOOKING_IP_SALT") ?? "";
  if (!supabaseUrl || !anonKey) {
    console.error("[create-player-booking] missing SUPABASE_URL/SUPABASE_ANON_KEY function secrets");
    return jsonResponse({ error: "Bookings are temporarily unavailable. Please try again later." }, 500);
  }

  let body: { facilityId?: string; courtId?: string; startTime?: string; endTime?: string; partySize?: number };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid request body." }, 400);
  }
  if (!body.facilityId || !body.courtId || !body.startTime || !body.endTime) {
    return jsonResponse({ error: "Missing booking details." }, 400);
  }

  const asPlayer = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });

  // 1 · who is asking
  const { data: me, error: meErr } = await asPlayer.rpc("get_my_player");
  const player = (Array.isArray(me) ? me[0] : me) as { full_name?: string; fullName?: string; phone?: string } | null;
  const name = (player?.full_name ?? player?.fullName ?? "").trim();
  const phone = (player?.phone ?? "").trim();
  if (meErr || !name || !phone) return jsonResponse({ error: "Please sign in to book." }, 401);

  // From here on the call is made exactly as the public page makes it (a plain anon client): the booking routines enforce staff
  // page access for any signed-in user (require_page_access_any), which a player is not. Who the booking is for was settled above,
  // from the caller's own session, so nothing the app sends can change it.
  const asGuest = createClient(supabaseUrl, anonKey);

  // 2 · the public page's rate limit
  const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim();
  const ipHash = ip ? await sha256Hex(ip + ipSalt) : "";
  const { error: rateError } = await asGuest.rpc("record_and_check_public_booking_attempt", {
    p_facility_id: body.facilityId,
    p_ip_hash: ipHash,
    p_phone_digits: phone.replace(/\D/g, ""),
  });
  if (rateError) {
    if (rateError.code === "P0001") return jsonResponse({ error: rateError.message }, 429);
    console.error("[create-player-booking] rate-limit check failed", { code: rateError.code, message: rateError.message });
    return jsonResponse({ error: "Bookings are temporarily unavailable. Please try again later." }, 500);
  }

  // 3 · the booking
  const { data, error } = await asGuest.rpc("public_create_guest_booking", {
    p_facility_id: body.facilityId,
    p_court_id: body.courtId,
    p_start_time: body.startTime,
    p_end_time: body.endTime,
    p_name: name,
    p_phone: phone,
    p_email: null,
    p_purpose: null,
    p_notes: null,
    p_party_size: Math.max(1, Math.min(body.partySize ?? 1, 50)),
  });
  if (error) {
    const message = error.message ?? "";
    if (message.toLowerCase().includes("no longer available")) return jsonResponse({ error: message, code: "SLOT_UNAVAILABLE" }, 409);
    if (message.startsWith("Please ") || message.startsWith("We could not") || message.startsWith("You have unpaid") || message.startsWith("That time has")) {
      return jsonResponse({ error: message }, 400);
    }
    console.error("[create-player-booking] public_create_guest_booking failed", { code: error.code, message });
    return jsonResponse({ error: "Something went wrong. Please try again." }, 500);
  }
  if (!data?.bookingId) return jsonResponse({ error: "Something went wrong. Please try again." }, 500);

  return jsonResponse(data, 200);
});
