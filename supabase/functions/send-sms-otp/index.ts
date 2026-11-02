// ═══════════════════════════════════════════════════════════════════════════
// send-sms-otp — Supabase Auth "Send SMS" hook for the Player app's phone login.
//
// Supabase Auth creates the six-digit code and calls this function instead of a built-in SMS provider. We deliver the code through
// 2Factor.in, by default as a PHONE CALL that reads the code out (voice OTP needs no DLT registration). When text messages are
// approved, set SMS_OTP_CHANNEL=sms to send them as texts instead; nothing else changes.
//
// Only Supabase can call it: every request carries a Standard Webhooks signature that is checked against SEND_SMS_HOOK_SECRET
// (and refused when stale), so nobody can use this URL to ring arbitrary numbers. Indian mobiles only.
//
// Setup (see supabase/functions/README.md):
//   supabase secrets set TWOFACTOR_API_KEY=<2factor api key>        (already set for mobile-otp)
//   supabase secrets set SEND_SMS_HOOK_SECRET="v1,whsec_..."         (the secret shown when you create the hook)
//   supabase secrets set SMS_OTP_CHANNEL=voice                       (default; "sms" for text messages)
//   supabase secrets set TWOFACTOR_TEMPLATE_NAME=<template>          (only for "sms", optional)
//   supabase functions deploy send-sms-otp --no-verify-jwt
// Then: Dashboard → Authentication → Hooks → Send SMS → HTTPS → this function's URL.
// ═══════════════════════════════════════════════════════════════════════════

import { sendTextOtp, sendVoiceOtp, tenDigitMobile, verifyHookSignature } from "../_shared/send-sms-hook.ts";

function reply(status: number, message?: string): Response {
  // Supabase Auth reads { error: { http_code, message } } from a failed hook and shows the message to the caller.
  const body = message ? { error: { http_code: status, message } } : {};
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return reply(405, "Method not allowed");

  const hookSecret = Deno.env.get("SEND_SMS_HOOK_SECRET");
  const apiKey = Deno.env.get("TWOFACTOR_API_KEY");
  if (!hookSecret || !apiKey) return reply(500, "Phone sign-in is not configured yet.");

  const raw = await req.text();
  const signed = await verifyHookSignature(
    raw,
    { id: req.headers.get("webhook-id"), timestamp: req.headers.get("webhook-timestamp"), signature: req.headers.get("webhook-signature") },
    hookSecret,
  );
  if (!signed) return reply(401, "Invalid signature.");

  let payload: { user?: { phone?: string }; sms?: { otp?: string } };
  try {
    payload = JSON.parse(raw);
  } catch {
    return reply(400, "Invalid request.");
  }
  const phone = tenDigitMobile(String(payload.user?.phone ?? ""));
  const code = String(payload.sms?.otp ?? "");
  if (!phone) return reply(400, "Please enter a valid Indian mobile number.");
  if (!/^\d{4,8}$/.test(code)) return reply(400, "Invalid code.");

  const channel = (Deno.env.get("SMS_OTP_CHANNEL") ?? "voice").toLowerCase();
  const ok = channel === "sms"
    ? await sendTextOtp(phone, code, apiKey, Deno.env.get("TWOFACTOR_TEMPLATE_NAME") || undefined)
    : await sendVoiceOtp(phone, code, apiKey);
  if (!ok) return reply(502, "We couldn't deliver the code right now. Please try again in a moment.");
  return reply(200);
});
