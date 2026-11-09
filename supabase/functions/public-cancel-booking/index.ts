// ═══════════════════════════════════════════════════════════════════════════
// public-cancel-booking — a guest cancels the booking they made on the public /book/<venue> page.
//
//   { action: "quote",  bookingId, phone }   → what cancelling now would do (hours left, % deducted, refund, the sentence to show)
//   { action: "cancel", bookingId, phone }   → cancels it and sends the refund to Razorpay
//
// The guest is not signed in: the booking id plus the mobile number it was made with is what proves it is theirs (the database
// compares the last ten digits). It is rate limited per IP. The amounts are decided by the database (migration 0188); this function
// only submits the REQUESTED refund rows it creates.
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

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const keyId = Deno.env.get("RAZORPAY_KEY_ID");
  const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
  const ipSalt = Deno.env.get("PUBLIC_BOOKING_IP_SALT") ?? "";
  if (!url || !service) {
    console.error("[public-cancel-booking] missing function secrets");
    return json({ error: "This is temporarily unavailable. Please try again later." }, 500);
  }

  let body: { action?: string; bookingId?: string; phone?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }
  if (!body.bookingId || !body.phone) return json({ error: "Enter the booking and the mobile number it was made with." }, 400);
  const action = body.action === "cancel" ? "cancel" : "quote";

  const admin = createClient(url, service);
  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  const who = await sha256Hex(`${ipSalt}:${ip}`);
  if (!(await allowed(admin, `public-cancel-booking:${action}:${who}`, action === "cancel" ? 5 : 20))) {
    return json({ error: "Too many tries. Please wait a minute and try again." }, 429);
  }

  if (action === "quote") {
    const { data, error } = await admin.rpc("public_booking_cancellation_quote", { p_booking_id: body.bookingId, p_phone: body.phone });
    if (error) {
      console.error("[public-cancel-booking] quote failed", error.code, error.message);
      return json({ error: "We could not work out the refund just now. Please try again." }, 400);
    }
    if (!data) return json({ error: "We could not find a booking with that mobile number." }, 404);
    return json({ quote: data });
  }

  const { data: result, error } = await admin.rpc("public_cancel_booking", { p_booking_id: body.bookingId, p_phone: body.phone });
  if (error || !result) {
    console.error("[public-cancel-booking] cancel rejected", error?.code, error?.message);
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
      console.error("[public-cancel-booking] submitting a refund failed", { refundId: id, message: String(err) });
      outcomes.push({ refundId: id, status: "REQUESTED" });
    }
  }
  return json({ cancelled: true, quote: result, refunds: outcomes });
});
