// ═══════════════════════════════════════════════════════════════════════════
// cancel-membership — Cancellation, Refund & Payment Recovery, Phase 6.
//
// Membership cancellation is deliberately NOT policy/time-driven (spec §14/
// §15) — the caller (owner/manager) explicitly decides the refund amount,
// if any. Omitting refundAmountMinor cancels the membership with no refund
// at all.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { submitRequestedRefund } from "../_shared/submit-refund.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface CancelRequest {
  membershipId: string;
  reason?: string;
  refundAmountMinor?: number;
  overrideReason?: string;
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return jsonResponse({ error: "Not authenticated" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const razorpayKeyId = Deno.env.get("RAZORPAY_KEY_ID");
  const razorpayKeySecret = Deno.env.get("RAZORPAY_KEY_SECRET");

  if (!supabaseUrl || !supabaseAnonKey) {
    console.error("[cancel-membership] missing required function secrets");
    return jsonResponse({ error: "This action is not configured yet." }, 500);
  }

  let body: CancelRequest;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid request body." }, 400);
  }
  if (!body.membershipId) return jsonResponse({ error: "membershipId is required." }, 400);

  const supabase = createClient(supabaseUrl, supabaseAnonKey, { global: { headers: { Authorization: authHeader } } });

  const { data: membership, error: cancelError } = await supabase.rpc("cancel_membership", {
    p_membership_id: body.membershipId,
    p_reason: body.reason ?? null,
    p_refund_amount_minor: body.refundAmountMinor ?? null,
    p_override_reason: body.overrideReason ?? null,
  });

  if (cancelError || !membership) {
    console.error("[cancel-membership] cancel_membership rejected", { membershipId: body.membershipId, message: cancelError?.message });
    const message = cancelError?.message?.startsWith("The maximum refundable amount") || cancelError?.message?.includes("not cancellable") || cancelError?.message?.includes("No captured")
      ? cancelError.message
      : "This membership could not be cancelled.";
    return jsonResponse({ error: message }, 400);
  }

  if (!body.refundAmountMinor || body.refundAmountMinor <= 0) {
    return jsonResponse({ membership, refund: null }, 200);
  }

  const { data: refunds } = await supabase
    .from("refunds")
    .select("id, status")
    .eq("source_id", body.membershipId)
    .in("status", ["REQUESTED"])
    .order("created_at", { ascending: false })
    .limit(1);

  const pendingRefund = refunds?.[0];
  if (!pendingRefund) {
    return jsonResponse({ membership, refund: null }, 200);
  }

  if (!razorpayKeyId || !razorpayKeySecret) {
    console.error("[cancel-membership] refund created but Razorpay is not configured");
    return jsonResponse({ membership, refund: { id: pendingRefund.id, status: pendingRefund.status } }, 200);
  }

  const submitted = await submitRequestedRefund(supabase, pendingRefund.id, razorpayKeyId, razorpayKeySecret);
  return jsonResponse({ membership, refund: submitted }, 200);
});