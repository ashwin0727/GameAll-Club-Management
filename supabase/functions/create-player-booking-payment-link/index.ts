// ═══════════════════════════════════════════════════════════════════════════
// create-player-booking-payment-link — "Complete the payment" for a booking, from the Player app's Home page.
//
// The player's own booking (a guest booking, or a court booking made for them) still has money owed. This makes (or hands back the
// still-open) ONE-TIME Razorpay Payment Link for it. Same link, same settlement as create-booking-payment-link (the staff version);
// the difference is who may call it:
//
//   * the caller is the signed-in PLAYER. Ownership is decided by player_booking_payment_context (migration 0177), which only
//     answers for a booking made for that player's phone number, under the player's own session;
//   * the payment order itself is then made with the service role, because create_payment_order runs under the caller's row-level
//     security and a player has no access to the club's payment tables.
//
// The amount is NEVER read from the request: create_payment_order takes it from the booking row (a guest booking longer than an hour
// is secured with the 50% advance, as everywhere else). Money only marks the booking paid through the razorpay-webhook
// (payment_link.paid → apply_payment_verification), the same gate checkout payments use.
//
// Setup (shared with the other payment functions):
//   supabase secrets set RAZORPAY_KEY_ID=... RAZORPAY_KEY_SECRET=...
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { toRazorpayContact } from "../_shared/coaching-billing.ts";
import { linkDescription, linkExpiryUnix, reusableLink } from "../_shared/booking-payment-link.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } });
}

interface BookingContext {
  bookingId: string;
  facilityId: string;
  customerType: "GUEST" | "MEMBER";
  status: string;
  paymentStatus: string | null;
  amountMinor: number;
  paidMinor: number;
  courtId: string | null;
  startTime: string;
  endTime: string;
  name: string | null;
  phone: string | null;
}

interface PaymentOrderRow {
  id: string;
  facility_id: string;
  booking_id: string | null;
  amount_minor: number;
  currency: string;
  status: string;
  razorpay_order_id: string | null;
  razorpay_payment_link_id: string | null;
  payment_link_url: string | null;
  payment_link_status: string | null;
  expires_at: string;
}

const PAID_STATES = ["CAPTURED", "COMPLETED", "SETTLEMENT_EXCEPTION"];

