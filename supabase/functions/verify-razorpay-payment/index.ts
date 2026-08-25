// ═══════════════════════════════════════════════════════════════════════════
// verify-razorpay-payment — Razorpay Payment Verification, Phase 4.
//
// The client (Flutter/Web) is NEVER the final authority for payment
// success — see supabase/functions/_shared/razorpay.ts and
// 0019_payment_verification.sql. This function is what a client calls
// right after Razorpay Checkout's success handler fires: it takes the
// client's claimed result and independently re-derives the truth —
// checking the signature server-side, then asking Razorpay directly for
// the payment's authoritative amount/currency/status — before ever
// advancing payment_orders.status.
//
// Runs under the CALLER's own Supabase session (same pattern as
// create-razorpay-order) — a staff member can only verify a payment for an
// order their own facility-scoped RLS lets them see, so cross-facility
// payment data can never leak here (§"Facility Isolation Test").
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { fetchRazorpayPayment, mapRazorpayPaymentStatus, verifyPaymentSignature } from "../_shared/razorpay.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface VerifyRequest {
  paymentOrderId: string;
  razorpayOrderId: string;
  razorpayPaymentId: string;
  razorpaySignature: string;
}

interface PaymentOrderRow {
  id: string;
  razorpay_order_id: string | null;
  status: string;
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } });
}

// Every rejected verification returns this one message — never the
// specific reason (wrong order, amount mismatch, bad signature) — so a
// tampering attempt learns nothing about which check it failed
// (§"Amount Tampering Protection"). The real reason is only ever logged
// server-side.
const VERIFICATION_FAILED_MESSAGE = "Payment could not be verified. Please contact the facility.";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Not authenticated" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const razorpayKeyId = Deno.env.get("RAZORPAY_KEY_ID");
  const razorpayKeySecret = Deno.env.get("RAZORPAY_KEY_SECRET");

  if (!supabaseUrl || !supabaseAnonKey || !razorpayKeyId || !razorpayKeySecret) {
    console.error("[verify-razorpay-payment] missing required function secrets");
    return jsonResponse({ error: "Payments are not configured yet. Ask the developer to set up Razorpay test keys." }, 500);
  }

  let body: VerifyRequest;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid request body." }, 400);
  }
  if (!body.paymentOrderId || !body.razorpayOrderId || !body.razorpayPaymentId || !body.razorpaySignature) {
    return jsonResponse({ error: "paymentOrderId, razorpayOrderId, razorpayPaymentId, and razorpaySignature are all required." }, 400);
  }

  // Runs as the caller — the same RLS the signed-in staff member already
  // has in the app applies to every read/write below.
  const supabase = createClient(supabaseUrl, supabaseAnonKey, { global: { headers: { Authorization: authHeader } } });

  const { data: orderData, error: orderError } = await supabase.rpc("get_payment_order", { p_payment_order_id: body.paymentOrderId });
  if (orderError || !orderData) {
    // Either the order doesn't exist, or RLS hid it because it belongs to
    // a different facility than the caller — either way, no leak.
    return jsonResponse({ error: "Payment order not found." }, 404);
  }
  const order = orderData as PaymentOrderRow;

  // §"Payment Order Matching" / §"Wrong Order Test" — checked here too
  // (defense in depth; apply_payment_verification checks it again as the
  // final authority) so a mismatch never even reaches the Razorpay API call.
  if (order.razorpay_order_id !== body.razorpayOrderId) {
    console.error("[verify-razorpay-payment] razorpay_order_id mismatch", { paymentOrderId: order.id });
    return jsonResponse({ error: VERIFICATION_FAILED_MESSAGE }, 400);
  }

  const signatureValid = await verifyPaymentSignature(body.razorpayOrderId, body.razorpayPaymentId, body.razorpaySignature, razorpayKeySecret);
  if (!signatureValid) {
    console.error("[verify-razorpay-payment] signature verification failed", { paymentOrderId: order.id });
    return jsonResponse({ error: VERIFICATION_FAILED_MESSAGE }, 400);
  }

  let razorpayPayment;
  try {
    razorpayPayment = await fetchRazorpayPayment(body.razorpayPaymentId, razorpayKeyId, razorpayKeySecret);
  } catch (err) {
    console.error("[verify-razorpay-payment] failed to fetch payment from Razorpay", { paymentOrderId: order.id, error: String(err) });
    return jsonResponse({ error: "Unable to reach the payment gateway. Please try again shortly." }, 502);
  }

  if (razorpayPayment.order_id !== body.razorpayOrderId || razorpayPayment.id !== body.razorpayPaymentId) {
    console.error("[verify-razorpay-payment] Razorpay payment does not belong to the claimed order", { paymentOrderId: order.id });
    return jsonResponse({ error: VERIFICATION_FAILED_MESSAGE }, 400);
  }

  const targetStatus = mapRazorpayPaymentStatus(razorpayPayment.status);

  const { data: applied, error: applyError } = await supabase.rpc("apply_payment_verification", {
    p_payment_order_id: order.id,
    p_razorpay_order_id: razorpayPayment.order_id,
    p_razorpay_payment_id: razorpayPayment.id,
    p_razorpay_status: targetStatus,
    p_amount_minor: razorpayPayment.amount,
    p_currency: razorpayPayment.currency,
    p_razorpay_signature: body.razorpaySignature,
  });

  if (applyError || !applied) {
    // §"Amount Mismatch Test" / §"Wrong Order Test" surface here as a
    // 23514 raised inside apply_payment_verification — still the same
    // generic message to the client, full detail logged server-side.
    console.error("[verify-razorpay-payment] apply_payment_verification rejected", {
      paymentOrderId: order.id,
      code: applyError?.code,
      message: applyError?.message,
    });
    return jsonResponse({ error: VERIFICATION_FAILED_MESSAGE }, 400);
  }

  console.log("[verify-razorpay-payment] verified", { paymentOrderId: order.id, status: applied.status, razorpayPaymentId: razorpayPayment.id });

  return jsonResponse({ paymentOrderId: applied.id, status: applied.status }, 200);
});