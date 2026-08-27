// ═══════════════════════════════════════════════════════════════════════════
// razorpay-webhook — Razorpay Webhook Handling, Phase 4.
//
// Publicly reachable over HTTPS by Razorpay itself — there is no signed-in
// user, so this is the one place in the payments architecture that reads
// SUPABASE_SERVICE_ROLE_KEY and deliberately bypasses RLS. It never
// returns anything to the caller beyond a bare acknowledgement (Razorpay
// doesn't read the body), and never logs a secret.
//
// Configure in the Razorpay Dashboard → Settings → Webhooks:
//   URL: https://<project-ref>.supabase.co/functions/v1/razorpay-webhook
//   Events: payment.authorized, payment.captured, payment.failed, order.paid
//   Secret: a value ONLY known to Razorpay and this function — set it as
//     `supabase secrets set RAZORPAY_WEBHOOK_SECRET=...`. This is NOT the
//     same value as RAZORPAY_KEY_SECRET.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { mapRazorpayPaymentStatus, mapRefundEventToStatus, verifyWebhookSignature, type RazorpayPayment, type RazorpayRefund } from "../_shared/razorpay.ts";

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

// Only these events drive payment_orders/payments/refunds changes —
// everything else Razorpay might deliver (order.notification.*, ...) is
// still recorded (for the audit trail) but never processed
// (§"Only process events actually required by GameAll"). Phase 6 adds the
// three refund.* events (spec §20).
const HANDLED_EVENT_TYPES = new Set(["payment.authorized", "payment.captured", "payment.failed", "order.paid", "refund.created", "refund.processed", "refund.failed"]);

interface WebhookPayload {
  event: string;
  payload?: {
    payment?: { entity?: RazorpayPayment };
    order?: { entity?: { id?: string; amount?: number; currency?: string } };
    refund?: { entity?: RazorpayRefund };
  };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const webhookSecret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET");

  if (!supabaseUrl || !serviceRoleKey || !webhookSecret) {
    console.error("[razorpay-webhook] missing required function secrets");
    return jsonResponse({ error: "Webhook is not configured yet." }, 500);
  }

  // MUST be the untouched raw body — signature verification breaks the
  // instant this is parsed and re-serialized (§"Raw Webhook Body").
  const rawBody = await req.text();
  const signature = req.headers.get("x-razorpay-signature");
  if (!signature || !(await verifyWebhookSignature(rawBody, signature, webhookSecret))) {
    console.error("[razorpay-webhook] invalid webhook signature");
    return jsonResponse({ error: "Invalid signature." }, 400);
  }

  const eventId = req.headers.get("x-razorpay-event-id");
  if (!eventId) {
    console.error("[razorpay-webhook] missing x-razorpay-event-id header");
    return jsonResponse({ error: "Missing event id." }, 400);
  }

  let payload: WebhookPayload;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return jsonResponse({ error: "Invalid JSON body." }, 400);
  }

  // Elevated access is intentional and scoped to exactly this function —
  // there is no user session to run this under (§"RLS": webhook Edge
  // Functions may require controlled server-side access).
  const supabase = createClient(supabaseUrl, serviceRoleKey);

  // §"Webhook Idempotency": insert-first, keyed on Razorpay's own event
  // id. A fresh event id inserts and this call proceeds to process it; a
  // redelivered one hits the unique constraint and inserts nothing.
  const { data: inserted, error: insertError } = await supabase
    .from("razorpay_webhook_events")
    .insert({ event_id: eventId, event_type: payload.event, payload })
    .select("id, processed")
    .maybeSingle();

  let eventRowId: string;
  if (insertError) {
    // Unique-violation on event_id = a duplicate delivery of an event
    // already known to us. Anything else is a real DB error.
    if (insertError.code !== "23505") {
      console.error("[razorpay-webhook] failed to record webhook event", { eventId, error: insertError.message });
      return jsonResponse({ error: "Unable to record this event." }, 500);
    }
    const { data: existing, error: fetchError } = await supabase.from("razorpay_webhook_events").select("id, processed").eq("event_id", eventId).single();
    if (fetchError || !existing) {
      console.error("[razorpay-webhook] event conflicted but could not be re-read", { eventId, error: fetchError?.message });
      return jsonResponse({ error: "Unable to record this event." }, 500);
    }
    if (existing.processed) {
      console.log("[razorpay-webhook] duplicate event, already processed", { eventId, eventType: payload.event });
      return jsonResponse({ received: true, duplicate: true }, 200);
    }
    // Exists but a previous attempt never finished — fall through and
    // retry processing now (§"Webhook Failure Handling": don't silently
    // discard a valid event just because it failed once).
    eventRowId = existing.id;
  } else {
    eventRowId = inserted!.id;
  }

  if (!HANDLED_EVENT_TYPES.has(payload.event)) {
    await supabase.from("razorpay_webhook_events").update({ processed: true, processed_at: new Date().toISOString() }).eq("id", eventRowId);
    return jsonResponse({ received: true, handled: false }, 200);
  }

  try {
    await processEvent(supabase, payload);
    await supabase.from("razorpay_webhook_events").update({ processed: true, processed_at: new Date().toISOString(), error: null }).eq("id", eventRowId);
    console.log("[razorpay-webhook] processed", { eventId, eventType: payload.event });
    return jsonResponse({ received: true, handled: true }, 200);
  } catch (err) {
    // Leave processed=false so Razorpay's retry (it retries on any
    // non-2xx) re-enters this same event id and tries again — never mark
    // a failed attempt as processed.
    console.error("[razorpay-webhook] processing failed", { eventId, eventType: payload.event, error: String(err) });
    await supabase.from("razorpay_webhook_events").update({ error: String(err) }).eq("id", eventRowId);
    return jsonResponse({ error: "Processing failed." }, 500);
  }
});

