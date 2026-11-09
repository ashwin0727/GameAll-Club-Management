// ═══════════════════════════════════════════════════════════════════════════
// sync-player-payment — "did my payment go through?"  (Player app: payment progress → payment success)
//
// The Razorpay webhook is the primary way a membership AutoPay mandate or a coaching payment link / AutoPay becomes a recorded payment.
// But it can be late, retried, or simply not set up for the current (test or live) Razorpay mode: then Razorpay shows the subscription as
// ACTIVE while GameAll still says "payment pending". This function asks Razorpay directly for the real state of the ONE item the player
// is paying for, and saves it through the SAME idempotent database functions the webhook uses, so the two can never double-count
// (record_subscription_charge / record_coaching_gateway_payment dedupe on the Razorpay payment id).
//
//   POST { kind: "membership" | "coaching" | "booking", id: "<membership id | coaching enrolment id | booking id>" }
//   → { changed: boolean, state?: "PAID" | "PENDING" | "FAILED" }      (membership also returns the refreshed state)
//
// Permission is checked under the CALLER's JWT first (get_my_payment_receipt returns null for anything that is not theirs); the write
// functions are service-role only, so they run with the service key AFTER that check, scoped to that one item's own Razorpay ids.
//
// Setup: same secrets as the other payment functions (RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET). Deploy:
//   supabase functions deploy sync-player-payment
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { allowed } from "../_shared/rate-limit.ts";
import { extractLinkPayment, mapPaymentLinkEventToStatus, razorpaySubscriptionStatusToCoaching } from "../_shared/coaching-billing.ts";
import { unixToDateString } from "../_shared/razorpay.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } });
}

