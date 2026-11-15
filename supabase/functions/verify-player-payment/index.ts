// ═══════════════════════════════════════════════════════════════════════════
// verify-player-payment — the Player app's in-app Razorpay checkout hands its result here.
//
// The app opens Razorpay's own sheet (which lists the phone's UPI apps). When the sheet says "success" the app is NOT trusted: it sends
// what Razorpay returned and this function re-derives the truth before any money is recorded.
//
//   POST { kind: "booking", bookingId, paymentOrderId, razorpayOrderId, razorpayPaymentId, razorpaySignature }
//        → checks the booking is the caller's own and the order is that booking's; checks the signature (order|payment); asks Razorpay
//          for the payment itself (same order, captured); then records it through apply_payment_verification, the one gate the web's
//          checkout and the webhook use too (it refuses a wrong amount or order, and dedupes on the payment id).
//   POST { kind: "membership" | "coaching", id, razorpayPaymentId, razorpaySubscriptionId, razorpaySignature }
//        → an AutoPay mandate: checks the item is the caller's own, the subscription is that item's, and the signature
//          (payment|subscription). Recording the charges stays with the razorpay-webhook and sync-player-payment (they dedupe on the
//          Razorpay payment id), so this only answers whether the claim is genuine.
//
// Every refusal answers the same words, so a forged request learns nothing about which check failed. The razorpay-webhook remains the
// backup: if the app never gets to call this (the phone dies after paying), the webhook still settles the payment.
//
// Setup: same secrets as the other payment functions (RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET). Deploy:
//   supabase functions deploy verify-player-payment
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  captureRazorpayPayment,
  fetchRazorpayPayment,
  mapRazorpayPaymentStatus,
  verifyPaymentSignature,
  verifySubscriptionPaymentSignature,
} from "../_shared/razorpay.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } });
}

const FAILED = "We couldn't verify that payment. If money was taken it will be reconciled automatically.";

interface VerifyBody {
  kind?: string;
  id?: string;
  bookingId?: string;
  paymentOrderId?: string;
  razorpayOrderId?: string;
  razorpayPaymentId?: string;
  razorpaySubscriptionId?: string;
  razorpaySignature?: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return jsonResponse({ error: "Not authenticated" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const keyId = Deno.env.get("RAZORPAY_KEY_ID");
  const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
  if (!supabaseUrl || !anonKey || !serviceKey || !keyId || !keySecret) {
    console.error("[verify-player-payment] missing function secrets");
    return jsonResponse({ error: "Online payments are not configured yet." }, 500);
  }

  let body: VerifyBody;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body." }, 400);
  }
  const kind = (body.kind ?? "").toLowerCase();
  if (!body.razorpayPaymentId || !body.razorpaySignature) return jsonResponse({ error: FAILED }, 400);

  const asPlayer = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });

  // ── an AutoPay mandate (membership, or monthly coaching) ──
  if (kind === "membership" || kind === "coaching") {
    if (!body.id || !body.razorpaySubscriptionId) return jsonResponse({ error: FAILED }, 400);

    // is it the caller's own? (get_my_payment_receipt answers null for anything that is not)
    const { data: receipt } = await asPlayer.rpc("get_my_payment_receipt", { p_kind: kind, p_id: body.id });
    if (!receipt) return jsonResponse({ error: FAILED }, 400);

    // is the subscription this item's own?
    const admin = createClient(supabaseUrl, serviceKey);
    let ownSubscriptionId: string | null = null;
    if (kind === "membership") {
      const { data } = await admin.from("membership_subscriptions").select("razorpay_subscription_id").eq("membership_id", body.id).maybeSingle();
      ownSubscriptionId = (data as { razorpay_subscription_id?: string } | null)?.razorpay_subscription_id ?? null;
    } else {
      const { data } = await asPlayer.rpc("player_get_coaching_billing_context", { p_enrollment_id: body.id });
      ownSubscriptionId = (data as { billing?: { razorpaySubscriptionId?: string | null } | null } | null)?.billing?.razorpaySubscriptionId ?? null;
    }
    if (!ownSubscriptionId || ownSubscriptionId !== body.razorpaySubscriptionId) {
      console.error("[verify-player-payment] subscription is not this item's", { kind });
      return jsonResponse({ error: FAILED }, 400);
    }
    if (!(await verifySubscriptionPaymentSignature(body.razorpayPaymentId, body.razorpaySubscriptionId, body.razorpaySignature, keySecret))) {
      console.error("[verify-player-payment] subscription signature failed", { kind });
      return jsonResponse({ error: FAILED }, 400);
    }
    return jsonResponse({ verified: true }, 200);
  }

  // ── a booking paid through a Razorpay order ──
  if (kind === "booking") {
    if (!body.bookingId || !body.paymentOrderId || !body.razorpayOrderId) return jsonResponse({ error: FAILED }, 400);

    // is the booking the caller's own?
    const { data: ctx, error: ctxErr } = await asPlayer.rpc("player_booking_payment_context", { p_booking_id: body.bookingId });
    if (ctxErr || !ctx) return jsonResponse({ error: FAILED }, 400);

    // is the order this booking's, and the one the app was shown?
    const admin = createClient(supabaseUrl, serviceKey);
    const { data: order } = await admin
      .from("payment_orders")
      .select("id, booking_id, razorpay_order_id")
      .eq("id", body.paymentOrderId)
      .maybeSingle();
    const o = order as { id: string; booking_id: string | null; razorpay_order_id: string | null } | null;
    if (!o || o.booking_id !== body.bookingId || o.razorpay_order_id !== body.razorpayOrderId) {
      console.error("[verify-player-payment] order does not belong to this booking");
      return jsonResponse({ error: FAILED }, 400);
    }

    if (!(await verifyPaymentSignature(body.razorpayOrderId, body.razorpayPaymentId, body.razorpaySignature, keySecret))) {
      console.error("[verify-player-payment] order signature failed", { paymentOrderId: o.id });
      return jsonResponse({ error: FAILED }, 400);
    }

    let payment;
    try {
      payment = await fetchRazorpayPayment(body.razorpayPaymentId, keyId, keySecret);
      if (payment.order_id !== body.razorpayOrderId || payment.id !== body.razorpayPaymentId) return jsonResponse({ error: FAILED }, 400);
      if (payment.status === "authorized") {
        payment = await captureRazorpayPayment(payment.id, payment.amount, payment.currency, keyId, keySecret);
      }
    } catch (err) {
      console.error("[verify-player-payment] could not read the payment from Razorpay", String(err));
      return jsonResponse({ error: "Unable to reach the payment provider. Please try again shortly." }, 502);
    }

    const { data: applied, error: applyErr } = await admin.rpc("apply_payment_verification", {
      p_payment_order_id: o.id,
      p_razorpay_order_id: payment.order_id,
      p_razorpay_payment_id: payment.id,
      p_razorpay_status: mapRazorpayPaymentStatus(payment.status),
      p_amount_minor: payment.amount,
      p_currency: payment.currency,
      p_razorpay_signature: body.razorpaySignature,
    });
    if (applyErr) {
      console.error("[verify-player-payment] apply_payment_verification rejected", applyErr.code, applyErr.message);
      return jsonResponse({ error: FAILED }, 400);
    }
    return jsonResponse({ verified: true, status: (applied as { status?: string } | null)?.status ?? null }, 200);
  }

  return jsonResponse({ error: FAILED }, 400);
});
