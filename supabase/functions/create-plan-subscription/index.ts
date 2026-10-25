// ═══════════════════════════════════════════════════════════════════════════
// create-plan-subscription — the club's own GameAll plan (Basic / Advanced).
//
// Two steps, both called by the signed-in OWNER:
//   action "start"   — validates the choice (begin_plan_change) and creates a Razorpay Subscription for the plan's price on the
//                      chosen cadence (monthly / yearly). The first plan has its first charge three months out, so the owner
//                      authorises the mandate now and nothing is charged until then: the subscription's start_at is that date.
//   action "confirm" — after Razorpay Checkout returns, verifies the signature, switches the plan on (activate_plan_checkout) and
//                      cancels the subscription it replaces, if any.
//
// The amount is always read from the plans table on the server — never from the client. Later cycles are collected by Razorpay;
// the razorpay-webhook function keeps the club's valid_till and status in step.
//
// Uses the same secrets as the membership subscriptions:
//   RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET (Subscriptions must be enabled on the Razorpay account).
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { verifyPaymentSignature } from "../_shared/razorpay.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } });
}

type Body =
  | { action: "start"; facilityId: string; planCode: string; interval: "month" | "year" }
  | { action: "confirm"; subscriptionId: string; paymentId: string; signature: string };

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

/** yyyy-mm-dd → unix seconds at 09:30 IST on that day (Razorpay needs start_at in the future). */
function startAtSeconds(isoDate: string): number {
  const [y, m, d] = isoDate.split("-").map(Number);
  return Math.floor(Date.UTC(y!, m! - 1, d!, 4, 0, 0) / 1000);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const keyId = Deno.env.get("RAZORPAY_KEY_ID");
  const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
  if (!url || !anonKey || !serviceRoleKey || !keyId || !keySecret) {
    console.error("[create-plan-subscription] missing function secrets");
    return jsonResponse({ error: "Plan billing is not configured yet." }, 500);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return jsonResponse({ error: "Sign in to choose a plan." }, 401);
  const asCaller = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
  const callerId = (await asCaller.auth.getUser()).data.user?.id ?? null;
  if (!callerId) return jsonResponse({ error: "Sign in to choose a plan." }, 401);

  let body: Body;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body." }, 400);
  }
  const admin = createClient(url, serviceRoleKey);

  if (body.action === "start") {
    if (!body.facilityId || !body.planCode || !["month", "year"].includes(body.interval)) {
      return jsonResponse({ error: "facilityId, planCode and interval are required." }, 400);
    }
    // Owner check, plan limits, price and first-charge date all live in the database.
    const { data: choice, error } = await asCaller.rpc("begin_plan_change", {
      p_facility_id: body.facilityId,
      p_plan_code: body.planCode,
      p_interval: body.interval,
    });
    if (error) return jsonResponse({ error: error.message }, error.code === "42501" ? 403 : 400);
    const c = choice as {
      planCode: string; planName: string; interval: "month" | "year"; amountMinor: number; currency: string;
      trial: boolean; firstChargeOn: string | null;
    };

    try {
      const rzpPlan = await razorpay("/plans", keyId, keySecret, {
        period: c.interval === "year" ? "yearly" : "monthly",
        interval: 1,
        item: { name: `GameAll ${c.planName} · ${c.interval === "year" ? "yearly" : "monthly"}`, amount: c.amountMinor, currency: c.currency },
        notes: { facility_id: body.facilityId, plan_code: c.planCode },
      });
      const subscription = await razorpay("/subscriptions", keyId, keySecret, {
        plan_id: rzpPlan.id,
        total_count: c.interval === "year" ? 10 : 120,
        quantity: 1,
        customer_notify: 1,
        ...(c.firstChargeOn ? { start_at: startAtSeconds(c.firstChargeOn) } : {}),
        notes: { facility_id: body.facilityId, plan_code: c.planCode, kind: "gameall_plan" },
      });
      const { error: recErr } = await admin.rpc("record_plan_checkout", {
        p_facility_id: body.facilityId,
        p_plan_code: c.planCode,
        p_interval: c.interval,
        p_razorpay_subscription_id: subscription.id,
        p_first_charge_on: c.firstChargeOn,
        p_is_trial: c.trial,
        p_user: callerId,
      });
      if (recErr) {
        console.error("[create-plan-subscription] record_plan_checkout failed", recErr.message);
        return jsonResponse({ error: "Could not save your plan choice." }, 500);
      }
      return jsonResponse(
        {
          subscriptionId: subscription.id,
          keyId,
          planName: c.planName,
          interval: c.interval,
          amountMinor: c.amountMinor,
          trial: c.trial,
          firstChargeOn: c.firstChargeOn,
        },
        200,
      );
    } catch (err) {
      console.error("[create-plan-subscription] razorpay error", String(err));
      return jsonResponse({ error: "Could not start the plan payment with Razorpay." }, 502);
    }
  }

  if (body.action === "confirm") {
    if (!body.subscriptionId || !body.paymentId || !body.signature) {
      return jsonResponse({ error: "subscriptionId, paymentId and signature are required." }, 400);
    }
    // For subscriptions the signed text is `${paymentId}|${subscriptionId}`.
    const ok = await verifyPaymentSignature(body.paymentId, body.subscriptionId, body.signature, keySecret);
    if (!ok) return jsonResponse({ error: "We couldn't verify that payment." }, 400);

    const { data: checkout } = await admin
      .from("plan_checkouts")
      .select("created_by")
      .eq("razorpay_subscription_id", body.subscriptionId)
      .maybeSingle();
    if (!checkout || checkout.created_by !== callerId) return jsonResponse({ error: "Plan checkout not found." }, 404);

    const { data: activated, error } = await admin.rpc("activate_plan_checkout", { p_razorpay_subscription_id: body.subscriptionId });
    if (error) {
      console.error("[create-plan-subscription] activate_plan_checkout failed", error.message);
      return jsonResponse({ error: "Could not switch your plan on." }, 500);
    }

    // The plan this one replaces stops billing now (best effort — the new one is already authorised).
    const replaced = (activated as { replacedSubscriptionId: string | null } | null)?.replacedSubscriptionId;
    if (replaced && replaced !== body.subscriptionId) {
      try {
        await razorpay(`/subscriptions/${replaced}/cancel`, keyId, keySecret, { cancel_at_cycle_end: 0 });
      } catch (err) {
        console.error("[create-plan-subscription] could not cancel the replaced subscription", String(err));
      }
    }
    return jsonResponse({ ok: true }, 200);
  }

  return jsonResponse({ error: "Unknown action." }, 400);
});
