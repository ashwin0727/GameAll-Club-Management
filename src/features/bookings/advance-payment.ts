/**
 * A guest booking longer than an hour is secured with a 50% advance paid ONLINE; shorter ones are unaffected.
 * Mirrors guest_booking_advance_minor in migration 0130 — the database is what actually decides the amount
 * charged, this is only for showing it beforehand.
 */
export const ADVANCE_PERCENT = 50;

const HOUR_MS = 3_600_000;

/** True when the booking runs for more than one hour. */
export function needsAdvance(startIso: string, endIso: string): boolean {
  return new Date(endIso).getTime() - new Date(startIso).getTime() > HOUR_MS;
}

/** The advance for a booking of `totalMinor`: half, rounded up to the next minor unit. */
export function advanceMinor(totalMinor: number): number {
  return Math.ceil((totalMinor * ADVANCE_PERCENT) / 100);
}

export interface AdvanceSummary {
  /** At least one booking is longer than an hour, so an online advance is compulsory. */
  required: boolean;
  /** Collected online now, across every booking that needs it. Null while any such booking has no price yet. */
  dueNowMinor: number | null;
  /** What is left to collect afterwards (the rest of the long bookings plus any short ones). */
  balanceMinor: number | null;
  /** How many bookings need an advance. */
  longCount: number;
}

/** `runs` are the bookings about to be made, each with its own price (null when unpriced). */
export function advanceSummary(runs: { startTime: string; endTime: string; totalMinor: number | null }[]): AdvanceSummary {
  const long = runs.filter((r) => needsAdvance(r.startTime, r.endTime));
  if (long.length === 0) return { required: false, dueNowMinor: 0, balanceMinor: null, longCount: 0 };
  if (runs.some((r) => r.totalMinor == null)) return { required: true, dueNowMinor: null, balanceMinor: null, longCount: long.length };
  const dueNow = long.reduce((sum, r) => sum + advanceMinor(r.totalMinor as number), 0);
  const total = runs.reduce((sum, r) => sum + (r.totalMinor as number), 0);
  return { required: true, dueNowMinor: dueNow, balanceMinor: total - dueNow, longCount: long.length };
}
