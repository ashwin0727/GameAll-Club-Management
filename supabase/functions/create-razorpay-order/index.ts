// ═══════════════════════════════════════════════════════════════════════════
// create-razorpay-order — Razorpay Payment Foundation, Phase 2.
//
// The ONLY place in this codebase allowed to hold the Razorpay Key Secret.
// Flutter/Web never talk to Razorpay directly and never see the secret —
// they call this function, which:
//
//   1. Forwards the caller's own Supabase session (Authorization header) to
//      a Supabase client, so every read/write below runs under the SAME
//      RLS the caller already has in the app — this function has no more
//      access than the signed-in owner/manager/staff member calling it.
//   2. Calls create_payment_order(), the single source of truth for
//      "is this a valid, facility-scoped, correctly-priced payment
//      request?" — the client's `amount` (if it sent one) is never read.
//   3. If that order doesn't have a Razorpay order yet, calls Razorpay's
//      Orders API with the server-computed amount, and saves the returned
//      razorpay_order_id back onto the row.
//   4. Returns only what the client needs to open Razorpay Checkout —
//      never the secret, never a service-role key.
//
// Setup (see supabase/functions/README.md for the full walkthrough):
//   supabase secrets set RAZORPAY_KEY_ID=rzp_test_xxxxxxxxxxxxx
//   supabase secrets set RAZORPAY_KEY_SECRET=your_test_secret
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface CreateOrderRequest {
  facilityId: string;
  sourceType: "MEMBERSHIP" | "MEMBER_BOOKING" | "GUEST_BOOKING";
  bookingId?: string;
  membershipSessionBookingId?: string;
  memberId?: string;
  planId?: string;
}

interface PaymentOrderRow {
  id: string;
  facility_id: string;
  source_type: string;
  amount_minor: number;
  currency: string;
  status: string;
  razorpay_order_id: string | null;
  receipt: string;
  booking_id: string | null;
  membership_session_booking_id: string | null;
  plan_id: string | null;
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
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

  if (!supabaseUrl || !supabaseAnonKey) {
    console.error("[create-razorpay-order] missing SUPABASE_URL/SUPABASE_ANON_KEY function secrets");
    return jsonResponse({ error: "Server is not configured correctly." }, 500);
  }
  if (!razorpayKeyId || !razorpayKeySecret) {
    console.error("[create-razorpay-order] missing RAZORPAY_KEY_ID/RAZORPAY_KEY_SECRET function secrets");
    return jsonResponse({ error: "Payments are not configured yet. Ask the developer to set up Razorpay test keys." }, 500);
  }
  if (!razorpayKeyId.startsWith("rzp_test_")) {
    // Phase 1/2 is TEST MODE ONLY — refuse to run against a live key even
    // if one is accidentally configured, rather than silently taking a
    // real payment during a foundation phase that never confirms success.
    console.error("[create-razorpay-order] refusing to run: RAZORPAY_KEY_ID is not a rzp_test_ key");
    return jsonResponse({ error: "Payments are only available in test mode right now." }, 500);
  }

  let body: CreateOrderRequest;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid request body." }, 400);
  }

  if (!body.facilityId || !body.sourceType) {
    return jsonResponse({ error: "facilityId and sourceType are required." }, 400);
  }

  // Runs as the caller — every RLS policy the signed-in staff member is
  // subject to in the app applies here too. This function gains no
  // privilege the caller didn't already have.
  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: orderData, error: orderError } = await supabase.rpc("create_payment_order", {
    p_facility_id: body.facilityId,
    p_source_type: body.sourceType,
    p_booking_id: body.bookingId ?? null,
    p_membership_session_booking_id: body.membershipSessionBookingId ?? null,
    p_member_id: body.memberId ?? null,
    p_plan_id: body.planId ?? null,
  });

  if (orderError) {
    console.error("[create-razorpay-order] create_payment_order failed", {
      code: orderError.code,
      message: orderError.message,
      sourceType: body.sourceType,
      facilityId: body.facilityId,
    });
    const friendly = orderError.code === "23514" || orderError.code === "23503" ? orderError.message : "Unable to start this payment.";
    return jsonResponse({ error: friendly }, 400);
  }

  const order = orderData as PaymentOrderRow;

  // Idempotent: a still-valid order for this exact source already has a
  // Razorpay order attached — hand it straight back instead of calling
  // Razorpay again (spec "Duplicate Order").
  if (order.razorpay_order_id) {
    return jsonResponse(
      {
        keyId: razorpayKeyId,
        razorpayOrderId: order.razorpay_order_id,
        amount: order.amount_minor,
        currency: order.currency,
        paymentOrderId: order.id,
        receipt: order.receipt,
      },
      200,
    );
  }

  let razorpayOrder: { id: string };
  try {
    const rzpResponse = await fetch("https://api.razorpay.com/v1/orders", {
      method: "POST",
      headers: {
        Authorization: `Basic ${btoa(`${razorpayKeyId}:${razorpayKeySecret}`)}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        amount: order.amount_minor,
        currency: order.currency,
        receipt: order.receipt,
        // Auto-capture on success so a payment never strands in AUTHORIZED
        // when the Razorpay account default is manual capture. verify- and
        // reconcile-razorpay-payment also capture explicitly as a backstop.
        payment_capture: 1,
        notes: {
          gameall_payment_order_id: order.id,
          facility_id: order.facility_id,
          source_type: order.source_type,
          booking_id: order.booking_id ?? "",
          membership_session_booking_id: order.membership_session_booking_id ?? "",
          plan_id: order.plan_id ?? "",
        },
      }),
    });

    if (!rzpResponse.ok) {
      const errBody = await rzpResponse.text();
      console.error("[create-razorpay-order] Razorpay API rejected the order", {
        status: rzpResponse.status,
        paymentOrderId: order.id,
        // Razorpay error bodies are safe to log (no secrets) but not to
        // return verbatim to the client.
        body: errBody.slice(0, 500),
      });
      await supabase.from("payment_orders").update({ status: "FAILED" }).eq("id", order.id);
      return jsonResponse({ error: "Unable to create the payment order right now. Please try again." }, 502);
    }

    razorpayOrder = await rzpResponse.json();
  } catch (err) {
    console.error("[create-razorpay-order] network error calling Razorpay", { paymentOrderId: order.id, error: String(err) });
    await supabase.from("payment_orders").update({ status: "FAILED" }).eq("id", order.id);
    return jsonResponse({ error: "Unable to reach the payment gateway. Please try again." }, 502);
  }

  const { data: updated, error: updateError } = await supabase
    .from("payment_orders")
    .update({ razorpay_order_id: razorpayOrder.id, status: "ORDER_CREATED" })
    .eq("id", order.id)
    .select("id, amount_minor, currency, razorpay_order_id, receipt")
    .single();

  if (updateError || !updated) {
    console.error("[create-razorpay-order] failed to save razorpay_order_id", { paymentOrderId: order.id, error: updateError?.message });
    return jsonResponse({ error: "Payment order created but could not be saved. Please try again." }, 500);
  }

  console.log("[create-razorpay-order] order created", {
    paymentOrderId: updated.id,
    razorpayOrderId: updated.razorpay_order_id,
    sourceType: body.sourceType,
    amount: updated.amount_minor,
  });

  return jsonResponse(
    {
      keyId: razorpayKeyId,
      razorpayOrderId: updated.razorpay_order_id,
      amount: updated.amount_minor,
      currency: updated.currency,
      paymentOrderId: updated.id,
      receipt: updated.receipt,
    },
    200,
  );
});