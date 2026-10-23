// ═══════════════════════════════════════════════════════════════════════════
// signup-otp — email one-time-password verification for NEW owner accounts.
//
// Actions (POST JSON { action, ... }):
//   start   { name, email, password } → creates the auth user UNCONFIRMED (no Supabase email is sent), then emails a
//                                       6-digit code through Resend.
//   resend  { email }                 → issues a fresh code for a still-unconfirmed signup.
//   verify  { email, code }           → checks the code; on success marks the email confirmed so the client can sign in.
//
// Security: the code comes from the CSPRNG, only an HMAC of it is stored (signup_otps, service-role only), it expires
// in 10 minutes, is single-use, locks after 5 wrong tries, and sends are cooldown/hour-capped per address. The
// password is passed straight to Supabase Auth (which hashes it) and is never stored, logged or echoed by this function.
//
// Required secrets: RESEND_API_KEY, RESEND_FROM (e.g. "GameAll <no-reply@yourdomain.com>"), SIGNUP_OTP_SECRET (long
// random string), and SITE_URL (public site origin — hosts /logo-icon.png for the email) or SIGNUP_EMAIL_LOGO_URL.
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are always present. Supabase "Confirm email" must stay ON.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  MAX_SENDS_PER_HOUR,
  MAX_VERIFY_ATTEMPTS,
  OTP_TTL_MINUTES,
  RESEND_COOLDOWN_SECONDS,
  buildOtpEmail,
  generateOtp,
  hashOtp,
  safeEqual,
} from "../_shared/signup-otp.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json", "Cache-Control": "no-store" } });
}
const fail = (code: string, message: string, status = 400) => json({ ok: false, code, message }, status);

