// ═══════════════════════════════════════════════════════════════════════════
// player-login — sign a Player-app user in from their phone number, WITHOUT a one-time code (switchable).
//
// POST JSON { phone }
//   → { ok: true, mode: "otp" }                                    the code step is switched on: the app sends a code instead
//   → { ok: true, mode: "open", refreshToken, accessToken, hasPlayer, knownName, clubRecords }
//                                                                  signed in; the app finishes with the profile step if needed
//
// How: finds or creates the auth user for the number (marked as a confirmed phone), gives it a password that only this function can
// compute (an HMAC of the number under PLAYER_LOGIN_SECRET), signs in with it on the server and hands the session to the app. The
// password never leaves this function.
//
// WARNING: with no code, anyone who types a number is signed in as that number's player and sees its memberships, coaching and
// bookings. To turn the code step back on, set PLAYER_OTP_REQUIRED=true (and keep the Send SMS hook function deployed); no app change.
// Protection while open: Indian mobiles only, and at most 30 attempts per hour per address.
//
// Secrets: PLAYER_LOGIN_SECRET (any long random string), optional PLAYER_OTP_REQUIRED ("true"), optional PUBLIC_BOOKING_IP_SALT.
// Deploy: supabase functions deploy player-login --no-verify-jwt
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { tenDigitMobile } from "../_shared/send-sms-hook.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const MAX_ATTEMPTS_PER_HOUR = 30;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json", "Cache-Control": "no-store" } });
}
const fail = (code: string, message: string, status = 400) => json({ ok: false, code, message }, status);

async function hmacHex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return fail("method", "Method not allowed", 405);

  let body: { phone?: unknown };
  try {
    body = await req.json();
  } catch {
    return fail("bad_request", "Invalid request.");
  }
  const phone = tenDigitMobile(String(body.phone ?? ""));
  if (!phone) return fail("bad_phone", "Please enter a valid Indian mobile number.");

  // Code step switched on: nothing to do here, the app sends a code.
  if ((Deno.env.get("PLAYER_OTP_REQUIRED") ?? "").toLowerCase() === "true") return json({ ok: true, mode: "otp" });

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const secret = Deno.env.get("PLAYER_LOGIN_SECRET");
  if (!url || !serviceKey || !anonKey || !secret) return fail("not_configured", "Sign in is not available yet.", 500);

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  // A flood from one address (someone trying many numbers) is stopped.
  const ip = (req.headers.get("x-forwarded-for") ?? req.headers.get("cf-connecting-ip") ?? "unknown").split(",")[0].trim();
  const ipHash = await hmacHex(Deno.env.get("PUBLIC_BOOKING_IP_SALT") || secret, `ip:${ip}`);
  const { data: attempts } = await admin.rpc("player_login_record_attempt", { p_ip_hash: ipHash, p_phone: phone });
  if (typeof attempts === "number" && attempts > MAX_ATTEMPTS_PER_HOUR) return fail("rate_limited", "Too many attempts. Please try again later.", 429);

  const { data: lookup, error: lookupError } = await admin.rpc("player_login_lookup", { p_phone: phone });
  if (lookupError || !lookup) {
    console.error("player-login: lookup failed", lookupError?.code);
    return fail("lookup", "We couldn't sign you in right now. Please try again.", 500);
  }

  const authPhone = `91${phone}`;
  const password = await hmacHex(secret, `player-login:${authPhone}`);
  if (lookup.userId) {
    // Already has an account (earlier login, or created with a code): make sure it is a confirmed phone with our password.
    const { error } = await admin.auth.admin.updateUserById(lookup.userId, { password, phone: authPhone, phone_confirm: true });
    if (error) {
      console.error("player-login: update failed", error.message);
      return fail("update", "We couldn't sign you in right now. Please try again.", 500);
    }
  } else {
    const { error } = await admin.auth.admin.createUser({ phone: authPhone, phone_confirm: true, password });
    if (error) {
      console.error("player-login: create failed", error.message);
      return fail("create", "We couldn't sign you in right now. Please try again.", 500);
    }
  }

  const anon = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: signedIn, error: signInError } = await anon.auth.signInWithPassword({ phone: authPhone, password });
  if (signInError || !signedIn.session) {
    console.error("player-login: sign-in failed", signInError?.message);
    return fail("sign_in", "We couldn't sign you in right now. Please try again.", 500);
  }

  return json({
    ok: true,
    mode: "open",
    accessToken: signedIn.session.access_token,
    refreshToken: signedIn.session.refresh_token,
    hasPlayer: lookup.hasPlayer === true,
    knownName: lookup.knownName ?? null,
    clubRecords: Number(lookup.clubRecords ?? 0),
  });
});
