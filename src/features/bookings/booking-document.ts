import { APP_NAME } from "@/lib/constants";
import { formatCurrency } from "@/features/pricing/money";
import type { GuestBookingRow } from "@/features/bookings/types";

function esc(s: string): string {
  return s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c] ?? c);
}
function fmtDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}
function fmtTime(iso: string): string {
  return new Date(iso).toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit", hour12: true });
}

/** A self-contained printable HTML page for a guest booking. `kind` only
 *  changes the heading — the content is identical. */
export function buildBookingDocument(kind: "invoice" | "receipt", row: GuestBookingRow, facilityName: string): string {
  const rows: [string, string][] = [
    ["Booking ID", row.code],
    ["Guest", `${row.guestName}${row.guestPhone ? ` · ${row.guestPhone}` : ""}`],
    ["Sport / Court", `${row.sportName ?? "—"} · ${row.courtName}`],
    ["Date", fmtDate(row.startTime)],
    ["Time", `${fmtTime(row.startTime)} – ${fmtTime(row.endTime)}`],
    ["Players", String(row.partySize)],
    ["Amount", money(row.amountMinor, row.currency)],
    ["Payment", `${titleCase(row.paymentStatus)}${row.paymentMethod ? ` · ${row.paymentMethod}` : ""}`],
    ["Status", titleCase(row.status)],
  ];
  const heading = kind === "invoice" ? "Invoice" : "Booking Receipt";
  return `<!doctype html><html><head><meta charset="utf-8"><title>${esc(row.code)} ${esc(heading)}</title>
<style>
  *{box-sizing:border-box;font-family:-apple-system,Segoe UI,Roboto,sans-serif}
  body{margin:0;padding:40px;color:#1f2937}
  .brand{font-size:22px;font-weight:700;color:#00834f}
  .facility{font-size:14px;font-weight:600;margin-top:2px}
  h1{font-size:16px;margin:28px 0 12px}
  table{width:100%;border-collapse:collapse;font-size:13px}
  td{padding:8px 0;border-bottom:1px solid #eee}
  td:first-child{color:#6b7280;width:180px}
  td:last-child{font-weight:600;text-align:right}
  .foot{margin-top:28px;font-size:11px;color:#9ca3af}
  @media print{body{padding:24px}}
</style></head><body>
  <div class="brand">${esc(APP_NAME)}</div>
  <div class="facility">${esc(facilityName)}</div>
  <h1>${esc(heading)}</h1>
  <table>${rows.map(([k, v]) => `<tr><td>${esc(k)}</td><td>${esc(v)}</td></tr>`).join("")}</table>
  <p class="foot">Generated ${new Date().toLocaleString("en-IN")} · Thank you for booking with us.</p>
  <script>window.onload=function(){window.print()}</script>
</body></html>`;
}

function money(minor: number | null, currency: string): string {
  return minor == null ? "—" : formatCurrency(minor, currency);
}
function titleCase(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1).toLowerCase();
}

/** Opens the HTML in a new tab; it auto-triggers the browser print dialog
 *  (the user's "Save as PDF" is the download). */
export function openPrintable(html: string): void {
  const w = window.open("", "_blank");
  if (!w) return;
  w.document.write(html);
  w.document.close();
}
