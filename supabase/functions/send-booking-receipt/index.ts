// ═══════════════════════════════════════════════════════════════════════════
// send-booking-receipt — emails a PDF receipt for a GUEST booking.
//
// Runs under the caller's own staff session (RLS-scoped read of the
// booking). Builds a one-page PDF with pdf-lib and sends it via Resend.
//
// Required function secrets: RESEND_API_KEY, RESEND_FROM (e.g.
// "GameAll <receipts@yourdomain.com>"). SUPABASE_URL / SUPABASE_ANON_KEY
// are always present.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { PDFDocument, StandardFonts, rgb } from "https://esm.sh/pdf-lib@1.17.1";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } });
}

function inr(minor: number | null): string {
  return minor == null ? "-" : `INR ${(minor / 100).toLocaleString("en-IN", { minimumFractionDigits: 2 })}`;
}
function fmt(iso: string): string {
  return new Date(iso).toLocaleString("en-IN", { day: "2-digit", month: "short", year: "numeric", hour: "numeric", minute: "2-digit", hour12: true });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Not authenticated" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const resendKey = Deno.env.get("RESEND_API_KEY");
  const resendFrom = Deno.env.get("RESEND_FROM");
  if (!supabaseUrl || !supabaseAnonKey) return json({ error: "This action is not configured yet." }, 500);
  if (!resendKey || !resendFrom) return json({ error: "Email is not configured. Set RESEND_API_KEY and RESEND_FROM." }, 500);

  let body: { bookingId?: string; email?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }
  const email = (body.email ?? "").trim();
  if (!body.bookingId || !email) return json({ error: "bookingId and email are required." }, 400);

  const supabase = createClient(supabaseUrl, supabaseAnonKey, { global: { headers: { Authorization: authHeader } } });

  const { data: b, error } = await supabase
    .from("bookings")
    .select("id, guest_name, guest_phone, start_time, end_time, amount_minor, currency, payment_status, payment_method, party_size, facility_id, court_id")
    .eq("id", body.bookingId)
    .maybeSingle();
  if (error || !b) return json({ error: "Booking not found." }, 404);

  const [{ data: facility }, { data: court }] = await Promise.all([
    supabase.from("facilities").select("name, address, city").eq("id", b.facility_id).maybeSingle(),
    supabase.from("courts").select("name, facility_sport_id").eq("id", b.court_id).maybeSingle(),
  ]);
  let sportName = "";
  if (court?.facility_sport_id) {
    const { data: fs } = await supabase
      .from("facility_sports")
      .select("custom_sport_name, sports(name)")
      .eq("id", court.facility_sport_id)
      .maybeSingle();
    sportName = fs?.custom_sport_name ?? (fs?.sports as { name?: string } | null)?.name ?? "";
  }

  const code = "GBK" + String(b.id).replace(/-/g, "").slice(0, 4).toUpperCase();

  // ── PDF ────────────────────────────────────────────────────────────────
  const pdf = await PDFDocument.create();
  const page = pdf.addPage([420, 560]);
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const green = rgb(0, 0.51, 0.32);
  let y = 520;
  const line = (text: string, opts: { size?: number; f?: typeof font; color?: typeof green } = {}) => {
    page.drawText(text, { x: 40, y, size: opts.size ?? 10, font: opts.f ?? font, color: opts.color ?? rgb(0.15, 0.15, 0.15) });
    y -= (opts.size ?? 10) + 8;
  };
  const kv = (k: string, v: string) => {
    page.drawText(k, { x: 40, y, size: 10, font, color: rgb(0.45, 0.45, 0.45) });
    page.drawText(v, { x: 190, y, size: 10, font: bold, color: rgb(0.15, 0.15, 0.15) });
    y -= 20;
  };
  line("GameAll", { size: 20, f: bold, color: green });
  line(facility?.name ?? "", { size: 11, f: bold });
  if (facility?.address || facility?.city) line([facility?.address, facility?.city].filter(Boolean).join(", "), { size: 9, color: rgb(0.45, 0.45, 0.45) });
  y -= 6;
  line("Booking Receipt", { size: 13, f: bold });
  y -= 4;
  kv("Booking ID", code);
  kv("Guest", `${b.guest_name ?? "Guest"}${b.guest_phone ? " / " + b.guest_phone : ""}`);
  kv("Sport / Court", `${sportName || "-"} / ${court?.name ?? "-"}`);
  kv("Date & Time", `${fmt(b.start_time)} - ${new Date(b.end_time).toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit", hour12: true })}`);
  kv("Players", String(b.party_size ?? 1));
  kv("Amount", inr(b.amount_minor));
  kv("Payment", `${b.payment_status}${b.payment_method ? " / " + b.payment_method : ""}`);
  y -= 10;
  line("Thank you for booking with us.", { size: 9, color: rgb(0.45, 0.45, 0.45) });
  line(`Generated ${new Date().toLocaleString("en-IN")}`, { size: 8, color: rgb(0.6, 0.6, 0.6) });
  const pdfBytes = await pdf.save();
  const pdfBase64 = btoa(String.fromCharCode(...pdfBytes));

  // ── Send ───────────────────────────────────────────────────────────────
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from: resendFrom,
      to: [email],
      subject: `Your booking receipt · ${code}`,
      html: `<p>Hi ${b.guest_name ?? "there"},</p><p>Your receipt for booking <strong>${code}</strong> at ${facility?.name ?? "our venue"} is attached.</p><p>${sportName || "Court"} · ${court?.name ?? ""}<br/>${fmt(b.start_time)}<br/>${inr(b.amount_minor)} · ${b.payment_status}</p><p>— GameAll</p>`,
      attachments: [{ filename: `receipt-${code}.pdf`, content: pdfBase64 }],
    }),
  });
  if (!res.ok) {
    const detail = await res.text();
    console.error("[send-booking-receipt] resend failed", res.status, detail);
    return json({ error: "Could not send the email. Check the email address and try again." }, 502);
  }
  return json({ sent: true }, 200);
});