async function razorpay(path: string, keyId: string, keySecret: string, body: unknown) {
  const res = await fetch(`https://api.razorpay.com/v1${path}`, {
    method: "POST",
    headers: { Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`Razorpay ${path} failed (${res.status}): ${text.slice(0, 400)}`);
  return JSON.parse(text);
}

function linkPayload(row: PaymentOrderRow, extra: Record<string, unknown> = {}) {
  return {
    paymentOrderId: row.id,
    bookingId: row.booking_id,
    shortUrl: row.payment_link_url,
    amountMinor: row.amount_minor,
    status: row.payment_link_status ?? "CREATED",
    expiresAt: row.expires_at,
    paid: PAID_STATES.includes(row.status),
    ...extra,
  };
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
    console.error("[create-player-booking-payment-link] missing function secrets");
    return jsonResponse({ error: "Online payments are not configured yet." }, 500);
  }

  let body: { bookingId?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body." }, 400);
  }
  if (!body.bookingId) return jsonResponse({ error: "bookingId is required." }, 400);

  // 1 · who is asking, and is the booking theirs? (their own session)
  const asPlayer = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });
  const { data: ctxData, error: ctxErr } = await asPlayer.rpc("player_booking_payment_context", { p_booking_id: body.bookingId });
  if (ctxErr || !ctxData) {
    if (ctxErr?.code === "P0002") return jsonResponse({ error: "Booking not found." }, 404);
    if (ctxErr?.code === "42501") return jsonResponse({ error: "Please sign in first." }, 401);
    console.error("[create-player-booking-payment-link] context failed", ctxErr?.message);
    return jsonResponse({ error: "Lookup failed." }, 500);
  }
  const ctx = ctxData as BookingContext;

  if (ctx.paymentStatus === "PAID" || (ctx.amountMinor > 0 && ctx.paidMinor >= ctx.amountMinor)) {
    return jsonResponse({ bookingId: ctx.bookingId, status: "PAID", paid: true }, 200);
  }
  if (!["pending", "confirmed"].includes(ctx.status)) return jsonResponse({ error: "This booking is no longer active." }, 400);
  if (ctx.amountMinor <= 0) return jsonResponse({ error: "There is nothing to pay for this booking." }, 400);

  // 2 · from here on the club's payment tables are used, with the service role
  const admin = createClient(supabaseUrl, serviceKey);

  // an advance (or the full amount) that was already received is never asked for twice
  const { data: settled } = await admin
    .from("payment_orders")
    .select("*")
    .eq("facility_id", ctx.facilityId)
    .eq("booking_id", ctx.bookingId)
    .in("status", PAID_STATES)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (settled) return jsonResponse(linkPayload(settled as PaymentOrderRow, { status: "PAID" }), 200);

  const isGuest = ctx.customerType === "GUEST";
  const { data: orderData, error: orderErr } = await admin.rpc("create_payment_order", {
    p_facility_id: ctx.facilityId,
    p_source_type: isGuest ? "GUEST_BOOKING" : "MEMBER_BOOKING",
    p_booking_id: ctx.bookingId,
    p_membership_session_booking_id: null,
    p_member_id: null,
    p_plan_id: null,
    // a guest booking longer than an hour is secured with a 50% advance (migration 0130); the rest pay in full
    p_advance: isGuest,
  });
  if (orderErr || !orderData) {
    console.error("[create-player-booking-payment-link] create_payment_order failed", orderErr?.code, orderErr?.message);
    const friendly = orderErr?.code === "23514" || orderErr?.code === "23503" ? orderErr.message : "Unable to start this payment.";
    return jsonResponse({ error: friendly }, 400);
  }
  const order = orderData as PaymentOrderRow;
  if (PAID_STATES.includes(order.status)) return jsonResponse(linkPayload(order, { status: "PAID" }), 200);

  // an earlier link that is still open → the same link again, never a second one
  const { data: latest } = await admin.from("payment_orders").select("*").eq("id", order.id).single();
  const current = (latest as PaymentOrderRow | null) ?? order;
  if (
    reusableLink(
      {
        razorpayPaymentLinkId: current.razorpay_payment_link_id,
        paymentLinkUrl: current.payment_link_url,
        paymentLinkStatus: current.payment_link_status,
        expiresAt: current.expires_at,
      },
      Date.now(),
    )
  ) {
    return jsonResponse(linkPayload(current, { reused: true }), 200);
  }

  const [{ data: court }, { data: facility }] = await Promise.all([
    ctx.courtId ? admin.from("courts").select("name").eq("id", ctx.courtId).maybeSingle() : Promise.resolve({ data: null }),
    admin.from("facilities").select("timezone").eq("id", ctx.facilityId).maybeSingle(),
  ]);

  const contact = toRazorpayContact(ctx.phone);
  const expireBy = linkExpiryUnix(Date.now());

  try {
    const link = await razorpay("/payment_links", keyId, keySecret, {
      amount: order.amount_minor,
      currency: order.currency,
      accept_partial: false,
      reference_id: order.id,
      description:
        (order.amount_minor < ctx.amountMinor ? "Advance (50%) · " : "") +
        linkDescription((court as { name?: string } | null)?.name ?? null, ctx.startTime, ctx.endTime, (facility as { timezone?: string } | null)?.timezone ?? "Asia/Kolkata"),
      expire_by: expireBy,
      customer: {
        ...(ctx.name ? { name: ctx.name } : {}),
        ...(contact ? { contact } : {}),
      },
      notify: { sms: Boolean(contact), email: false },
      reminder_enable: true,
      notes: {
        gameall_payment_order_id: order.id,
        facility_id: order.facility_id,
        booking_id: ctx.bookingId,
        source_type: isGuest ? "GUEST_BOOKING" : "MEMBER_BOOKING",
      },
    });

    const { data: saved, error: saveErr } = await admin
      .from("payment_orders")
      .update({
        razorpay_payment_link_id: link.id,
        payment_link_url: link.short_url ?? null,
        payment_link_status: "CREATED",
        status: "ORDER_CREATED",
        expires_at: new Date(expireBy * 1000).toISOString(),
      })
      .eq("id", order.id)
      .select("*")
      .single();
    if (saveErr || !saved) {
      console.error("[create-player-booking-payment-link] could not save the link", saveErr?.message);
      // don't leave an orphan link the player could pay without us knowing about it
      await razorpay(`/payment_links/${link.id}/cancel`, keyId, keySecret, {}).catch(() => undefined);
      return jsonResponse({ error: "Could not save the payment link." }, 500);
    }
    return jsonResponse(linkPayload(saved as PaymentOrderRow), 200);
  } catch (err) {
    console.error("[create-player-booking-payment-link] razorpay error", String(err));
    return jsonResponse({ error: "Could not create the payment link with Razorpay." }, 502);
  }
});
