import type { Booking } from "@/features/bookings/types";

/** Court bookings (all "Guest", whoever they are for), plus the memberships and coaching enrolments listed alongside them. */
export type ListKind = "GUEST" | "MEMBERSHIP" | "COACHING";

export type RowStatus = Booking["status"];

/**
 * One row of the table. Court bookings, memberships and coaching enrolments all
 * take this shape, so the table, sorting, filtering and export treat them alike;
 * what differs is only how their duration and amount read.
 */
export interface BookingRow {
  id: string;
  /** The court booking behind the row; null for memberships and coaching, which open their own page. */
  booking: Booking | null;
  kind: ListKind;
  customerName: string;
  /** Full number, kept for search only — never rendered as is. */
  customerPhone: string | null;
  /** First court (or "" when none is known) — kept for bookings, which always have exactly one. */
  courtId: string;
  courtIds: string[];
  /** Court text when it isn't simply the names of courtIds (e.g. a membership's batch court). */
  courtLabel: string | null;
  start: Date;
  end: Date;
  /** Second line under the date. Null = the clock range from start to end. */
  timeLabel: string | null;
  /** Minutes — only for sorting; what is shown is durationLabel. */
  durationMin: number;
  /** "1 Hour", "3 Months", "12 Sessions". */
  durationLabel: string;
  /** Detail under it: "12 hrs · Weekdays", "Mon · Wed · Fri". */
  durationSub: string | null;
  amountMinor: number | null;
  /** Detail under the amount: "₹1,500 / month", "Paid ₹2,000". */
  amountSub: string | null;
  /** Money actually collected against this row, in minor units (0 for unpaid or cancelled). Feeds the revenue card. */
  collectedMinor: number;
  currency: string;
  /** The bucket used for filtering and sorting… */
  status: RowStatus;
  /** …and the wording shown, which can be more specific ("Active", "Payment pending"). */
  statusLabel: string;
  reference: string;
  /** The page that owns a non-booking row. */
  href: string | null;
}

/** The text for the Court(s) column. */
export function courtText(r: BookingRow, courtName: (courtId: string) => string): string {
  if (r.courtLabel) return r.courtLabel;
  return r.courtIds.length > 0 ? r.courtIds.map(courtName).join(", ") : "—";
}

export type SortKey = "date" | "customer" | "court" | "type" | "duration" | "amount" | "status";
export type SortDir = "asc" | "desc";

export interface ListFilters {
  courtId: string;
  /** "EVENT" is offered in the filter; no row has that kind yet, so choosing it lists none. */
  kind: "" | ListKind | "EVENT";
  status: "" | Booking["status"];
  search: string;
}

/** "GBK7F3A" for court bookings, "MEM…" memberships, "COA…" coaching — a short code from the record id. */
const REF_PREFIX: Record<ListKind, string> = { GUEST: "GBK", MEMBERSHIP: "MEM", COACHING: "COA" };
export function bookingReference(id: string, kind: ListKind): string {
  return `${REF_PREFIX[kind]}${id.replace(/-/g, "").slice(0, 4).toUpperCase()}`;
}

/**
 * "+91 98765 43210" → "+91 98••• ••210". Enough to recognise a customer, not
 * enough to copy their number off a screen. Too-short values are fully hidden.
 */
export function maskPhone(phone: string | null | undefined): string {
  if (!phone) return "—";
  const digits = phone.replace(/\D/g, "");
  if (digits.length < 7) return "••••••";
  const national = digits.slice(-10);
  const country = digits.slice(0, digits.length - national.length);
  const body = national.length >= 8 ? `${national.slice(0, 2)}••• ••${national.slice(-3)}` : `••••${national.slice(-3)}`;
  return country ? `+${country} ${body}` : body;
}

/** 30 → "30 Min", 60 → "1 Hour", 90 → "1.5 Hours", 120 → "2 Hours". */
export function formatDuration(minutes: number): string {
  if (minutes < 60) return `${minutes} Min`;
  const hours = minutes / 60;
  const text = Number.isInteger(hours) ? String(hours) : String(Math.round(hours * 10) / 10);
  return `${text} ${hours === 1 ? "Hour" : "Hours"}`;
}

