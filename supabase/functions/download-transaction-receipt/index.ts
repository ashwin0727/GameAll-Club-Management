// ═══════════════════════════════════════════════════════════════════════════
// download-transaction-receipt — returns a PDF receipt for one finance
// transaction, as bytes the browser downloads.
//
// Built here rather than in the browser for two reasons: pdf-lib is already
// a dependency of send-booking-receipt, so this adds nothing new to the
// project; and generating it server-side keeps the web bundle free of a PDF
// library that only one page needs.
//
// Runs under the caller's own staff session — get_transaction_details does
// its own facility-role check, so a receipt cannot be pulled for a facility
// the caller has no access to.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { PDFDocument, StandardFonts, rgb } from "https://esm.sh/pdf-lib@1.17.1";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function money(minor: number | null, currency = "INR"): string {
  if (minor == null) return "-";
  return `${currency} ${(minor / 100).toLocaleString("en-IN", { minimumFractionDigits: 2 })}`;
}

function when(iso: string | null): string {
  if (!iso) return "-";
  return new Date(iso).toLocaleString("en-IN", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  });
}

interface HistoryRow {
  paidAt: string;
  amountMinor: number;
  paymentMethod: string | null;
  reference: string | null;
  status: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Not authenticated" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !supabaseAnonKey) return json({ error: "This action is not configured yet." }, 500);

  let body: { transactionId?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }
  if (!body.transactionId) return json({ error: "transactionId is required." }, 400);

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data, error } = await supabase.rpc("get_transaction_details", {
    p_transaction_id: body.transactionId,
  });
  if (error || !data) {
    return json({ error: "We couldn't find that transaction." }, 404);
  }

  const t = data as Record<string, unknown>;
  const currency = (t.currency as string) ?? "INR";
  const history = (t.history as HistoryRow[]) ?? [];

  const pdf = await PDFDocument.create();
  const page = pdf.addPage([595, 842]); // A4
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const body_ = await pdf.embedFont(StandardFonts.Helvetica);

  const ink = rgb(0.03, 0.06, 0.12);
  const muted = rgb(0.42, 0.46, 0.53);
  const accent = rgb(0, 0.72, 0.45);

  let y = 790;

  const text = (
    value: string,
    x: number,
    size: number,
    font = body_,
    color = ink,
  ) => page.drawText(value, { x, y, size, font, color });

  // Header
  text("GameAll", 48, 20, bold, accent);
  text("PAYMENT RECEIPT", 400, 12, bold, muted);
  y -= 18;
  text((t.facilityName as string) ?? "", 48, 11, body_, muted);
  y -= 26;
  page.drawLine({
    start: { x: 48, y },
    end: { x: 547, y },
    thickness: 1,
    color: rgb(0.88, 0.9, 0.93),
  });
  y -= 28;

  // The figure people look for first.
  text("Amount paid", 48, 10, body_, muted);
  y -= 22;
  text(money(t.amountMinor as number, currency), 48, 24, bold, accent);
  y -= 34;

  const row = (label: string, value: string) => {
    text(label, 48, 10, body_, muted);
    text(value, 200, 10, body_, ink);
    y -= 18;
  };

  row("Transaction ID", (t.reference as string) ?? "-");
  row("Date", when(t.occurredAt as string));
  row("Status", String(t.status ?? "").toUpperCase());
  row("Payment mode", (t.paymentMethod as string) ?? "-");
  row("Category", (t.category as string) ?? "-");
  row("Description", (t.description as string) ?? "-");
  if (t.sourceReference) row("Reference", t.sourceReference as string);
  if (t.customerName) row("Customer", t.customerName as string);
  if (t.customerPhone) row("Phone", t.customerPhone as string);
  if (t.recordedBy) row("Recorded by", t.recordedBy as string);

  // Payment history — a part-paid booking's receipt is misleading without
  // the other instalments beside it.
  if (history.length > 1) {
    y -= 12;
    text("Payment history", 48, 11, bold, ink);
    y -= 20;
    text("Date", 48, 9, body_, muted);
    text("Amount", 240, 9, body_, muted);
    text("Mode", 330, 9, body_, muted);
    text("Reference", 420, 9, body_, muted);
    y -= 16;

    for (const h of history) {
      if (y < 90) break; // Keep it to one page; the totals still balance.
      text(when(h.paidAt), 48, 9);
      text(money(h.amountMinor, currency), 240, 9);
      text(h.paymentMethod ?? "-", 330, 9);
      text(h.reference ?? "-", 420, 9);
      y -= 15;
    }

    const total = history.reduce((sum, h) => sum + h.amountMinor, 0);
    y -= 6;
    text("Total collected", 240, 10, bold);
    text(money(total, currency), 420, 10, bold);
    y -= 24;
  }

  if ((t.refundedMinor as number) > 0) {
    row("Refunded", money(t.refundedMinor as number, currency));
    row("Net", money(t.netMinor as number, currency));
  }

  y = 60;
  text("This is a computer-generated receipt and does not require a signature.", 48, 8, body_, muted);

  const bytes = await pdf.save();
  const filename = `receipt-${(t.reference as string) ?? "transaction"}.pdf`;

  return new Response(bytes, {
    status: 200,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/pdf",
      "Content-Disposition": `attachment; filename="${filename}"`,
    },
  });
});
