// ═══════════════════════════════════════════════════════════════════════════
// cancel-booking — Cancellation, Refund & Payment Recovery, Phase 6.
//
// Single entry point for cancelling a MEMBER_BOOKING or ad-hoc GUEST_BOOKING
// (a `bookings` row). Runs under the caller's own staff session (same
// pattern as create-razorpay-order etc.) so a facility member can only
// cancel a booking their own facility-scoped RLS lets them see.
//
// Flow: cancel_booking (DB — cancels the booking, releases court
// availability for free via the existing exclusion constraint, and — if the
// booking was paid — creates a policy-derived REQUESTED refund row) →
// submit that refund to Razorpay in the same request, so the client makes
// one call and sees the real outcome, not just "cancelled, refund maybe
// coming" (spec §8/§13's single flow diagram).
//
// A booking with no captured payment (never paid, or PENDING) cancels with
// no refund step at all — cancel_booking itself decides that; this function
// never re-implements that check.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { submitRequestedRefund } from "../_shared/submit-refund.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface CancelRequest {
  bookingId: string;
  reason?: string;
  /** Owner override — replaces the policy-computed refund percent (0-100). Omit to use the facility's cancellation policy. */
  refundOverridePercent?: number;
  overrideReason?: string;
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return jsonResponse({ error: "Not authenticated" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const razorpayKeyId = Deno.env.get("RAZORPAY_KEY_ID");
  const razorpayKeySecret = Deno.env.get("RAZORPAY_KEY_SECRET");

  if (!supabaseUrl || !supabaseAnonKey) {
    console.error("[cancel-booking] missing required function secrets");
    return jsonResponse({ error: "This action is not configured yet." }, 500);
  }

  let body: CancelRequest;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid request body." }, 400);
  }
  if (!body.bookingId) return jsonResponse({ error: "bookingId is required." }, 400);

  const supabase = createClient(supabaseUrl, supabaseAnonKey, { global: { headers: { Authorization: authHeader } } });

  const { data: booking, error: cancelError } = await supabase.rpc("cancel_booking", {
    p_booking_id: body.bookingId,
    p_reason: body.reason ?? null,
    p_refund_override_percent: body.refundOverridePercent ?? null,
    p_override_reason: body.overrideReason ?? null,
  });

  if (cancelError || !booking) {
    console.error("[cancel-booking] cancel_booking rejected", { bookingId: body.bookingId, message: cancelError?.message });
    const message = cancelError?.message?.includes("cannot be cancelled") ? cancelError.message : "Booking cannot be cancelled.";
    return jsonResponse({ error: message }, 400);
  }

  // A refund row may or may not have been created (unpaid booking, or a
  // policy percent of 0%) — look for one this cancellation could have made.
  const { data: refunds } = await supabase
    .from("refunds")
    .select("id, status")
    .eq("source_id", body.bookingId)
    .in("status", ["REQUESTED"])
    .order("created_at", { ascending: false })
    .limit(1);

  const pendingRefund = refunds?.[0];
  if (!pendingRefund) {
    return jsonResponse({ booking, refund: null }, 200);
  }

  if (!razorpayKeyId || !razorpayKeySecret) {
    console.error("[cancel-booking] refund created but Razorpay is not configured");
    return jsonResponse({ booking, refund: { id: pendingRefund.id, status: pendingRefund.status } }, 200);
  }

  const submitted = await submitRequestedRefund(supabase, pendingRefund.id, razorpayKeyId, razorpayKeySecret);
  return jsonResponse({ booking, refund: submitted }, 200);
});