async function razorpayGet(path: string, keyId: string, keySecret: string) {
  const res = await fetch(`https://api.razorpay.com/v1${path}`, { headers: { Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}` } });
  const text = await res.text();
  if (!res.ok) throw new Error(`Razorpay GET ${path} failed (${res.status}): ${text}`);
  return JSON.parse(text);
}

/** Razorpay's subscription status words → the membership_subscription_status enum (null = leave it alone). */
function membershipSubscriptionStatus(status: string | undefined | null): string | null {
  switch ((status ?? "").toLowerCase()) {
    case "created": return "created";
    case "authenticated": return "authenticated";
    case "active": return "active";
    case "pending": return "pending";
    case "halted": return "halted";
    case "cancelled": case "expired": return "cancelled";
    case "completed": return "completed";
    default: return null; // paused, or something new: do not guess
  }
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
    console.error("[sync-player-payment] missing function secrets");
    return jsonResponse({ error: "Online payments are not configured yet." }, 500);
  }

  let body: { kind?: string; id?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body." }, 400);
  }
  const kind = (body.kind ?? "").toLowerCase();
  if (!body.id || (kind !== "membership" && kind !== "coaching" && kind !== "booking")) {
    return jsonResponse({ error: "kind (membership | coaching | booking) and id are required." }, 400);
  }

  // 1 · is it really the caller's? (under the caller's own JWT)
  const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });
  const { data: receipt, error: rcptErr } = await userClient.rpc("get_my_payment_receipt", { p_kind: kind, p_id: body.id });
  if (rcptErr) {
    console.error("[sync-player-payment] receipt lookup failed", rcptErr.message);
    return jsonResponse({ error: "Lookup failed." }, 500);
  }
  if (!receipt) return jsonResponse({ error: "Payment not found." }, 404);
  const admin = createClient(supabaseUrl, serviceKey);

  // Razorpay is asked at most a handful of times a minute per item, however often the app polls: a throttled call just reports what the
  // database already says (the webhook keeps that current), so a stuck client cannot turn into a Razorpay storm.
  if (!(await allowed(admin, `sync:${kind}:${body.id}`, 12, 60))) {
    return jsonResponse({ changed: false, state: (receipt as { state?: string }).state ?? null, throttled: true }, 200);
  }
  let changed = false;

  try {
    // ── booking: the one-time payment link made for it (an advance, or the full amount) ──
    if (kind === "booking") {
      const { data: orders } = await admin
        .from("payment_orders")
        .select("razorpay_payment_link_id, payment_link_status, status")
        .eq("booking_id", body.id)
        .not("razorpay_payment_link_id", "is", null)
        .order("created_at", { ascending: false })
        .limit(3);
      for (const o of orders ?? []) {
        const linkId = o.razorpay_payment_link_id as string;
        const rz = await razorpayGet(`/payment_links/${linkId}`, keyId, keySecret);
        if (rz.status === "paid") {
          // same gate the webhook uses; it dedupes on the Razorpay payment id
          const pay = (rz.payments as Array<{ payment_id?: string; amount?: number; status?: string; order_id?: string }> | undefined)?.find((x) => x.status === "captured") ?? (rz.payments as Array<{ payment_id?: string; amount?: number; order_id?: string }> | undefined)?.[0];
          const { data: handled, error } = await admin.rpc("apply_booking_payment_link_event", {
            p_razorpay_payment_link_id: linkId,
            p_event: "paid",
            p_razorpay_order_id: rz.order_id ?? pay?.order_id ?? null,
            p_razorpay_payment_id: pay?.payment_id ?? null,
            p_amount_minor: pay?.amount ?? rz.amount_paid ?? null,
            p_currency: rz.currency ?? "INR",
          });
          if (error && error.code !== "23514") throw new Error(`apply_booking_payment_link_event failed: ${error.message}`);
          changed = changed || handled === true;
          break;
        }
        if ((rz.status === "expired" || rz.status === "cancelled") && o.payment_link_status !== rz.status.toUpperCase()) {
          await admin.rpc("apply_booking_payment_link_event", { p_razorpay_payment_link_id: linkId, p_event: rz.status });
          changed = true;
        }
      }
      const { data: afterBooking } = await userClient.rpc("get_my_payment_receipt", { p_kind: kind, p_id: body.id });
      return jsonResponse({ changed, state: (afterBooking as { state?: string } | null)?.state ?? null }, 200);
    }

    // ── membership: an AutoPay subscription ──
    if (kind === "membership") {
      const { data: sub } = await admin.from("membership_subscriptions").select("razorpay_subscription_id, status, charge_count").eq("membership_id", body.id).maybeSingle();
      if (!sub) return jsonResponse({ changed: false, state: (receipt as { state?: string }).state ?? null }, 200);
      const subId = sub.razorpay_subscription_id as string;
      const rz = await razorpayGet(`/subscriptions/${subId}`, keyId, keySecret);

      // every paid invoice is one cycle's charge: record each (deduped on the Razorpay payment id)
      if ((rz.paid_count ?? 0) > 0) {
        const invoices = await razorpayGet(`/invoices?subscription_id=${encodeURIComponent(subId)}`, keyId, keySecret);
        for (const inv of (invoices.items ?? []) as { status?: string; payment_id?: string; amount_paid?: number; amount?: number; paid_at?: number }[]) {
          if (inv.status !== "paid" || !inv.payment_id) continue;
          const { error } = await admin.rpc("record_subscription_charge", {
            p_razorpay_subscription_id: subId,
            p_amount_inr: Math.round((inv.amount_paid ?? inv.amount ?? 0) / 100),
            p_razorpay_payment_id: inv.payment_id,
            p_paid_at: inv.paid_at ? new Date(inv.paid_at * 1000).toISOString() : new Date().toISOString(),
          });
          if (error) throw new Error(`record_subscription_charge failed: ${error.message}`);
        }
      }
      const status = membershipSubscriptionStatus(rz.status);
      if (status) {
        const { error } = await admin.rpc("apply_subscription_webhook", {
          p_razorpay_subscription_id: subId,
          p_status: status,
          p_charge_count: rz.paid_count ?? null,
          p_current_start: unixToDateString(rz.current_start),
          p_current_end: unixToDateString(rz.current_end),
        });
        if (error) throw new Error(`apply_subscription_webhook failed: ${error.message}`);
        changed = status !== sub.status || (rz.paid_count ?? 0) !== sub.charge_count;
      }
      const { data: after } = await userClient.rpc("get_my_payment_receipt", { p_kind: kind, p_id: body.id });
      return jsonResponse({ changed, state: (after as { state?: string } | null)?.state ?? null }, 200);
    }

    // ── coaching: a payment link (one time) or an AutoPay subscription (monthly) ──
    const { data: ctx, error: ctxErr } = await userClient.rpc("player_get_coaching_billing_context", { p_enrollment_id: body.id });
    if (ctxErr || !ctx) return jsonResponse({ error: "Enrolment not found." }, 404);
    const billing = (ctx as { billing: { kind: string; status: string; chargeCount: number; razorpayPaymentLinkId: string | null; razorpaySubscriptionId: string | null } | null }).billing;
    const LIVE = ["CREATED", "AUTHENTICATED", "ACTIVE", "PENDING", "HALTED"];
    if (!billing || !LIVE.includes(billing.status)) return jsonResponse({ changed: false }, 200);

    if (billing.kind === "PAYMENT_LINK") {
      const linkId = billing.razorpayPaymentLinkId!;
      const link = await razorpayGet(`/payment_links/${linkId}`, keyId, keySecret);
      if (link.status === "paid") {
        const payment = extractLinkPayment(link);
        if (!payment) return jsonResponse({ changed: false, pending: true }, 200); // paid, but not listed yet: next poll
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
    const { data: after } = await userClient.rpc("get_my_payment_receipt", { p_kind: kind, p_id: body.id });
    return jsonResponse({ changed, state: (after as { state?: string } | null)?.state ?? null }, 200);
  } catch (err) {
    console.error("[sync-player-payment] failed", String(err));
    return jsonResponse({ error: "Could not check the payment with Razorpay." }, 502);
  }
});
