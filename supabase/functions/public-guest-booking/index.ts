// ═══════════════════════════════════════════════════════════════════════════
// public-guest-booking — the ONLY write path for the anonymous
// /book/<facilityId> flow (Public Booking Hardening, 0065).
//
// The browser used to call the public_create_guest_booking RPC directly.
// That gave the database no client IP, no place to verify a CAPTCHA, and no
// rate limit — a script could confirm-book a whole facility. This function
// sits in front of that RPC:
//
//   1. derives the real client IP (x-forwarded-for) and hashes it with a
//      salt — a raw IP is never stored;
//   2. optionally verifies a Cloudflare Turnstile token (only when
//      TURNSTILE_SECRET is configured — wired but dormant until then);
//   3. calls record_and_check_public_booking_attempt (logs + window limits);
//   4. calls public_create_guest_booking under a plain anon client — this
//      function holds no service-role key and gains no privilege the RPC's
//      own SECURITY DEFINER body doesn't already grant anon.
//
// Response shape and error messages mirror what the browser previously got
// straight from the RPC, so the client only has to swap .rpc() for
// .functions.invoke().
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface BookingRequest {
  facilityId: string;
  courtId: string;
  startTime: string;
  endTime: string;
  name: string;
  phone: string;
  email?: string | null;
  purpose?: string | null;
  notes?: string | null;
  partySize?: number;
  captchaToken?: string;
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } });
}

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function verifyTurnstile(token: string, secret: string, ip: string): Promise<boolean> {
  try {
    const form = new URLSearchParams({ secret, response: token });
    if (ip) form.set("remoteip", ip);
    const res = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: form,
    });
    const body = await res.json();
    return body?.success === true;
  } catch (err) {
    console.error("[public-guest-booking] Turnstile verification error", { error: String(err) });
    return false;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const turnstileSecret = Deno.env.get("TURNSTILE_SECRET");
  const ipSalt = Deno.env.get("PUBLIC_BOOKING_IP_SALT") ?? "";

  if (!supabaseUrl || !supabaseAnonKey) {
    console.error("[public-guest-booking] missing SUPABASE_URL/SUPABASE_ANON_KEY function secrets");
    return jsonResponse({ error: "Bookings are temporarily unavailable. Please try again later." }, 500);
  }

  let body: BookingRequest;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid request body." }, 400);
  }
  if (!body.facilityId || !body.courtId || !body.startTime || !body.endTime || !body.name || !body.phone) {
    return jsonResponse({ error: "Missing booking details." }, 400);
  }

  const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim();
  const ipHash = ip ? await sha256Hex(ip + ipSalt) : "";
  const phoneDigits = body.phone.replace(/\D/g, "");

  // CAPTCHA is enforced only once a secret is configured — until then the
  // rate limit is the sole gate.
  if (turnstileSecret) {
    if (!body.captchaToken || !(await verifyTurnstile(body.captchaToken, turnstileSecret, ip))) {
      return jsonResponse({ error: "Please complete the verification and try again." }, 403);
    }
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey);

  const { error: rateError } = await supabase.rpc("record_and_check_public_booking_attempt", {
    p_facility_id: body.facilityId,
    p_ip_hash: ipHash,
    p_phone_digits: phoneDigits,
  });
  if (rateError) {
    if (rateError.code === "P0001") {
      return jsonResponse({ error: rateError.message }, 429);
    }
    console.error("[public-guest-booking] rate-limit check failed", { code: rateError.code, message: rateError.message });
    return jsonResponse({ error: "Bookings are temporarily unavailable. Please try again later." }, 500);
  }

  const { data, error } = await supabase.rpc("public_create_guest_booking", {
    p_facility_id: body.facilityId,
    p_court_id: body.courtId,
    p_start_time: body.startTime,
    p_end_time: body.endTime,
    p_name: body.name.trim(),
    p_phone: body.phone.trim(),
    p_email: body.email?.trim() || null,
    p_purpose: body.purpose || null,
    p_notes: body.notes || null,
    p_party_size: body.partySize ?? 1,
  });

  if (error) {
    const message = error.message ?? "";
    if (message.toLowerCase().includes("no longer available")) {
      return jsonResponse({ error: message, code: "SLOT_UNAVAILABLE" }, 409);
    }
    if (message.startsWith("Please ") || message.startsWith("We could not") || message.startsWith("You have unpaid") || message.startsWith("That time has")) {
      return jsonResponse({ error: message }, 400);
    }
    console.error("[public-guest-booking] public_create_guest_booking failed", { code: error.code, message });
    return jsonResponse({ error: "Something went wrong. Please try again." }, 500);
  }

  if (!data?.bookingId) {
    return jsonResponse({ error: "Something went wrong. Please try again." }, 500);
  }

  return jsonResponse(data, 200);
});
