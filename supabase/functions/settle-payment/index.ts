// ═══════════════════════════════════════════════════════════════════════════
// settle-payment — Payment Settlement & Business Confirmation, Phase 5.
//
// Settlement normally already happened automatically: apply_payment_verification
// (0019/0021) calls settle_payment inline the moment a payment order genuinely
// transitions to CAPTURED, in the same transaction as the capture itself. This
// function exists for the retry/manual-recovery case the spec explicitly asks
// for — a payment order stuck at CAPTURED because settlement hit a transient
// DB failure that time (rather than a business rejection, which already
// resolved to SETTLEMENT_EXCEPTION and won't change by retrying). Staff can
// call this to retry; it is fully idempotent either way.
//
// Runs under the CALLER's own Supabase session, same pattern as every other
// client-facing payment function — a staff member can only settle a payment
// order their own facility-scoped RLS lets them see.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface SettleRequest {
  paymentOrderId: string;
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } });
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
  if (!supabaseUrl || !supabaseAnonKey) {
    console.error("[settle-payment] missing SUPABASE_URL/SUPABASE_ANON_KEY function secrets");
    return jsonResponse({ error: "Server is not configured correctly." }, 500);
  }

  let body: SettleRequest;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid request body." }, 400);
  }
  if (!body.paymentOrderId) {
    return jsonResponse({ error: "paymentOrderId is required." }, 400);
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, { global: { headers: { Authorization: authHeader } } });

  const { data, error } = await supabase.rpc("settle_payment", { p_payment_order_id: body.paymentOrderId });

  if (error || !data) {
    console.error("[settle-payment] settle_payment failed", { paymentOrderId: body.paymentOrderId, code: error?.code, message: error?.message });
    // Not ready for settlement (not yet CAPTURED) or not found/not visible
    // to this caller's facility — same generic message either way, never
    // leaking which.
    return jsonResponse({ error: "Unable to settle this payment right now." }, 400);
  }

  console.log("[settle-payment] settled", { paymentOrderId: data.id, status: data.status });
  return jsonResponse({ paymentOrderId: data.id, status: data.status }, 200);
});