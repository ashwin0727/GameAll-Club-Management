// ═══════════════════════════════════════════════════════════════════════════
// cancel-membership-slot — Cancellation, Refund & Payment Recovery, Phase 6.
//
// Cancels a released-capacity guest booking (a membership_session_bookings
// row) and, if it was paid, requests + submits a policy-derived refund —
// same shape as cancel-booking, for the guest-slot path (spec §11/§12).
// Guest capacity release is free: get_membership_session_capacity (0014)
// derives availability live from CONFIRMED rows only.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { submitRequestedRefund } from "../_shared/submit-refund.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface CancelRequest {
  bookingId: string; // membership_session_bookings.id
  reason?: string;
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
    console.error("[cancel-membership-slot] missing required function secrets");
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

  const { data: booking, error: cancelError } = await supabase.rpc("cancel_membership_guest_slot", {
    p_booking_id: body.bookingId,
    p_reason: body.reason ?? null,
    p_refund_override_percent: body.refundOverridePercent ?? null,
    p_override_reason: body.overrideReason ?? null,
  });

  if (cancelError || !booking) {
    console.error("[cancel-membership-slot] cancel_membership_guest_slot rejected", { bookingId: body.bookingId, message: cancelError?.message });
    return jsonResponse({ error: "This booking could not be cancelled." }, 400);
  }

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
    console.error("[cancel-membership-slot] refund created but Razorpay is not configured");
    return jsonResponse({ booking, refund: { id: pendingRefund.id, status: pendingRefund.status } }, 200);
  }

  const submitted = await submitRequestedRefund(supabase, pendingRefund.id, razorpayKeyId, razorpayKeySecret);
  return jsonResponse({ booking, refund: submitted }, 200);
});