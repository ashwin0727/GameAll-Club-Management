// ═══════════════════════════════════════════════════════════════════════════
// reconcile-coaching-enrollment-billing — "did the student pay yet?"
//
// The Razorpay webhook is the primary way a coaching payment link / AutoPay
// subscription becomes a recorded payment, but it can be late, un-configured
// (payment_link.paid not enabled in the dashboard) or retrying. This function
// asks Razorpay directly for the link's / subscription's current state and
// applies it through the SAME idempotent RPCs the webhook uses, so the page
// can reflect a payment the moment the student finishes — and so webhook +
// reconcile can never double-count (record_coaching_gateway_payment dedupes
// on razorpay_payment_id).
//
// Permission is checked under the caller's JWT (get_coaching_billing_context);
// the write RPCs are service-role only, so they run with the service key
// AFTER that check, scoped to the one enrollment's own Razorpay ids.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { extractLinkPayment, mapPaymentLinkEventToStatus, razorpaySubscriptionStatusToCoaching } from "../_shared/coaching-billing.ts";
import { unixToDateString } from "../_shared/razorpay.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } });
}

interface BillingContext {
  billing: {
    kind: "PAYMENT_LINK" | "SUBSCRIPTION";
    status: string;
    chargeCount: number;
    razorpayPaymentLinkId: string | null;
    razorpaySubscriptionId: string | null;
  } | null;
}

const LIVE = ["CREATED", "AUTHENTICATED", "ACTIVE", "PENDING", "HALTED"];

async function razorpayGet(path: string, keyId: string, keySecret: string) {
  const res = await fetch(`https://api.razorpay.com/v1${path}`, {
    headers: { Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}` },
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`Razorpay GET ${path} failed (${res.status}): ${text}`);
  return JSON.parse(text);
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
    console.error("[reconcile-coaching-enrollment-billing] missing function secrets");
    return jsonResponse({ error: "Online payments are not configured yet." }, 500);
  }

  let body: { enrollmentId?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body." }, 400);
  }
  if (!body.enrollmentId) return jsonResponse({ error: "enrollmentId is required." }, 400);

  const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });
  const { data, error: ctxErr } = await userClient.rpc("get_coaching_billing_context", { p_enrollment_id: body.enrollmentId });
  if (ctxErr || !data) {
    if (ctxErr?.code === "42501") return jsonResponse({ error: "You don't have permission to view this payment." }, 403);
    if (ctxErr?.code === "P0002") return jsonResponse({ error: "Enrollment not found." }, 404);
    console.error("[reconcile-coaching-enrollment-billing] context lookup failed", ctxErr?.message);
    return jsonResponse({ error: "Lookup failed." }, 500);
  }
  const billing = (data as BillingContext).billing;
  // Nothing in flight (no billing, or it already finished) — nothing to reconcile.
  if (!billing || !LIVE.includes(billing.status)) {
    return jsonResponse({ status: billing?.status ?? null, changed: false }, 200);
  }

  // Elevated client: ONLY for the idempotent webhook RPCs, after the permission check above.
  const admin = createClient(supabaseUrl, serviceKey);
  let changed = false;

  try {
    if (billing.kind === "PAYMENT_LINK") {
      const linkId = billing.razorpayPaymentLinkId!;
      const link = await razorpayGet(`/payment_links/${linkId}`, keyId, keySecret);

      if (link.status === "paid") {
        const payment = extractLinkPayment(link);
        if (!payment) {
          // Paid, but Razorpay hasn't listed the payment yet — try again on the next poll.
          console.warn("[reconcile-coaching-enrollment-billing] link paid but no payment visible yet", { linkId });
          return jsonResponse({ status: billing.status, changed: false, pending: true }, 200);
        }
        const { error } = await admin.rpc("record_coaching_gateway_payment", {
          p_razorpay_payment_link_id: linkId,
          p_amount_minor: payment.amountMinor,
          p_razorpay_payment_id: payment.paymentId,
          p_paid_at: new Date().toISOString(),
        });
        if (error) throw new Error(`record_coaching_gateway_payment failed: ${error.message}`);
        changed = true;
      } else if (link.status === "cancelled" || link.status === "expired") {
        const status = mapPaymentLinkEventToStatus(`payment_link.${link.status}`);
        const { error } = await admin.rpc("apply_coaching_billing_webhook", { p_razorpay_payment_link_id: linkId, p_status: status });
        if (error) throw new Error(`apply_coaching_billing_webhook failed: ${error.message}`);
        changed = true;
      }
    } else {
      const subId = billing.razorpaySubscriptionId!;
      const sub = await razorpayGet(`/subscriptions/${subId}`, keyId, keySecret);

      // Every paid invoice is one month's charge — record each (deduped on payment id).
      const invoices = await razorpayGet(`/invoices?subscription_id=${encodeURIComponent(subId)}`, keyId, keySecret);
      for (const inv of (invoices.items ?? []) as { status?: string; payment_id?: string; amount_paid?: number; amount?: number; paid_at?: number }[]) {
        if (inv.status !== "paid" || !inv.payment_id) continue;
        const { error } = await admin.rpc("record_coaching_gateway_payment", {
          p_razorpay_subscription_id: subId,
          p_amount_minor: inv.amount_paid ?? inv.amount ?? 0,
          p_razorpay_payment_id: inv.payment_id,
          p_paid_at: inv.paid_at ? new Date(inv.paid_at * 1000).toISOString() : new Date().toISOString(),
        });
        if (error) throw new Error(`record_coaching_gateway_payment failed: ${error.message}`);
      }

      const status = razorpaySubscriptionStatusToCoaching(sub.status);
      const { error } = await admin.rpc("apply_coaching_billing_webhook", {
        p_razorpay_subscription_id: subId,
        p_status: status,
        p_charge_count: sub.paid_count ?? null,
        p_current_start: unixToDateString(sub.current_start),
        p_current_end: unixToDateString(sub.current_end),
      });
      if (error) throw new Error(`apply_coaching_billing_webhook failed: ${error.message}`);
      changed = (status !== null && status !== billing.status) || (sub.paid_count ?? 0) !== billing.chargeCount;
    }
  } catch (err) {
    console.error("[reconcile-coaching-enrollment-billing] failed", String(err));
    return jsonResponse({ error: "Could not check the payment with Razorpay." }, 502);
  }

  return jsonResponse({ changed }, 200);
});
