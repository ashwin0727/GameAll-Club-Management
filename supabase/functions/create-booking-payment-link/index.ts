// ═══════════════════════════════════════════════════════════════════════════
// create-booking-payment-link — "Pay Online" for a guest booking made by staff.
//
// The player is not at the counter, so nothing opens on the staff member's screen. Instead this makes a
// ONE-TIME Razorpay Payment Link for the booking, which staff share with the player (WhatsApp / SMS / copy).
//
//   action "create" (default)  → create (or hand back the still-open) link for the booking
//   action "status"            → ask Razorpay whether it was paid, and settle it if so (the webhook is the
//                                normal path; this is the "Check status" backstop)
//   action "cancel"            → close an unpaid link
//
// Security:
//   * Runs under the CALLER's staff session, so every read/write is subject to the same RLS as in the app.
//   * The amount is NEVER read from the request: create_payment_order takes it from the booking row, which
//     was priced server-side at booking time.
//   * Money only moves the booking to Paid through apply_payment_verification (amount / currency /
//     duplicate-payment checks + settlement), the same gate checkout payments use.
//   * Idempotent: an open link for the booking is returned as-is; a paid one is never re-created.
//
// Setup (shared with the other payment functions):
//   supabase secrets set RAZORPAY_KEY_ID=... RAZORPAY_KEY_SECRET=...
// Razorpay Dashboard → Payment Links must be enabled, and razorpay-webhook must receive payment_link.paid.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { toRazorpayContact } from "../_shared/coaching-billing.ts";
import { linkDescription, linkExpiryUnix, linkStatusFromRazorpay, reusableLink } from "../_shared/booking-payment-link.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } });
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

