// ═══════════════════════════════════════════════════════════════════════════
// cancel-membership-subscription — counterpart to create-membership-
// subscription, for the "Generate Payment Link, then Mark as Paid instead"
// case in the Add Member wizard: the member paid a different way (e.g. cash
// at the desk) before ever using the Razorpay AutoPay link, so the mandate
// this membership generated must actually be cancelled with Razorpay — not
// just ignored — or it keeps charging every month regardless.
//
// Idempotent: a membership with no subscription, or one already cancelled,
// is a no-op success rather than an error, since the wizard may call this
// defensively.
//
// Setup: reuses the same RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET secrets as
// create-membership-subscription.
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
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const keyId = Deno.env.get("RAZORPAY_KEY_ID");
  const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
  if (!supabaseUrl || !serviceRoleKey || !keyId || !keySecret) {
    console.error("[cancel-membership-subscription] missing function secrets");
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

  const { data: sub, error: subErr } = await supabase
    .from("membership_subscriptions")
    .select("razorpay_subscription_id, status")
    .eq("membership_id", payload.membershipId)
    .maybeSingle();
  if (subErr) return jsonResponse({ error: "Lookup failed." }, 500);
  // No subscription to cancel — the member never had one, or it's already gone. Not an error.
  if (!sub) return jsonResponse({ cancelled: true, alreadyCancelled: true }, 200);
  if (sub.status === "cancelled" || sub.status === "completed") {
    return jsonResponse({ cancelled: true, alreadyCancelled: true }, 200);
  }

  try {
    const res = await fetch(`https://api.razorpay.com/v1/subscriptions/${sub.razorpay_subscription_id}/cancel`, {
      method: "POST",
      headers: {
        Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}`,
        "Content-Type": "application/json",
      },
      // Stop immediately — the member is being marked paid another way right now, so no further
      // cycle at the end of the current period should go through either.
      body: JSON.stringify({ cancel_at_cycle_end: 0 }),
    });
    const text = await res.text();
    // Razorpay 400s "already cancelled" if the mandate was never authorised — treat that as
    // success too, since the end state (nothing left to charge) is exactly what's wanted.
    if (!res.ok && !text.includes("already been cancelled")) {
      throw new Error(`Razorpay cancel failed (${res.status}): ${text}`);
    }

    const { error: updErr } = await supabase.rpc("apply_subscription_webhook", {
      p_razorpay_subscription_id: sub.razorpay_subscription_id,
      p_status: "cancelled",
    });
    if (updErr) {
      console.error("[cancel-membership-subscription] apply_subscription_webhook failed", updErr.message);
      return jsonResponse({ error: "Cancelled with Razorpay but could not update our records." }, 500);
    }

    return jsonResponse({ cancelled: true }, 200);
  } catch (err) {
    console.error("[cancel-membership-subscription] razorpay error", String(err));
    return jsonResponse({ error: "Could not cancel the subscription with Razorpay." }, 502);
  }
});
