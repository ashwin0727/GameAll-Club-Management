// ═══════════════════════════════════════════════════════════════════════════
// public-booking-checkout — paying the 50% advance for a booking made on the public /book/<facility> page, and
// the invoice for it.
//
// A booking longer than one hour is held (PENDING, 30 minutes) until its advance is paid (migration 0131). The
// player is anonymous and nothing is shared with them: the booking page opens Razorpay Checkout itself.
//
//   action "create"   → ONE Razorpay order for the advances of every booking being paid (one payment, however many
//                       courts and times), and what Checkout needs to open
//   action "verify"   → the player's Checkout result, re-checked here (signature, then Razorpay's own record of the
//                       payment) before the booking is settled — the browser is never the authority on "paid"
//   action "invoice"  → a PDF invoice for a booking, as bytes the browser downloads
//
// Security:
//   * runs with the service role (there is no signed-in user), so it does its own checks instead of RLS: every
//     action needs the booking id AND the phone number it was made with, and answers "not found" for either being
//     wrong, so ids can't be probed;
//   * the amount is NEVER read from the request: create_public_payment_order works it out from the bookings
//     (guest_booking_advance_minor, 50% each, migration 0132);
//   * money only moves a booking to confirmed through apply_payment_verification — the gate every payment uses.
//
// Secrets: RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET (shared with the other payment functions).
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { PDFDocument, StandardFonts, rgb } from "https://esm.sh/pdf-lib@1.17.1";
import { captureRazorpayPayment, fetchRazorpayPayment, mapRazorpayPaymentStatus, verifyPaymentSignature } from "../_shared/razorpay.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } });
}

const last10 = (phone: string | null | undefined) => (phone ?? "").replace(/\D/g, "").slice(-10);
const HOUR_MS = 3_600_000;
/** Time given to finish paying once Checkout is about to open. */
const PAY_WINDOW_MS = 15 * 60_000;

interface OrderRow {
  id: string;
  facility_id: string;
  amount_minor: number;
  currency: string;
  status: string;
  receipt: string;
  razorpay_order_id: string | null;
}

// Mirrors money() in download-transaction-receipt: plain "INR 1,200" — pdf-lib's standard fonts can't draw "₹".
function money(minor: number | null | undefined, currency = "INR"): string {
  if (minor == null) return "-";
  const major = minor / 100;
  const formatted = major.toLocaleString("en-IN", { minimumFractionDigits: Number.isInteger(major) ? 0 : 2, maximumFractionDigits: 2 });
  return `${currency} ${formatted}`;
}

function when(iso: string | null | undefined): string {
  if (!iso) return "-";
  return new Date(iso).toLocaleString("en-IN", {
    day: "2-digit", month: "short", year: "numeric", hour: "numeric", minute: "2-digit", hour12: true, timeZone: "Asia/Kolkata",
  });
}