async function razorpay(method: "GET" | "POST", path: string, keyId: string, keySecret: string, body?: unknown) {
  const res = await fetch(`https://api.razorpay.com/v1${path}`, {
    method,
    headers: { Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`Razorpay ${path} failed (${res.status}): ${text.slice(0, 400)}`);
  return JSON.parse(text);
}

const PAID_STATES = ["CAPTURED", "COMPLETED", "SETTLEMENT_EXCEPTION"];

function linkPayload(row: PaymentOrderRow, extra: Record<string, unknown> = {}) {
  return {
    paymentOrderId: row.id,
    bookingId: row.booking_id,
    shortUrl: row.payment_link_url,
    amountMinor: row.amount_minor,
    currency: row.currency,
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
  const keyId = Deno.env.get("RAZORPAY_KEY_ID");
  const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
  if (!supabaseUrl || !anonKey || !keyId || !keySecret) {
    console.error("[create-booking-payment-link] missing function secrets");
    return jsonResponse({ error: "Online payments are not configured yet." }, 500);
  }

  let body: { bookingId?: string; facilityId?: string; action?: "create" | "status" | "cancel" };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body." }, 400);
  }
  if (!body.bookingId || !body.facilityId) return jsonResponse({ error: "bookingId and facilityId are required." }, 400);
  const action = body.action ?? "create";

  const supabase = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });

  // ── status / cancel work on the order that already exists for this booking ──────────────────────────
  if (action === "status" || action === "cancel") {
    const { data: row, error } = await supabase
      .from("payment_orders")
      .select("*")
      .eq("facility_id", body.facilityId)
      .eq("booking_id", body.bookingId)
      .not("razorpay_payment_link_id", "is", null)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (error) {
      console.error("[create-booking-payment-link] lookup failed", error.message);
      return jsonResponse({ error: "Lookup failed." }, 500);
    }
    if (!row) return jsonResponse({ error: "There is no payment link for this booking." }, 404);
    const order = row as PaymentOrderRow;

    try {
      if (action === "cancel") {
        if (PAID_STATES.includes(order.status)) return jsonResponse({ error: "This booking is already paid." }, 400);
        if (order.payment_link_status === "CREATED") {
          await razorpay("POST", `/payment_links/${order.razorpay_payment_link_id}/cancel`, keyId, keySecret);
        }
        await supabase.from("payment_orders").update({ payment_link_status: "CANCELLED" }).eq("id", order.id);
        return jsonResponse(linkPayload({ ...order, payment_link_status: "CANCELLED" }), 200);
      }

      // status — already settled here? nothing to ask Razorpay.
      if (PAID_STATES.includes(order.status)) return jsonResponse(linkPayload(order, { status: "PAID" }), 200);

      const link = await razorpay("GET", `/payment_links/${order.razorpay_payment_link_id}`, keyId, keySecret);
      const linkStatus = linkStatusFromRazorpay(link.status);

      if (linkStatus === "PAID") {
        const paymentId: string | undefined = link.payments?.[0]?.payment_id;
        if (!paymentId) return jsonResponse(linkPayload(order, { status: "CREATED" }), 200);
        // The payment itself is the authority for order id / amount / currency, not the link or the caller.
        const payment = await razorpay("GET", `/payments/${paymentId}`, keyId, keySecret);
        if (payment.status !== "captured") return jsonResponse(linkPayload(order, { status: "CREATED" }), 200);

        if (order.razorpay_order_id !== payment.order_id) {
          const { error: adoptErr } = await supabase.from("payment_orders").update({ razorpay_order_id: payment.order_id }).eq("id", order.id);
          if (adoptErr) throw new Error(`could not attach the link's order: ${adoptErr.message}`);
        }
        const { data: applied, error: applyErr } = await supabase.rpc("apply_payment_verification", {
          p_payment_order_id: order.id,
          p_razorpay_order_id: payment.order_id,
          p_razorpay_payment_id: payment.id,
          p_razorpay_status: "CAPTURED",
          p_amount_minor: payment.amount,
          p_currency: payment.currency,
        });
        if (applyErr) {
          console.error("[create-booking-payment-link] apply_payment_verification rejected", applyErr.code, applyErr.message);
          return jsonResponse({ error: "The payment did not match this booking. It needs a manual check." }, 409);
        }
        await supabase.from("payment_orders").update({ payment_link_status: "PAID" }).eq("id", order.id);
        return jsonResponse(linkPayload((applied as PaymentOrderRow) ?? order, { status: "PAID", paid: true }), 200);
      }

      if (linkStatus && linkStatus !== order.payment_link_status) {
        await supabase.from("payment_orders").update({ payment_link_status: linkStatus }).eq("id", order.id);
      }
      return jsonResponse(linkPayload(order, { status: linkStatus ?? order.payment_link_status ?? "CREATED" }), 200);
    } catch (err) {
      console.error("[create-booking-payment-link] razorpay error", String(err));
      return jsonResponse({ error: "Could not reach Razorpay. Please try again." }, 502);
    }
  }

  // ── create ───────────────────────────────────────────────────────────────────────────────────────────
  // Everything the link shows comes from the booking row, read under the caller's own access.
  const { data: booking, error: bookingErr } = await supabase
    .from("bookings")
    .select("guest_name, guest_phone, start_time, end_time, court_id, payment_status")
    .eq("id", body.bookingId)
    .eq("facility_id", body.facilityId)
    .maybeSingle();
  if (bookingErr || !booking) return jsonResponse({ error: "Booking not found." }, 404);
  // Paid already (a settled order is never reused by create_payment_order, so guard here).
  if (booking.payment_status === "PAID") {
    return jsonResponse({ bookingId: body.bookingId, status: "PAID", paid: true }, 200);
  }

  const { data: orderData, error: orderErr } = await supabase.rpc("create_payment_order", {
    p_facility_id: body.facilityId,
    p_source_type: "GUEST_BOOKING",
    p_booking_id: body.bookingId,
    p_membership_session_booking_id: null,
    p_member_id: null,
    p_plan_id: null,
  });
  if (orderErr || !orderData) {
    console.error("[create-booking-payment-link] create_payment_order failed", orderErr?.code, orderErr?.message);
    const friendly = orderErr?.code === "23514" || orderErr?.code === "23503" ? orderErr.message : "Unable to start this payment.";
    return jsonResponse({ error: friendly }, 400);
  }
  const order = orderData as PaymentOrderRow;

  if (PAID_STATES.includes(order.status)) return jsonResponse(linkPayload(order, { status: "PAID" }), 200);

  // An earlier link for this booking that is still open → the same link again, never a second one.
  const { data: latest } = await supabase.from("payment_orders").select("*").eq("id", order.id).single();
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
    supabase.from("courts").select("name").eq("id", booking.court_id).maybeSingle(),
    supabase.from("facilities").select("timezone").eq("id", body.facilityId).maybeSingle(),
  ]);

  const contact = toRazorpayContact(booking.guest_phone);
  const expireBy = linkExpiryUnix(Date.now());

  try {
    const link = await razorpay("POST", "/payment_links", keyId, keySecret, {
      amount: order.amount_minor,
      currency: order.currency,
      accept_partial: false,
      reference_id: order.id,
      description: linkDescription(court?.name ?? null, booking.start_time, booking.end_time, facility?.timezone ?? "Asia/Kolkata"),
      expire_by: expireBy,
      customer: {
        ...(booking.guest_name ? { name: booking.guest_name } : {}),
        ...(contact ? { contact } : {}),
      },
      // Razorpay texts the player the link too, when we have a valid mobile number.
      notify: { sms: Boolean(contact), email: false },
      reminder_enable: true,
      notes: {
        gameall_payment_order_id: order.id,
        facility_id: order.facility_id,
        booking_id: body.bookingId,
        source_type: "GUEST_BOOKING",
      },
    });

    const expiresAt = new Date(expireBy * 1000).toISOString();
    const { data: saved, error: saveErr } = await supabase
      .from("payment_orders")
      .update({
        razorpay_payment_link_id: link.id,
        payment_link_url: link.short_url ?? null,
        payment_link_status: "CREATED",
        status: "ORDER_CREATED",
        expires_at: expiresAt,
      })
      .eq("id", order.id)
      .select("*")
      .single();
    if (saveErr || !saved) {
      console.error("[create-booking-payment-link] could not save the link", saveErr?.message);
      // Don't leave an orphan link the player could pay without us knowing about it.
      await razorpay("POST", `/payment_links/${link.id}/cancel`, keyId, keySecret).catch(() => undefined);
      return jsonResponse({ error: "Could not save the payment link." }, 500);
    }
    return jsonResponse(linkPayload(saved as PaymentOrderRow), 200);
  } catch (err) {
    console.error("[create-booking-payment-link] razorpay error", String(err));
    return jsonResponse({ error: "Could not create the payment link with Razorpay." }, 502);
  }
});