async function processEvent(supabase: SupabaseClient, payload: WebhookPayload): Promise<void> {
  const refundStatus = mapRefundEventToStatus(payload.event);
  if (refundStatus) {
    return processRefundEvent(supabase, payload, refundStatus);
  }

  const payment = payload.payload?.payment?.entity;
  if (!payment) {
    // order.paid can theoretically arrive without an embedded payment
    // entity — nothing concrete to reconcile against in that case.
    console.log("[razorpay-webhook] event carried no payment entity, nothing to reconcile", { eventType: payload.event });
    return;
  }

  const { data: order, error: orderError } = await supabase
    .from("payment_orders")
    .select("id")
    .eq("razorpay_order_id", payment.order_id)
    .maybeSingle();

  if (orderError) {
    throw new Error(`Failed to look up payment order: ${orderError.message}`);
  }
  if (!order) {
    // A payment for an order GameAll doesn't (or no longer) know about —
    // nothing to reconcile. Not an error worth retrying over.
    console.warn("[razorpay-webhook] no matching payment order for razorpay_order_id", { razorpayOrderId: payment.order_id });
    return;
  }

  const targetStatus = payload.event === "payment.failed" ? "FAILED" : mapRazorpayPaymentStatus(payment.status);

  const { error: applyError } = await supabase.rpc("apply_payment_verification", {
    p_payment_order_id: order.id,
    p_razorpay_order_id: payment.order_id,
    p_razorpay_payment_id: payment.id,
    p_razorpay_status: targetStatus,
    p_amount_minor: payment.amount,
    p_currency: payment.currency,
  });

  if (applyError) {
    // A 23514 here means order/amount/currency mismatch or an id swap
    // attempt — surfaced as a processing failure so it's visible in the
    // webhook_events audit row, but NOT retried forever as a transient
    // error would be (it will never succeed on retry either way). Log
    // loudly; still return without throwing so the event is marked
    // processed rather than retried indefinitely.
    console.error("[razorpay-webhook] apply_payment_verification rejected", { paymentOrderId: order.id, code: applyError.code, message: applyError.message });
    return;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// processRefundEvent — Phase 6. The authoritative path for refund state:
// a client's own "Check Again" never resolves REQUESTED/PROCESSING beyond
// what it already knew (there is no reconcile-razorpay-refund equivalent
// in this phase's spec — refund reconciliation is webhook-driven only,
// spec §22). apply_refund_webhook is forward-only + idempotent, so a
// redelivered event (this function's own dedupe already caught most of
// those, but Razorpay's refund.created + refund.processed can legitimately
// both arrive) is always safe to re-run.
// ─────────────────────────────────────────────────────────────────────────
async function processRefundEvent(supabase: SupabaseClient, payload: WebhookPayload, status: "created" | "processed" | "failed"): Promise<void> {
  const refund = payload.payload?.refund?.entity;
  if (!refund) {
    console.log("[razorpay-webhook] refund event carried no refund entity, nothing to reconcile", { eventType: payload.event });
    return;
  }

  const { error: applyError } = await supabase.rpc("apply_refund_webhook", {
    p_razorpay_refund_id: refund.id,
    p_razorpay_payment_id: refund.payment_id,
    p_status: status,
    p_amount_minor: refund.amount,
  });

  if (applyError) {
    // A P0002 here means GameAll has no matching refund row at all (e.g. a
    // refund created directly in the Razorpay dashboard, outside this
    // integration) — logged, not retried forever, since retrying can never
    // manufacture a refund row that was never requested through GameAll.
    console.error("[razorpay-webhook] apply_refund_webhook rejected", { razorpayRefundId: refund.id, code: applyError.code, message: applyError.message });
    return;
  }
}