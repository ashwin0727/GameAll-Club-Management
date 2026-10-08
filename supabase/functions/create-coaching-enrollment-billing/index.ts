// ═══════════════════════════════════════════════════════════════════════════
// create-coaching-enrollment-billing — Razorpay online payment for a coaching
// enrollment.
//
//   ONE_TIME program → a Razorpay Payment Link for the outstanding fee; the
//                      student pays once and `payment_link.paid` settles it.
//   MONTHLY  program → a Razorpay Subscription (UPI AutoPay): the student
//                      approves the mandate once, then the per-month fee is
//                      charged every month for `billing_cycles` cycles — i.e.
//                      until the program's end date.
//
// Runs under the CALLER's staff session (JWT). Every figure — the amount,
// the cycle count, the student's contact — is read server-side through
// get_coaching_billing_context, which also enforces COACHING_MANAGE_
// ENROLLMENTS; nothing money-related is trusted from the request body.
// Idempotent: a live link/subscription for the enrollment is returned as-is.
//
// Setup (shared with the membership functions):
//   supabase secrets set RAZORPAY_KEY_ID=rzp_test_xxx RAZORPAY_KEY_SECRET=...
// Razorpay Dashboard → Payment Links AND Subscriptions must be enabled.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { cycleAmountMinor, toRazorpayContact } from "../_shared/coaching-billing.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } });
}

interface BillingContext {
  enrollmentId: string;
  facilityId: string;
  status: string;
  feeType: "ONE_TIME" | "MONTHLY";
  billingCycles: number;
  priceMinor: number;
  paidMinor: number;
  outstandingMinor: number;
  programName: string;
  memberName: string | null;
  memberPhone: string | null;
  memberEmail: string | null;
  billing: { kind: string; status: string; shortUrl: string | null } | null;
}

async function razorpay(path: string, keyId: string, keySecret: string, body: unknown) {
  const res = await fetch(`https://api.razorpay.com/v1${path}`, {
    method: "POST",
    headers: { Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`Razorpay ${path} failed (${res.status}): ${text}`);
  return JSON.parse(text);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return jsonResponse({ error: "Not authenticated" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const keyId = Deno.env.get("RAZORPAY_KEY_ID");
  const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
  if (!supabaseUrl || !anonKey || !keyId || !keySecret) {
    console.error("[create-coaching-enrollment-billing] missing function secrets");
    return jsonResponse({ error: "Online payments are not configured yet." }, 500);
  }

  let body: { enrollmentId?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body." }, 400);
  }
  if (!body.enrollmentId) return jsonResponse({ error: "enrollmentId is required." }, 400);

  const supabase = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });

  const { data, error: ctxErr } = await supabase.rpc("get_coaching_billing_context", { p_enrollment_id: body.enrollmentId });
  if (ctxErr || !data) {
    if (ctxErr?.code === "42501") return jsonResponse({ error: "You don't have permission to collect this payment." }, 403);
    if (ctxErr?.code === "P0002") return jsonResponse({ error: "Enrollment not found." }, 404);
    console.error("[create-coaching-enrollment-billing] context lookup failed", ctxErr?.message);
    return jsonResponse({ error: "Lookup failed." }, 500);
  }
  const ctx = data as BillingContext;

  if (ctx.status === "CANCELLED") return jsonResponse({ error: "This enrollment is cancelled." }, 400);

  // Already set up → hand back the same link instead of creating a second mandate.
  if (ctx.billing && !["CANCELLED", "EXPIRED"].includes(ctx.billing.status)) {
    return jsonResponse({ kind: ctx.billing.kind, shortUrl: ctx.billing.shortUrl, status: ctx.billing.status, reused: true }, 200);
  }

  if (ctx.outstandingMinor <= 0) return jsonResponse({ error: "There is nothing left to collect for this enrollment." }, 400);

  const contact = toRazorpayContact(ctx.memberPhone);
  const email = ctx.memberEmail?.trim() || null;

  try {
    if (ctx.feeType === "MONTHLY") {
      if (ctx.paidMinor > 0) {
        return jsonResponse({ error: "A payment was already recorded for this enrollment, so monthly auto-pay can't be set up." }, 400);
      }
      const perCycle = cycleAmountMinor(ctx.priceMinor, ctx.billingCycles);
      if (perCycle === null) {
        return jsonResponse({ error: "This enrollment's fee doesn't split evenly across its months. Check the program dates and price." }, 400);
      }

      const plan = await razorpay("/plans", keyId, keySecret, {
        period: "monthly",
        interval: 1,
        item: { name: `${ctx.programName} · monthly`, amount: perCycle, currency: "INR" },
        notes: { enrollment_id: ctx.enrollmentId, facility_id: ctx.facilityId },
      });
      const subscription = await razorpay("/subscriptions", keyId, keySecret, {
        plan_id: plan.id,
        total_count: ctx.billingCycles,
        quantity: 1,
        customer_notify: 1,
        ...(contact || email ? { notify_info: { ...(contact ? { notify_phone: contact } : {}), ...(email ? { notify_email: email } : {}) } } : {}),
        notes: { enrollment_id: ctx.enrollmentId, facility_id: ctx.facilityId },
      });

      const { error: recErr } = await supabase.rpc("record_coaching_enrollment_billing", {
        p_enrollment_id: ctx.enrollmentId,
        p_kind: "SUBSCRIPTION",
        p_amount_minor: perCycle,
        p_total_cycles: ctx.billingCycles,
        p_plan_id: plan.id,
        p_subscription_id: subscription.id,
        p_short_url: subscription.short_url ?? null,
      });
      if (recErr) {
        console.error("[create-coaching-enrollment-billing] record failed", recErr.message);
        return jsonResponse({ error: "Could not save the subscription." }, 500);
      }
      return jsonResponse({ kind: "SUBSCRIPTION", shortUrl: subscription.short_url ?? null, status: "CREATED", cycles: ctx.billingCycles, amountMinor: perCycle }, 200);
    }

    // ONE_TIME — a payment link for whatever is still outstanding.
    const link = await razorpay("/payment_links", keyId, keySecret, {
      amount: ctx.outstandingMinor,
      currency: "INR",
      accept_partial: false,
      reference_id: ctx.enrollmentId,
      description: `${ctx.programName} — coaching fee`,
      customer: {
        ...(ctx.memberName ? { name: ctx.memberName } : {}),
        ...(contact ? { contact } : {}),
        ...(email ? { email } : {}),
      },
      notify: { sms: Boolean(contact), email: Boolean(email) },
      reminder_enable: true,
      notes: { enrollment_id: ctx.enrollmentId, facility_id: ctx.facilityId },
    });

    const { error: recErr } = await supabase.rpc("record_coaching_enrollment_billing", {
      p_enrollment_id: ctx.enrollmentId,
      p_kind: "PAYMENT_LINK",
      p_amount_minor: ctx.outstandingMinor,
      p_total_cycles: 1,
      p_payment_link_id: link.id,
      p_short_url: link.short_url ?? null,
    });
    if (recErr) {
      console.error("[create-coaching-enrollment-billing] record failed", recErr.message);
      return jsonResponse({ error: "Could not save the payment link." }, 500);
    }
    return jsonResponse({ kind: "PAYMENT_LINK", shortUrl: link.short_url ?? null, status: "CREATED", amountMinor: ctx.outstandingMinor }, 200);
  } catch (err) {
    console.error("[create-coaching-enrollment-billing] razorpay error", String(err));
    return jsonResponse({ error: "Could not set up the online payment with Razorpay." }, 502);
  }
});