export function filterRows(rows: BookingRow[], f: ListFilters): BookingRow[] {
  const q = f.search.trim().toLowerCase();
  const qDigits = q.replace(/\D/g, "");
  return rows.filter((r) => {
    if (f.courtId && !r.courtIds.includes(f.courtId)) return false;
    if (f.kind && r.kind !== f.kind) return false;
    if (f.status && r.status !== f.status) return false;
    if (!q) return true;
    return (
      r.customerName.toLowerCase().includes(q) ||
      r.reference.toLowerCase().includes(q) ||
      (qDigits.length >= 3 && (r.customerPhone ?? "").replace(/\D/g, "").includes(qDigits))
    );
  });
}

/** How each kind of row is named in the Type column, the filter and the export. */
export const TYPE_LABEL: Record<ListKind, string> = { GUEST: "Guest", MEMBERSHIP: "Membership", COACHING: "Coaching" };

const STATUS_RANK: Record<Booking["status"], number> = { confirmed: 0, pending: 1, completed: 2, cancelled: 3 };

export function sortRows(
  rows: BookingRow[],
  key: SortKey,
  dir: SortDir,
  courtName: (courtId: string) => string,
): BookingRow[] {
  const cmp = (a: BookingRow, b: BookingRow): number => {
    switch (key) {
      case "date":
        return a.start.getTime() - b.start.getTime();
      case "customer":
        return a.customerName.localeCompare(b.customerName);
      case "court":
        return courtText(a, courtName).localeCompare(courtText(b, courtName), undefined, { numeric: true });
      case "type":
        return TYPE_LABEL[a.kind].localeCompare(TYPE_LABEL[b.kind]);
      case "duration":
        return a.durationMin - b.durationMin;
      case "amount":
        return (a.amountMinor ?? -1) - (b.amountMinor ?? -1);
      case "status":
        return STATUS_RANK[a.status] - STATUS_RANK[b.status];
    }
  };
  const sign = dir === "asc" ? 1 : -1;
  // Ties fall back to time so equal values keep a stable, chronological order.
  return [...rows].sort((a, b) => sign * cmp(a, b) || a.start.getTime() - b.start.getTime());
}

export function paginate<T>(items: T[], page: number, perPage: number): { rows: T[]; pages: number; page: number } {
  const pages = Math.max(1, Math.ceil(items.length / perPage));
  const safe = Math.min(Math.max(page, 1), pages);
  return { rows: items.slice((safe - 1) * perPage, safe * perPage), pages, page: safe };
}

/** Page numbers with gaps collapsed: [1, "…", 4, 5, 6, "…", 12]. */
export function pageWindow(page: number, pages: number): (number | "…")[] {
  if (pages <= 7) return Array.from({ length: pages }, (_, i) => i + 1);
  const out: (number | "…")[] = [1];
  const from = Math.max(2, page - 1);
  const to = Math.min(pages - 1, page + 1);
  if (from > 2) out.push("…");
  for (let p = from; p <= to; p++) out.push(p);
  if (to < pages - 1) out.push("…");
  out.push(pages);
  return out;
}

function csvCell(v: string | number): string {
  const s = String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

/** The export: what the table shows (phones stay masked), one line per row. */
export function bookingsToCsv(rows: BookingRow[], courtName: (courtId: string) => string, formatAmount: (r: BookingRow) => string): string {
  const header = ["Reference", "Date", "Time / details", "Customer", "Phone", "Court", "Type", "Duration", "Duration details", "Amount", "Amount details", "Status"];
  const time = (d: Date) => d.toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit", hour12: true });
  const lines = rows.map((r) =>
    [
      r.reference,
      r.start.toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" }),
      r.timeLabel ?? `${time(r.start)} - ${time(r.end)}`,
      r.customerName,
      maskPhone(r.customerPhone),
      courtText(r, courtName),
      TYPE_LABEL[r.kind],
      r.durationLabel,
      r.durationSub ?? "",
      formatAmount(r),
      r.amountSub ?? "",
      r.statusLabel,
    ]
      .map(csvCell)
      .join(","),
  );
  return [header.join(","), ...lines].join("\n");
}
