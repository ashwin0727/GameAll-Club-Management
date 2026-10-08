// ═══════════════════════════════════════════════════════════════════════════
// cancel-coaching-enrollment-billing — stops a coaching enrollment's Razorpay
// payment link / subscription. Called when staff mark the enrollment paid
// another way (e.g. cash at the desk) or cancel the enrollment, so the link
// can no longer be paid and a mandate stops charging every month.
//
// Runs under the caller's staff session; permission is enforced by
// get_coaching_billing_context / mark_coaching_billing_cancelled. Idempotent:
// no billing, or already finished, is a no-op success.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";

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
    razorpayPaymentLinkId: string | null;
    razorpaySubscriptionId: string | null;
  } | null;
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
    console.error("[cancel-coaching-enrollment-billing] missing function secrets");
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
    if (ctxErr?.code === "42501") return jsonResponse({ error: "You don't have permission to change this payment." }, 403);
    if (ctxErr?.code === "P0002") return jsonResponse({ error: "Enrollment not found." }, 404);
    console.error("[cancel-coaching-enrollment-billing] context lookup failed", ctxErr?.message);
    return jsonResponse({ error: "Lookup failed." }, 500);
  }
  const billing = (data as BillingContext).billing;

  // Nothing to stop, or it already finished (paid / cancelled / ran its course).
  if (!billing || ["PAID", "CANCELLED", "COMPLETED", "EXPIRED"].includes(billing.status)) {
    return jsonResponse({ cancelled: true, alreadyDone: true }, 200);
  }

  const path =
    billing.kind === "SUBSCRIPTION"
      ? `/subscriptions/${billing.razorpaySubscriptionId}/cancel`
      : `/payment_links/${billing.razorpayPaymentLinkId}/cancel`;

  try {
    const res = await fetch(`https://api.razorpay.com/v1${path}`, {
      method: "POST",
      headers: { Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}`, "Content-Type": "application/json" },
      // Subscriptions stop immediately — no further cycle may go through.
      body: billing.kind === "SUBSCRIPTION" ? JSON.stringify({ cancel_at_cycle_end: 0 }) : "{}",
    });
    const text = await res.text();
    // "Already cancelled/paid/expired" on Razorpay's side still means nothing is left to charge.
    if (!res.ok && !/already|cannot be cancelled/i.test(text)) {
      throw new Error(`Razorpay cancel failed (${res.status}): ${text}`);
    }

    const { error: markErr } = await supabase.rpc("mark_coaching_billing_cancelled", { p_enrollment_id: body.enrollmentId });
    if (markErr) {
      console.error("[cancel-coaching-enrollment-billing] mark cancelled failed", markErr.message);
      return jsonResponse({ error: "Cancelled with Razorpay but could not update our records." }, 500);
    }
    return jsonResponse({ cancelled: true }, 200);
  } catch (err) {
    console.error("[cancel-coaching-enrollment-billing] razorpay error", String(err));
    return jsonResponse({ error: "Could not cancel the online payment with Razorpay." }, 502);
  }
});
