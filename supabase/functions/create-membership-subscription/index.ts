// ═══════════════════════════════════════════════════════════════════════════
// create-membership-subscription — Membership Subscriptions, Phase 2.
//
// Turns an existing (pending) membership into a Razorpay Subscription so the
// player can authorise a UPI AutoPay mandate once and be charged monthly
// automatically. Callable from:
//   • the signed-in Memberships page (staff creates a recurring link), and
//   • the public /join/<facilityId> page (anon key) — which has already
//     created the membership via public_start_membership_signup.
//
// The amount is ALWAYS read server-side from the membership's plan /
// monthly_price_inr — the client's value is never trusted. Uses the service
// role because the public flow has no user session; every read is
// explicitly scoped to the membership id passed in.
//
// Setup:
//   supabase secrets set RAZORPAY_KEY_ID=rzp_test_xxx
//   supabase secrets set RAZORPAY_KEY_SECRET=your_secret
// Razorpay Dashboard → Subscriptions must be enabled on the account.
// Add these webhook events (razorpay-webhook): subscription.authenticated,
//   subscription.activated, subscription.charged, subscription.pending,
//   subscription.halted, subscription.cancelled, subscription.completed.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

interface Req {
  membershipId: string;
  /** How many monthly cycles to authorise the mandate for (default 120 = 10 years). */
  totalCount?: number;
}

async function razorpay(path: string, keyId: string, keySecret: string, body: unknown) {
  const res = await fetch(`https://api.razorpay.com/v1${path}`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`Razorpay ${path} failed (${res.status}): ${text}`);
  return JSON.parse(text);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const keyId = Deno.env.get("RAZORPAY_KEY_ID");
  const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
  if (!supabaseUrl || !serviceRoleKey || !keyId || !keySecret) {
    console.error("[create-membership-subscription] missing function secrets");
    return jsonResponse({ error: "Subscriptions are not configured yet." }, 500);
  }

  let payload: Req;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body." }, 400);
  }
  if (!payload.membershipId) return jsonResponse({ error: "membershipId is required." }, 400);

  const supabase = createClient(supabaseUrl, serviceRoleKey);

  const { data: membership, error: mErr } = await supabase
    .from("memberships")
    .select("id, facility_id, member_id, plan_id, monthly_price_inr, membership_plans(name, price_inr, duration_days)")
    .eq("id", payload.membershipId)
    .maybeSingle();
  if (mErr) return jsonResponse({ error: "Lookup failed." }, 500);
  if (!membership) return jsonResponse({ error: "Membership not found." }, 404);

  const { data: existing } = await supabase
    .from("membership_subscriptions")
    .select("razorpay_subscription_id, short_url")
    .eq("membership_id", payload.membershipId)
    .maybeSingle();
  if (existing) {
    return jsonResponse({ subscriptionId: existing.razorpay_subscription_id, shortUrl: existing.short_url, keyId, reused: true }, 200);
  }

  const plan = (membership as { membership_plans?: { name?: string; price_inr?: number; duration_days?: number } }).membership_plans;
  const amountInr = membership.monthly_price_inr ?? plan?.price_inr ?? 0;
  if (amountInr <= 0) return jsonResponse({ error: "This plan has no recurring price." }, 400);
  const amountMinor = amountInr * 100;
  const totalCount = Math.min(Math.max(payload.totalCount ?? 120, 1), 1200);

  try {
    const rzpPlan = await razorpay("/plans", keyId, keySecret, {
      period: "monthly",
      interval: 1,
      item: { name: `${plan?.name ?? "Membership"} · monthly`, amount: amountMinor, currency: "INR" },
      notes: { facility_id: membership.facility_id, plan_id: membership.plan_id },
    });

    const subscription = await razorpay("/subscriptions", keyId, keySecret, {
      plan_id: rzpPlan.id,
      total_count: totalCount,
      quantity: 1,
      customer_notify: 1,
      notes: { membership_id: membership.id, facility_id: membership.facility_id },
    });

    const { error: recErr } = await supabase.rpc("record_membership_subscription", {
      p_membership_id: membership.id,
      p_razorpay_plan_id: rzpPlan.id,
      p_razorpay_subscription_id: subscription.id,
      p_amount_inr: amountInr,
      p_short_url: subscription.short_url ?? null,
      p_razorpay_customer_id: subscription.customer_id ?? null,
    });
    if (recErr) {
      console.error("[create-membership-subscription] record_membership_subscription failed", recErr.message);
      return jsonResponse({ error: "Could not save the subscription." }, 500);
    }

    return jsonResponse({ subscriptionId: subscription.id, shortUrl: subscription.short_url, keyId }, 200);
  } catch (err) {
    console.error("[create-membership-subscription] razorpay error", String(err));
    return jsonResponse({ error: "Could not start the subscription with Razorpay." }, 502);
  }
});