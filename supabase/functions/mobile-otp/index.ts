// ═══════════════════════════════════════════════════════════════════════════
// mobile-otp — SMS one-time-password verification of a mobile number (2Factor.in).
//
// POST JSON { action, phone, purpose, code? }
//   action  "send" | "verify"
//   purpose "signup"  — a signed-in new owner verifying their own number (needs the caller's JWT). On success the number
//                       is recorded in user_verified_phones and copied to profiles.phone.
//           "booking" — an anonymous guest on the public /book page. On success returns a short-lived signed `proof`
//                       that public-guest-booking requires before it will create the booking.
//
// Security: CSPRNG code, only an HMAC of it is stored (mobile_otps, service-role only), 10-minute expiry, single use,
// 5 wrong tries then the code is cancelled, 30 s resend cooldown, 5 SMS/hour/number and 10 SMS/hour/IP (so nobody can
// use the endpoint to text arbitrary numbers). The 2Factor key never leaves this function.
//
// Secrets: TWOFACTOR_API_KEY, SIGNUP_OTP_SECRET (shared with signup-otp — also signs booking proofs), optional
// TWOFACTOR_TEMPLATE_NAME (a DLT-approved template; omit to use 2Factor's default OTP route), optional
// PUBLIC_BOOKING_IP_SALT (shared with public-guest-booking).
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { MAX_SENDS_PER_HOUR, MAX_VERIFY_ATTEMPTS, OTP_TTL_MINUTES, RESEND_COOLDOWN_SECONDS, generateOtp, safeEqual } from "../_shared/signup-otp.ts";
import { hashMobileOtp, issueMobileProof, normalizeIndianMobile, sendSms } from "../_shared/mobile-otp.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const MAX_SENDS_PER_IP_HOUR = 10;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json", "Cache-Control": "no-store" } });
}
const fail = (code: string, message: string, status = 400) => json({ ok: false, code, message }, status);

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return fail("method", "Method not allowed", 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const smsKey = Deno.env.get("TWOFACTOR_API_KEY");
  const secret = Deno.env.get("SIGNUP_OTP_SECRET");
  const template = Deno.env.get("TWOFACTOR_TEMPLATE_NAME") || undefined;
  const ipSalt = Deno.env.get("PUBLIC_BOOKING_IP_SALT") ?? "";
  if (!supabaseUrl || !serviceKey || !anonKey || !smsKey || !secret) return fail("not_configured", "Mobile verification is not configured yet.", 500);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return fail("bad_request", "Invalid request body.");
  }
  const action = String(body.action ?? "");
  const purpose = String(body.purpose ?? "");
  if (purpose !== "signup" && purpose !== "booking") return fail("bad_request", "Unknown purpose.");
  const phone = normalizeIndianMobile(String(body.phone ?? ""));
  if (!phone) return fail("invalid_phone", "Enter a valid 10-digit mobile number.");

  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  // Signup verification belongs to a signed-in account; booking verification is anonymous.
  let userId: string | null = null;
  if (purpose === "signup") {
    const authHeader = req.headers.get("Authorization") ?? "";
    const caller = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } });
    const { data } = await caller.auth.getUser();
    userId = data.user?.id ?? null;
    if (!userId) return fail("unauthenticated", "Please sign in again to verify your mobile number.", 401);
  }

  try {
    if (action === "send") {
      const now = new Date();
      const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim();
      const ipHash = await sha256Hex(`${ip}${ipSalt}`);

      const { data: existing } = await admin.from("mobile_otps").select("*").eq("phone", phone).eq("purpose", purpose).maybeSingle();
      let sendCount = 1;
      let windowStart = now;
      if (existing) {
        const since = (now.getTime() - new Date(existing.last_sent_at).getTime()) / 1000;
        if (since < RESEND_COOLDOWN_SECONDS) return fail("cooldown", `Please wait ${Math.ceil(RESEND_COOLDOWN_SECONDS - since)}s before requesting another code.`, 429);
        if (now.getTime() - new Date(existing.window_start).getTime() < 3_600_000) {
          if (existing.send_count >= MAX_SENDS_PER_HOUR) return fail("rate_limited", "Too many codes requested for this number. Try again in an hour.", 429);
          sendCount = existing.send_count + 1;
          windowStart = new Date(existing.window_start);
        }
      }
      const { count } = await admin
        .from("mobile_otp_sends")
        .select("id", { count: "exact", head: true })
        .eq("ip_hash", ipHash)
        .gte("created_at", new Date(now.getTime() - 3_600_000).toISOString());
      if ((count ?? 0) >= MAX_SENDS_PER_IP_HOUR) return fail("rate_limited", "Too many codes requested. Try again later.", 429);

      const code = generateOtp();
      const { error: upsertError } = await admin.from("mobile_otps").upsert({
        phone,
        purpose,
        code_hash: await hashMobileOtp(phone, purpose, code, secret),
        expires_at: new Date(now.getTime() + OTP_TTL_MINUTES * 60_000).toISOString(),
        attempts: 0,
        send_count: sendCount,
        window_start: windowStart.toISOString(),
        last_sent_at: now.toISOString(),
      });
      if (upsertError) throw upsertError;

      if (!(await sendSms(phone, code, smsKey, template))) {
        await admin.from("mobile_otps").delete().eq("phone", phone).eq("purpose", purpose);
        return fail("send_failed", "We couldn't place the verification call. Please check the number and try again.", 502);
      }
      await admin.from("mobile_otp_sends").insert({ ip_hash: ipHash, phone });
      return json({ ok: true });
    }

    if (action === "verify") {
      const code = String(body.code ?? "").replace(/\s+/g, "");
      if (!/^\d{6}$/.test(code)) return fail("invalid_code", "Enter the 6-digit code.");

      const { data: row } = await admin.from("mobile_otps").select("*").eq("phone", phone).eq("purpose", purpose).maybeSingle();
      if (!row) return fail("invalid_code", "That code is incorrect or has expired. Request a new one.");
      if (new Date(row.expires_at).getTime() < Date.now()) {
        await admin.from("mobile_otps").delete().eq("phone", phone).eq("purpose", purpose);
        return fail("expired", "That code has expired. Request a new one.");
      }
      if (row.attempts >= MAX_VERIFY_ATTEMPTS) {
        await admin.from("mobile_otps").delete().eq("phone", phone).eq("purpose", purpose);
        return fail("locked", "Too many incorrect attempts. Request a new code.", 429);
      }
      if (!safeEqual(row.code_hash, await hashMobileOtp(phone, purpose, code, secret))) {
        await admin.from("mobile_otps").update({ attempts: row.attempts + 1 }).eq("phone", phone).eq("purpose", purpose);
        const left = MAX_VERIFY_ATTEMPTS - row.attempts - 1;
        return fail("invalid_code", left > 0 ? `Incorrect code. ${left} attempt${left === 1 ? "" : "s"} left.` : "Too many incorrect attempts. Request a new code.");
      }
      await admin.from("mobile_otps").delete().eq("phone", phone).eq("purpose", purpose); // single use

      if (purpose === "signup") {
        const { error } = await admin.from("user_verified_phones").upsert({ user_id: userId, phone, verified_at: new Date().toISOString() });
        if (error) throw error;
        await admin.from("profiles").update({ phone }).eq("id", userId!);
        return json({ ok: true });
      }
      return json({ ok: true, proof: await issueMobileProof(phone, secret) });
    }

    return fail("bad_request", "Unknown action.");
  } catch (e) {
    console.error("mobile-otp: unexpected error", e instanceof Error ? e.message : "unknown");
    return fail("server_error", "Something went wrong. Please try again.", 500);
  }
});
