import type { GuestBookingRow, GuestBookingsSummary } from "@/features/bookings/types";

/** The figures from the period just before the selected one — what the "from previous period" lines compare with. */
export interface PreviousPeriod {
  total: number;
  completed: number;
  cancelled: number;
  revenueMinor: number;
}

export interface GuestStats {
  summary: GuestBookingsSummary;
  previous: PreviousPeriod;
}

function localDate(iso: string): string {
  const d = new Date(iso);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

/** "2026-09-01" → local midnight (a bare `new Date("2026-09-01")` is UTC and can slip a day). */
export function parseIsoDate(iso: string): Date {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(y!, (m ?? 1) - 1, d ?? 1);
}

function isoDate(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function addDaysIso(iso: string, n: number): string {
  const d = parseIsoDate(iso);
  d.setDate(d.getDate() + n);
  return isoDate(d);
}

/** The stretch of the same length that ends the day before `from` — [from − length, from − 1]. */
export function previousRange(from: string, to: string): { from: string; to: string } {
  const length = Math.round((parseIsoDate(to).getTime() - parseIsoDate(from).getTime()) / 86_400_000) + 1;
  return { from: addDaysIso(from, -length), to: addDaysIso(from, -1) };
}

const pct = (current: number, previous: number): number | null =>
  previous === 0 ? null : Math.round(((current - previous) * 100) / previous);

/**
 * The page's summary figures, worked out from the bookings themselves — the same
 * definitions the database summary uses (every booking in the range counts, cancelled
 * included; revenue is money actually collected), but over whatever rows it is given,
 * so it can be limited to one sport.
 */
export function buildGuestStats(current: GuestBookingRow[], previous: GuestBookingRow[]): GuestStats {
  const count = (rows: GuestBookingRow[], status: GuestBookingRow["status"]) => rows.filter((r) => r.status === status).length;
  const revenue = (rows: GuestBookingRow[]) => rows.reduce((sum, r) => sum + r.paidMinor, 0);

  const paid = current.map((r) => r.paidMinor).filter((v) => v > 0);
  const byDay = new Map<string, number>();
  for (const r of current) byDay.set(localDate(r.startTime), (byDay.get(localDate(r.startTime)) ?? 0) + r.paidMinor);

  const totalRevenue = revenue(current);
  return {
    summary: {
      total: current.length,
      confirmed: count(current, "confirmed"),
      completed: count(current, "completed"),
      cancelled: count(current, "cancelled"),
      pending: count(current, "pending"),
      totalRevenueMinor: totalRevenue,
      avgPerBookingMinor: paid.length > 0 ? Math.round(paid.reduce((a, b) => a + b, 0) / paid.length) : 0,
      highestBookingMinor: current.reduce((max, r) => Math.max(max, r.paidMinor), 0),
      totalChangePct: pct(current.length, previous.length),
      revenueChangePct: pct(totalRevenue, revenue(previous)),
      trend: [...byDay.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([date, amountMinor]) => ({ date, amountMinor })),
    },
    previous: {
      total: previous.length,
      completed: count(previous, "completed"),
      cancelled: count(previous, "cancelled"),
      revenueMinor: revenue(previous),
    },
  };
}

/** Bookings still to come: confirmed or pending, and not yet over. */
export function countUpcoming(rows: GuestBookingRow[], now: Date): number {
  return rows.filter((r) => (r.status === "confirmed" || r.status === "pending") && new Date(r.endTime) > now).length;
}
