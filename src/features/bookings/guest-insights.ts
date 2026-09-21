import { parseIsoDate } from "@/features/bookings/guest-booking-stats";
import type { GuestBookingRow } from "@/features/bookings/types";

/**
 * Guest insights, worked out from a sport's whole guest-booking history.
 *
 * - A guest is one phone number (the last ten digits). A booking with no usable phone can't be
 *   matched to anyone, so it isn't counted in the guest figures — only in booking value.
 * - Cancelled bookings never count.
 * - Repeat (2+) and Frequent (3+) look at a guest's whole history, whether or not they booked in
 *   the selected period. The other figures use only the selected period.
 */

const DAY_MS = 86_400_000;

/** "+91 98765 43210" and "98765 43210" are the same guest: the last ten digits, or null if there's no real number. */
export function phoneKey(phone: string | null | undefined): string | null {
  const digits = (phone ?? "").replace(/\D/g, "");
  return digits.length >= 7 ? digits.slice(-10) : null;
}

const isLive = (r: GuestBookingRow) => r.status !== "cancelled";
const startMs = (r: GuestBookingRow) => new Date(r.startTime).getTime();

export type InsightPeriod = "7" | "30" | "90" | "custom";

/** [from, to) for the chosen period — the last N days ending today, or a custom pair of dates. */
export function periodRange(kind: InsightPeriod, custom: { from: string; to: string } | null, now: Date = new Date()): { from: Date; to: Date } {
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  if (kind === "custom" && custom) {
    const to = parseIsoDate(custom.to);
    to.setDate(to.getDate() + 1);
    return { from: parseIsoDate(custom.from), to };
  }
  const days = kind === "7" ? 7 : kind === "90" ? 90 : 30;
  const from = new Date(startOfToday);
  from.setDate(from.getDate() - (days - 1));
  const to = new Date(startOfToday);
  to.setDate(to.getDate() + 1);
  return { from, to };
}

export interface InsightFigures {
  /** Different guests who booked in the period. */
  unique: number;
  /** Bookings in the period (cancelled excluded). */
  bookings: number;
  /** Bookings per unique guest. */
  avgBookings: number;
  /** Money collected per booking, in minor units. */
  avgValueMinor: number;
  /** Of the guests who booked in the period, the share whose first booking ever fell in it (0–100). */
  newPercent: number;
}

/** How many guests have made at least `n` bookings, ever. */
export function guestsWithAtLeast(rows: GuestBookingRow[], n: number): number {
  return [...countsBefore(rows).values()].filter((c) => c >= n).length;
}

export interface GuestInsights {
  current: InsightFigures;
  /** The same figures for the stretch of equal length just before. */
  previous: InsightFigures;
  /** Guests with 2+ bookings, ever. */
  repeat: number;
  /** Guests with 3+ bookings, ever. */
  frequent: number;
  /** How many of each there were the day the period began — what the arrows compare with. */
  repeatAtStart: number;
  frequentAtStart: number;
}

function countsBefore(rows: GuestBookingRow[], cutoffMs?: number): Map<string, number> {
  const counts = new Map<string, number>();
  for (const r of rows) {
    if (!isLive(r)) continue;
    const key = phoneKey(r.guestPhone);
    if (!key) continue;
    if (cutoffMs !== undefined && startMs(r) >= cutoffMs) continue;
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return counts;
}

function firstBooking(rows: GuestBookingRow[]): Map<string, number> {
  const first = new Map<string, number>();
  for (const r of rows) {
    if (!isLive(r)) continue;
    const key = phoneKey(r.guestPhone);
    if (!key) continue;
    const t = startMs(r);
    if (t < (first.get(key) ?? Infinity)) first.set(key, t);
  }
  return first;
}

function figures(rows: GuestBookingRow[], from: number, to: number, first: Map<string, number>): InsightFigures {
  const inPeriod = rows.filter((r) => isLive(r) && startMs(r) >= from && startMs(r) < to);
  const withPhone = inPeriod.filter((r) => phoneKey(r.guestPhone) !== null);
  const guests = new Set(withPhone.map((r) => phoneKey(r.guestPhone)!));
  const collected = inPeriod.reduce((sum, r) => sum + r.paidMinor, 0);
  const newGuests = [...guests].filter((k) => {
    const f = first.get(k)!;
    return f >= from && f < to;
  }).length;
  return {
    unique: guests.size,
    bookings: inPeriod.length,
    avgBookings: guests.size > 0 ? withPhone.length / guests.size : 0,
    avgValueMinor: inPeriod.length > 0 ? Math.round(collected / inPeriod.length) : 0,
    newPercent: guests.size > 0 ? (newGuests / guests.size) * 100 : 0,
  };
}

export function computeInsights(rows: GuestBookingRow[], from: Date, to: Date): GuestInsights {
  const length = to.getTime() - from.getTime();
  const first = firstBooking(rows);
  const atLeast = (counts: Map<string, number>, n: number) => [...counts.values()].filter((c) => c >= n).length;
  const now = countsBefore(rows);
  const atStart = countsBefore(rows, from.getTime());
  return {
    current: figures(rows, from.getTime(), to.getTime(), first),
    previous: figures(rows, from.getTime() - length, from.getTime(), first),
    repeat: atLeast(now, 2),
    frequent: atLeast(now, 3),
    repeatAtStart: atLeast(atStart, 2),
    frequentAtStart: atLeast(atStart, 3),
  };
}

export interface RecentGuests {
  /** The guests who booked most recently, newest first. */
  shown: { key: string; name: string }[];
  /** Other guests who booked in the last 30 days, beyond those shown. */
  more: number;
}

/**
 * Who has been in lately: the most recent guests whose bookings have started (an upcoming
 * booking doesn't make someone a recent guest), and how many more booked in the last 30 days.
 */
export function recentGuests(rows: GuestBookingRow[], now: Date, limit = 4, windowDays = 30): RecentGuests {
  const past = rows
    .filter((r) => isLive(r) && phoneKey(r.guestPhone) !== null && startMs(r) <= now.getTime())
    .sort((a, b) => startMs(b) - startMs(a));

  const shown: RecentGuests["shown"] = [];
  const seen = new Set<string>();
  for (const r of past) {
    const key = phoneKey(r.guestPhone)!;
    if (seen.has(key)) continue;
    seen.add(key);
    if (shown.length < limit) shown.push({ key, name: r.guestName });
  }

  const since = now.getTime() - windowDays * DAY_MS;
  const shownKeys = new Set(shown.map((g) => g.key));
  const others = new Set(past.filter((r) => startMs(r) >= since).map((r) => phoneKey(r.guestPhone)!));
  return { shown, more: [...others].filter((k) => !shownKeys.has(k)).length };
}
