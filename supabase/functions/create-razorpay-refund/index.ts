// ═══════════════════════════════════════════════════════════════════════════
// create-razorpay-refund — Cancellation, Refund & Payment Recovery, Phase 6.
//
// The owner's manual refund entry point: "Initiate Refund" on a settled
// payment (partial adjustment, duplicate-payment correction, or resolving a
// SETTLEMENT_EXCEPTION). Runs under the caller's own staff session — the
// same RLS-scoped pattern as every other Phase 1-5 Edge Function.
//
// Never called directly from the frontend to talk to Razorpay (spec §17):
// this function is the ONLY place besides cancel-booking/
// cancel-membership-slot/cancel-membership that holds RAZORPAY_KEY_SECRET
// and calls the Razorpay Refund API. The frontend only ever says "refund
// this payment [this much] [for this reason]" — eligibility, amount
// validation, and the actual Razorpay call all happen here.
//
// Flow: request_refund (DB — validates eligibility, creates REQUESTED row,
// blocks over-refund/concurrent-refund) → Razorpay Refund API →
// mark_refund_processing (or mark_refund_failed on error) → response.
// Final confirmation always arrives via the refund.processed webhook
// (razorpay-webhook), never decided here (spec §22/§25).
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { submitRequestedRefund } from "../_shared/submit-refund.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface RefundRequest {
  // Exactly one of these two identifies what's being refunded.
  paymentOrderId?: string;
  settlementExceptionId?: string;
  amountMinor?: number; // required with paymentOrderId; ignored/derived for settlementExceptionId (always full)
  reason?: string; // a refund_reason value; defaults to OTHER
  overrideReason?: string;
}

interface RefundRow {
  id: string;
  razorpay_payment_id: string;
  amount_minor: number;
  status: string;
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } });
}

const GENERIC_ERROR = "Refund could not be initiated.";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return jsonResponse({ error: "Not authenticated" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const razorpayKeyId = Deno.env.get("RAZORPAY_KEY_ID");
  const razorpayKeySecret = Deno.env.get("RAZORPAY_KEY_SECRET");

  if (!supabaseUrl || !supabaseAnonKey || !razorpayKeyId || !razorpayKeySecret) {
    console.error("[create-razorpay-refund] missing required function secrets");
    return jsonResponse({ error: "Refunds are not configured yet." }, 500);
  }

  let body: RefundRequest;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid request body." }, 400);
  }
  if (!body.paymentOrderId && !body.settlementExceptionId) {
    return jsonResponse({ error: "Either paymentOrderId or settlementExceptionId is required." }, 400);
  }
  if (body.paymentOrderId && (body.amountMinor === undefined || body.amountMinor <= 0)) {
    return jsonResponse({ error: "amountMinor is required and must be positive." }, 400);
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, { global: { headers: { Authorization: authHeader } } });

  let refund: RefundRow | null = null;
  if (body.settlementExceptionId) {
    const { data, error } = await supabase.rpc("refund_settlement_exception", { p_settlement_exception_id: body.settlementExceptionId });
    if (error || !data) {
      console.error("[create-razorpay-refund] refund_settlement_exception rejected", { id: body.settlementExceptionId, message: error?.message });
      return jsonResponse({ error: error?.message?.includes("Nothing left") ? error.message : GENERIC_ERROR }, 400);
    }
    refund = data as RefundRow;
  } else {
    const { data, error } = await supabase.rpc("initiate_manual_refund", {
      p_payment_order_id: body.paymentOrderId,
      p_amount_minor: body.amountMinor,
      p_reason: (body.reason as string) || "OTHER",
      p_override_reason: body.overrideReason ?? null,
    });
    if (error || !data) {
      console.error("[create-razorpay-refund] initiate_manual_refund rejected", { paymentOrderId: body.paymentOrderId, message: error?.message });
      // The maximum-refundable message is safe and useful to surface verbatim (spec §68); anything else is generic.
      const message = error?.message?.startsWith("The maximum refundable amount") || error?.message?.includes("not eligible for a refund") ? error.message : GENERIC_ERROR;
      return jsonResponse({ error: message }, 400);
    }
    refund = data as RefundRow;
  }

  // §41/§60: a concurrent/duplicate request may have returned an
  // already-PROCESSING (or further along) refund row rather than a fresh
  // REQUESTED one — submitRequestedRefund is a no-op in that case.
  const result = await submitRequestedRefund(supabase, refund.id, razorpayKeyId, razorpayKeySecret);
  if (result.status === "FAILED") {
    return jsonResponse({ error: "Unable to reach the payment gateway. Please retry.", refundId: result.refundId, status: result.status }, 502);
  }
  return jsonResponse(result, 200);
});