async function invoicePdf(r: Record<string, unknown>): Promise<Uint8Array> {
  const currency = (r.currency as string) ?? "INR";
  const pdf = await PDFDocument.create();
  const page = pdf.addPage([595, 842]);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const ink = rgb(0.03, 0.06, 0.12);
  const muted = rgb(0.42, 0.46, 0.53);
  const accent = rgb(0, 0.72, 0.45);
  let y = 790;
  const text = (value: string, x: number, size: number, f = font, color = ink) => page.drawText(value, { x, y, size, font: f, color });
  const rule = () => page.drawLine({ start: { x: 48, y }, end: { x: 547, y }, thickness: 1, color: rgb(0.88, 0.9, 0.93) });
  const row = (label: string, value: string, strong = false) => {
    text(label, 48, 10, font, muted);
    text(value, 220, 10, strong ? bold : font, ink);
    y -= 18;
  };

  text((r.facilityName as string) ?? "", 48, 20, bold, accent);
  text("INVOICE", 440, 14, bold, muted);
  y -= 20;
  text("Court booking", 48, 10, font, muted);
  text(`No. ${r.code as string}`, 440, 10, font, muted);
  y -= 22;
  rule();
  y -= 26;

  text("Billed to", 48, 9, font, muted);
  y -= 15;
  text((r.guestName as string) ?? "-", 48, 12, bold);
  y -= 15;
  text((r.guestPhone as string) ?? "", 48, 10, font, muted);
  y -= 30;

  text("Booking", 48, 11, bold);
  y -= 20;
  row("Booking ID", r.code as string);
  row("Sport", (r.sportName as string) ?? "-");
  row("Court / Turf", (r.courtName as string) ?? "-");
  row("Date", new Date(r.startTime as string).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric", weekday: "short", timeZone: "Asia/Kolkata" }));
  row("Time", `${new Date(r.startTime as string).toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit", hour12: true, timeZone: "Asia/Kolkata" })} - ${new Date(r.endTime as string).toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit", hour12: true, timeZone: "Asia/Kolkata" })}`);
  row("Players", String(r.partySize ?? 1));
  y -= 10;

  text("Payment", 48, 11, bold);
  y -= 20;
  const status = r.paymentStatus === "PAID" ? "FULLY PAID" : r.paymentStatus === "PARTIALLY_PAID" ? "PARTIALLY PAID" : "PAYMENT PENDING";
  row("Status", status, true);
  row("Total amount", money(r.amountMinor as number, currency), true);
  row("Paid amount", money(r.paidMinor as number, currency));
  if ((r.outstandingMinor as number) > 0) row("Pending amount (pay at venue)", money(r.outstandingMinor as number, currency), true);
  if (r.paymentMethod) row("Payment mode", String(r.paymentMethod));
  if (r.paymentReference) row("Payment reference", String(r.paymentReference));
  if (r.paidAt) row("Paid on", when(r.paidAt as string));

  y = 60;
  text("This is a computer-generated invoice and does not require a signature.", 48, 8, font, muted);
  return await pdf.save();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const keyId = Deno.env.get("RAZORPAY_KEY_ID");
  const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
  if (!supabaseUrl || !serviceKey || !keyId || !keySecret) {
    console.error("[public-booking-checkout] missing function secrets");
    return json({ error: "Online payments are not available right now." }, 500);
  }

  let body: {
    action?: "create" | "verify" | "invoice";
    /** One booking (invoice) ... */
    bookingId?: string;
    /** ... or every booking one payment covers (create / verify). */
    bookingIds?: string[];
    phone?: string;
    paymentOrderId?: string;
    razorpayOrderId?: string;
    razorpayPaymentId?: string;
    razorpaySignature?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request." }, 400);
  }
  const ids = [...new Set(body.bookingIds?.length ? body.bookingIds : body.bookingId ? [body.bookingId] : [])];
  if (ids.length === 0 || ids.length > 12 || !body.phone) return json({ error: "Missing booking details." }, 400);
  const action = body.action ?? "create";

  const supabase = createClient(supabaseUrl, serviceKey);
  await supabase.rpc("release_expired_booking_holds");

  // The same answer for "no such booking" and "not yours", so ids can't be probed.
  const notFound = () => json({ error: "We could not find that booking." }, 404);
  const receipts: Record<string, unknown>[] = [];
  for (const id of ids) {
    const { data: receipt } = await supabase.rpc("public_booking_receipt", { p_booking_id: id, p_phone: body.phone });
    const one = receipt as Record<string, unknown> | null;
    if (!one || one.found !== true) return notFound();
    receipts.push(one);
  }
  const r = receipts[0]!;

  // ── invoice ──────────────────────────────────────────────────────────────────────────────────────────
  if (action === "invoice") {
    if (r.cancelled === true) return json({ error: "That booking was cancelled." }, 410);
    const bytes = await invoicePdf(r);
    return new Response(bytes as unknown as BodyInit, {
      status: 200,
      headers: { ...CORS_HEADERS, "Content-Type": "application/pdf", "Content-Disposition": `attachment; filename="invoice-${r.code as string}.pdf"` },
    });
  }

  const { data: bookingRows } = await supabase
    .from("bookings")
    .select("id, facility_id, status, start_time, end_time, hold_expires_at")
    .in("id", ids);
  const bookings = bookingRows ?? [];
  if (bookings.length !== ids.length) return notFound();

  // ── create ───────────────────────────────────────────────────────────────────────────────────────────
  if (action === "create") {
    if (receipts.every((x) => x.confirmed === true)) return json({ paid: true, bookingIds: ids }, 200);
    if (receipts.some((x) => x.cancelled === true)) return json({ error: "That booking has expired. Please book again.", code: "HOLD_EXPIRED" }, 410);
    for (const booking of bookings) {
      if (booking.status !== "pending" || booking.hold_expires_at == null) {
        return json({ error: "This booking does not need an online advance." }, 400);
      }
      if (new Date(booking.end_time).getTime() - new Date(booking.start_time).getTime() <= HOUR_MS) {
        return json({ error: "This booking does not need an online advance." }, 400);
      }
    }

    // Keep every court held while the player pays, so none can be released from under an open Checkout.
    const holdUntil = new Date(Date.now() + PAY_WINDOW_MS).toISOString();
    for (const booking of bookings) {
      if (new Date(booking.hold_expires_at as string).getTime() < Date.now() + PAY_WINDOW_MS) {
        await supabase.from("bookings").update({ hold_expires_at: holdUntil }).eq("id", booking.id).eq("status", "pending");
      }
    }

    const { data: orderData, error: orderErr } = await supabase.rpc("create_public_payment_order", { p_booking_ids: ids });
    if (orderErr || !orderData) {
      console.error("[public-booking-checkout] create_public_payment_order failed", orderErr?.code, orderErr?.message);
      return json({ error: "Unable to start this payment." }, 400);
    }
    const order = orderData as OrderRow;
    const checkout = (o: { id: string; razorpay_order_id: string | null; amount_minor: number; currency: string; receipt: string }) => ({
      keyId,
      razorpayOrderId: o.razorpay_order_id,
      amount: o.amount_minor,
      currency: o.currency,
      paymentOrderId: o.id,
      receipt: o.receipt,
      bookingIds: ids,
    });
    // A still-valid order for these bookings already has its Razorpay order: hand it back, never a second one.
    if (order.razorpay_order_id) return json(checkout(order), 200);

    try {
      const res = await fetch("https://api.razorpay.com/v1/orders", {
        method: "POST",
        headers: { Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          amount: order.amount_minor,
          currency: order.currency,
          receipt: order.receipt,
          payment_capture: 1,
          notes: { gameall_payment_order_id: order.id, facility_id: order.facility_id, source_type: "GUEST_BOOKING", booking_ids: ids.join(",").slice(0, 250) },
        }),
      });
      if (!res.ok) {
        console.error("[public-booking-checkout] Razorpay rejected the order", res.status, (await res.text()).slice(0, 400));
        await supabase.from("payment_orders").update({ status: "FAILED" }).eq("id", order.id);
        return json({ error: "Unable to start the payment right now. Please try again." }, 502);
      }
      const rzp = (await res.json()) as { id: string };
      const { data: saved, error: saveErr } = await supabase
        .from("payment_orders")
        .update({ razorpay_order_id: rzp.id, status: "ORDER_CREATED" })
        .eq("id", order.id)
        .select("id, amount_minor, currency, razorpay_order_id, receipt")
        .single();
      if (saveErr || !saved) {
        console.error("[public-booking-checkout] could not save the order", saveErr?.message);
        return json({ error: "Could not start the payment. Please try again." }, 500);
      }
      return json(checkout(saved), 200);
    } catch (err) {
      console.error("[public-booking-checkout] network error calling Razorpay", String(err));
      return json({ error: "Could not reach the payment provider. Please try again." }, 502);
    }
  }

  // ── verify ───────────────────────────────────────────────────────────────────────────────────────────
  if (action === "verify") {
    const failed = () => json({ error: "We couldn't verify that payment. If money was taken it will be reconciled — please contact the venue." }, 400);
    if (!body.paymentOrderId || !body.razorpayOrderId || !body.razorpayPaymentId || !body.razorpaySignature) return failed();

    // The order must be this booking's own.
    const { data: order } = await supabase
      .from("payment_orders")
      .select("id, razorpay_order_id, status")
      .eq("id", body.paymentOrderId)
      .maybeSingle();
    if (!order || order.razorpay_order_id !== body.razorpayOrderId) return failed();
    // The order must cover exactly the bookings being claimed.
    const { data: covered } = await supabase.from("payment_order_bookings").select("booking_id").eq("payment_order_id", order.id);
    const coveredIds = new Set((covered ?? []).map((c: { booking_id: string }) => c.booking_id));
    if (coveredIds.size !== ids.length || !ids.every((id) => coveredIds.has(id))) return failed();

    if (!(await verifyPaymentSignature(body.razorpayOrderId, body.razorpayPaymentId, body.razorpaySignature, keySecret))) {
      console.error("[public-booking-checkout] signature verification failed", order.id);
      return failed();
    }

    let payment;
    try {
      payment = await fetchRazorpayPayment(body.razorpayPaymentId, keyId, keySecret);
      if (payment.order_id !== body.razorpayOrderId || payment.id !== body.razorpayPaymentId) return failed();
      if (payment.status === "authorized") {
        payment = await captureRazorpayPayment(payment.id, payment.amount, payment.currency, keyId, keySecret);
      }
    } catch (err) {
      console.error("[public-booking-checkout] could not read the payment from Razorpay", String(err));
      return json({ error: "Unable to reach the payment provider. Please try again shortly." }, 502);
    }

    const { error: applyErr } = await supabase.rpc("apply_payment_verification", {
      p_payment_order_id: order.id,
      p_razorpay_order_id: payment.order_id,
      p_razorpay_payment_id: payment.id,
      p_razorpay_status: mapRazorpayPaymentStatus(payment.status),
      p_amount_minor: payment.amount,
      p_currency: payment.currency,
      p_razorpay_signature: body.razorpaySignature,
    });
    if (applyErr) {
      console.error("[public-booking-checkout] apply_payment_verification rejected", applyErr.code, applyErr.message);
      return failed();
    }

    let allConfirmed = true;
    for (const id of ids) {
      const { data: after } = await supabase.rpc("public_booking_receipt", { p_booking_id: id, p_phone: body.phone });
      if ((after as { confirmed?: boolean } | null)?.confirmed !== true) allConfirmed = false;
    }
    return json({ confirmed: allConfirmed }, 200);
  }

  return json({ error: "Unknown action." }, 400);
});