const EMAIL_RE = /^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$/;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return fail("method", "Method not allowed", 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resendKey = Deno.env.get("RESEND_API_KEY");
  const resendFrom = Deno.env.get("RESEND_FROM");
  const otpSecret = Deno.env.get("SIGNUP_OTP_SECRET");
  const siteUrl = (Deno.env.get("SITE_URL") ?? "").replace(/\/+$/, "");
  const logoUrl = Deno.env.get("SIGNUP_EMAIL_LOGO_URL") ?? (siteUrl ? `${siteUrl}/logo-icon.png` : "");
  if (!supabaseUrl || !serviceKey || !resendKey || !resendFrom || !otpSecret) {
    return fail("not_configured", "Signup email is not configured yet.", 500);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return fail("bad_request", "Invalid request body.");
  }

  const action = String(body.action ?? "");
  const email = String(body.email ?? "").trim().toLowerCase();
  if (!EMAIL_RE.test(email) || email.length > 254) return fail("invalid_email", "Enter a valid email address.");

  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  async function userStatus(): Promise<{ id: string; confirmed: boolean } | null> {
    const { data, error } = await admin.rpc("signup_otp_user_status", { p_email: email });
    if (error) throw error;
    const row = (data as { user_id: string; confirmed: boolean }[] | null)?.[0];
    return row ? { id: row.user_id, confirmed: row.confirmed } : null;
  }

  /** Enforces the cooldown + hourly cap, stores the hashed code and emails it. */
  async function issueCode(name: string): Promise<Response | null> {
    const now = new Date();
    const { data: existing } = await admin.from("signup_otps").select("*").eq("email", email).maybeSingle();

    let sendCount = 1;
    let windowStart = now;
    if (existing) {
      const since = (now.getTime() - new Date(existing.last_sent_at).getTime()) / 1000;
      if (since < RESEND_COOLDOWN_SECONDS) {
        return fail("cooldown", `Please wait ${Math.ceil(RESEND_COOLDOWN_SECONDS - since)}s before requesting another code.`, 429);
      }
      const windowAge = now.getTime() - new Date(existing.window_start).getTime();
      if (windowAge < 3_600_000) {
        if (existing.send_count >= MAX_SENDS_PER_HOUR) return fail("rate_limited", "Too many codes requested. Try again in an hour.", 429);
        sendCount = existing.send_count + 1;
        windowStart = new Date(existing.window_start);
      }
    }

    const code = generateOtp();
    const { error: upsertError } = await admin.from("signup_otps").upsert({
      email,
      code_hash: await hashOtp(email, code, otpSecret!),
      expires_at: new Date(now.getTime() + OTP_TTL_MINUTES * 60_000).toISOString(),
      attempts: 0,
      send_count: sendCount,
      window_start: windowStart.toISOString(),
      last_sent_at: now.toISOString(),
    });
    if (upsertError) throw upsertError;

    const mail = buildOtpEmail({ name, code, logoUrl });
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from: resendFrom, to: [email], subject: mail.subject, html: mail.html, text: mail.text }),
    });
    if (!res.ok) {
      // Don't leave a code nobody received. Never log the code or the email body.
      await admin.from("signup_otps").delete().eq("email", email);
      // Resend's error body names the cause (unverified domain, bad key, malformed "from"); it holds no secrets.
      const detail = (await res.text().catch(() => "")).slice(0, 300);
      console.error("signup-otp: resend failed", res.status, detail);
      return fail("send_failed", "We couldn't send the verification email. Please try again.", 502);
    }
    return null;
  }

  try {
    if (action === "start") {
      const name = String(body.name ?? "").trim();
      const password = String(body.password ?? "");
      if (name.length < 2 || name.length > 80) return fail("invalid_name", "Enter your full name.");
      if (password.length < 8 || password.length > 128) return fail("weak_password", "Password must be 8–128 characters.");

      const existing = await userStatus();
      if (existing?.confirmed) return fail("email_taken", "An account already exists for this email address. Sign in instead.", 409);

      // require_mobile: new owners must also verify a mobile number (mobile-otp) before onboarding.
      const meta = { full_name: name, account_type: "owner", require_mobile: true };
      if (existing) {
        // An earlier, never-verified attempt: refresh its details and re-issue a code.
        const { error } = await admin.auth.admin.updateUserById(existing.id, { password, user_metadata: meta });
        if (error) throw error;
      } else {
        const { error } = await admin.auth.admin.createUser({ email, password, email_confirm: false, user_metadata: meta });
        if (error) {
          if (/password/i.test(error.message)) return fail("weak_password", "That password is too weak. Try a longer one.");
          throw error;
        }
      }
      const blocked = await issueCode(name);
      if (blocked) return blocked;
      return json({ ok: true });
    }

    if (action === "resend") {
      const existing = await userStatus();
      // Same answer whether or not the address exists, so this can't be used to probe for accounts.
      if (!existing || existing.confirmed) return json({ ok: true });
      const { data: user } = await admin.auth.admin.getUserById(existing.id);
      const name = String(user?.user?.user_metadata?.full_name ?? "");
      const blocked = await issueCode(name);
      if (blocked) return blocked;
      return json({ ok: true });
    }

    if (action === "verify") {
      const code = String(body.code ?? "").replace(/\s+/g, "");
      if (!/^\d{6}$/.test(code)) return fail("invalid_code", "Enter the 6-digit code.");

      const { data: row } = await admin.from("signup_otps").select("*").eq("email", email).maybeSingle();
      if (!row) return fail("invalid_code", "That code is incorrect or has expired. Request a new one.");
      if (new Date(row.expires_at).getTime() < Date.now()) {
        await admin.from("signup_otps").delete().eq("email", email);
        return fail("expired", "That code has expired. Request a new one.");
      }
      if (row.attempts >= MAX_VERIFY_ATTEMPTS) {
        await admin.from("signup_otps").delete().eq("email", email);
        return fail("locked", "Too many incorrect attempts. Request a new code.", 429);
      }

      const ok = safeEqual(row.code_hash, await hashOtp(email, code, otpSecret));
      if (!ok) {
        await admin.from("signup_otps").update({ attempts: row.attempts + 1 }).eq("email", email);
        const left = MAX_VERIFY_ATTEMPTS - row.attempts - 1;
        return fail("invalid_code", left > 0 ? `Incorrect code. ${left} attempt${left === 1 ? "" : "s"} left.` : "Too many incorrect attempts. Request a new code.");
      }

      const existing = await userStatus();
      if (!existing) return fail("invalid_code", "That code is incorrect or has expired. Request a new one.");
      const { error } = await admin.auth.admin.updateUserById(existing.id, { email_confirm: true });
      if (error) throw error;
      await admin.from("signup_otps").delete().eq("email", email); // single use
      return json({ ok: true });
    }

    return fail("bad_request", "Unknown action.");
  } catch (e) {
    console.error("signup-otp: unexpected error", e instanceof Error ? e.message : "unknown");
    return fail("server_error", "Something went wrong. Please try again.", 500);
  }
});
