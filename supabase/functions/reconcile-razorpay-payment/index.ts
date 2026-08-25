// ═══════════════════════════════════════════════════════════════════════════
// reconcile-razorpay-payment — Payment Reconciliation, Phase 4.
//
// Recovers from the "client callback lost" case (§"Client Callback Lost
// Test"): the customer paid, Razorpay knows it, but the browser/app never
// got to call verify-razorpay-payment (crash, closed tab, lost network)
// and the webhook hasn't landed yet either. Rather than polling Razorpay
// continuously, this is a single, staff-triggered, on-demand recheck —
// called from the Payment Status panel's "Check Again" action when a
// payment order is still stuck in a non-terminal state.
//
// Same session/RLS model as verify-razorpay-payment — runs as the caller,
// so facility isolation is enforced for free.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { fetchRazorpayOrderPayments, mapRazorpayPaymentStatus, pickMostDecisivePayment } from "../_shared/razorpay.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ReconcileRequest {
  paymentOrderId: string;
}

interface PaymentOrderRow {
  id: string;
  razorpay_order_id: string | null;
  status: string;
}

// Once here, the order is done being reconciled — no point asking
// Razorpay again.
const TERMINAL_STATUSES = new Set(["CAPTURED", "COMPLETED", "FAILED", "CANCELLED", "REFUND_REQUESTED", "REFUNDED"]);

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } });
}

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
    console.error("[reconcile-razorpay-payment] missing required function secrets");
    return jsonResponse({ error: "Payments are not configured yet. Ask the developer to set up Razorpay test keys." }, 500);
  }

  let body: ReconcileRequest;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid request body." }, 400);
  }
  if (!body.paymentOrderId) {
    return jsonResponse({ error: "paymentOrderId is required." }, 400);
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, { global: { headers: { Authorization: authHeader } } });

  const { data: orderData, error: orderError } = await supabase.rpc("get_payment_order", { p_payment_order_id: body.paymentOrderId });
  if (orderError || !orderData) {
    return jsonResponse({ error: "Payment order not found." }, 404);
  }
  const order = orderData as PaymentOrderRow;

  if (TERMINAL_STATUSES.has(order.status)) {
    return jsonResponse({ paymentOrderId: order.id, status: order.status }, 200);
  }
  if (!order.razorpay_order_id) {
    // Never even got a Razorpay order — nothing to reconcile against yet.
    return jsonResponse({ paymentOrderId: order.id, status: order.status }, 200);
  }

  let payments;
  try {
    payments = await fetchRazorpayOrderPayments(order.razorpay_order_id, razorpayKeyId, razorpayKeySecret);
  } catch (err) {
    console.error("[reconcile-razorpay-payment] failed to fetch order payments from Razorpay", { paymentOrderId: order.id, error: String(err) });
    return jsonResponse({ error: "Unable to reach the payment gateway. Please try again shortly." }, 502);
  }

  const decisive = pickMostDecisivePayment(payments);
  if (!decisive) {
    // Razorpay itself has no payment attempt for this order yet — still
    // genuinely pending, not an error.
    return jsonResponse({ paymentOrderId: order.id, status: order.status }, 200);
  }

  const targetStatus = mapRazorpayPaymentStatus(decisive.status);

  const { data: applied, error: applyError } = await supabase.rpc("apply_payment_verification", {
    p_payment_order_id: order.id,
    p_razorpay_order_id: order.razorpay_order_id,
    p_razorpay_payment_id: decisive.id,
    p_razorpay_status: targetStatus,
    p_amount_minor: decisive.amount,
    p_currency: decisive.currency,
  });

  if (applyError || !applied) {
    console.error("[reconcile-razorpay-payment] apply_payment_verification rejected", { paymentOrderId: order.id, code: applyError?.code, message: applyError?.message });
    return jsonResponse({ error: "Payment could not be verified. Please contact the facility." }, 400);
  }

  console.log("[reconcile-razorpay-payment] reconciled", { paymentOrderId: order.id, status: applied.status });
  return jsonResponse({ paymentOrderId: applied.id, status: applied.status }, 200);
});