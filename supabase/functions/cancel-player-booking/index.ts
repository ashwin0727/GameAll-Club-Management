// ═══════════════════════════════════════════════════════════════════════════
// cancel-player-booking — a signed-in player previews and cancels THEIR OWN court booking (Player app: Guest Booking → Cancel).
//
//   { action: "quote",  bookingId }   → what cancelling right now would do: the hours left, the % deducted, the refund amount and the
//                                       sentence to show the player (get_my_booking_cancellation_quote, migration 0188).
//   { action: "cancel", bookingId }   → cancels it (player_cancel_booking), then sends the refund to Razorpay in the same request, so the
//                                       player sees the real outcome. A booking that is only part-paid (the 50% advance) gets no refund;
//                                       a fully paid one gets the schedule (5% deducted with 12 h or more left ... 100% under 1 h).
//
// Who is asking comes from the caller's JWT, and the database checks the booking is theirs. Money only moves through the REQUESTED
// refund rows the database creates: this function never decides an amount, it only submits them (claim_refund_for_submission makes a
// double submit impossible).
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { allowed } from "../_shared/rate-limit.ts";
import { submitRequestedRefund } from "../_shared/submit-refund.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Please sign in." }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const keyId = Deno.env.get("RAZORPAY_KEY_ID");
  const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
  if (!url || !anon || !service) {
    console.error("[cancel-player-booking] missing function secrets");
    return json({ error: "This is temporarily unavailable. Please try again later." }, 500);
  }

  let body: { action?: string; bookingId?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }
  if (!body.bookingId) return json({ error: "bookingId is required." }, 400);
  const action = body.action === "cancel" ? "cancel" : "quote";

  const asPlayer = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
  const admin = createClient(url, service);

  const { data: me } = await asPlayer.rpc("get_my_player");
  const playerId = (me as { id?: string } | null)?.id;
  if (!playerId) return json({ error: "Please sign in." }, 401);

  if (!(await allowed(admin, `cancel-player-booking:${action}:${playerId}`, action === "cancel" ? 6 : 30))) {
    return json({ error: "Too many tries. Please wait a minute and try again." }, 429);
  }

  if (action === "quote") {
    const { data, error } = await asPlayer.rpc("get_my_booking_cancellation_quote", { p_booking_id: body.bookingId });
    if (error) {
      console.error("[cancel-player-booking] quote failed", error.code, error.message);
      return json({ error: "We could not work out the refund just now. Please try again." }, 400);
    }
    if (!data) return json({ error: "We could not find that booking." }, 404);
    return json({ quote: data });
  }

  const { data: result, error } = await asPlayer.rpc("player_cancel_booking", { p_booking_id: body.bookingId, p_reason: null });
  if (error || !result) {
    console.error("[cancel-player-booking] cancel rejected", error?.code, error?.message);
    // the database's own sentences ("This booking cannot be cancelled.") are meant to be read
    const readable = error?.code === "23514" || error?.code === "P0002";
    return json({ error: readable ? error!.message : "We could not cancel this booking. Please try again." }, 400);
  }

  const refundIds = ((result as { refundIds?: string[] }).refundIds ?? []).filter(Boolean);
  const outcomes: { refundId: string; status: string }[] = [];
  for (const id of refundIds) {
    if (!keyId || !keySecret) {
      outcomes.push({ refundId: id, status: "REQUESTED" });
      continue;
    }
    try {
      const r = await submitRequestedRefund(admin, id, keyId, keySecret);
      outcomes.push({ refundId: id, status: r.status });
    } catch (err) {
      // the refund row stays REQUESTED, so it can be sent again; the cancellation itself stands
      console.error("[cancel-player-booking] submitting a refund failed", { refundId: id, message: String(err) });
      outcomes.push({ refundId: id, status: "REQUESTED" });
    }
  }
  return json({ cancelled: true, quote: result, refunds: outcomes });
});
