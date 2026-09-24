import { phoneKey } from "@/features/bookings/guest-insights";
import type { GuestBookingRow } from "@/features/bookings/types";

/**
 * Potential Members: guests who book often and aren't members yet.
 *
 * Built from a sport's whole guest-booking history. A guest is one phone number (last ten
 * digits); cancelled bookings never count; a guest whose phone matches a current member is a
 * member, not a potential one.
 */

const DAY_MS = 86_400_000;
const MONTH_DAYS = 30.4375;

/** The number of bookings that makes a guest a potential member. */
export const POTENTIAL_MIN_BOOKINGS = 3;

export interface GuestProfile {
  key: string;
  name: string;
  phone: string | null;
  bookings: number;
  /** The most recent booking that has started (else the earliest one still to come). ISO. */
  lastBookingAt: string;
  /** Collected money across all their bookings, in minor units. */
  totalSpentMinor: number;
  /** The court they book most (ties go to the one they booked most recently). */
  preferredCourt: string;
  /** "Frequent" if they booked in the last 30 days, otherwise "Returning". */
  label: "Frequent" | "Returning";
  /** What they pay in bookings per month: total spent over the months since their first booking (at least one). */
  monthlySpendMinor: number;
  isMember: boolean;
}

/** Every guest with a usable phone number, from live (non-cancelled) bookings. */
export function buildGuestProfiles(rows: GuestBookingRow[], memberKeys: ReadonlySet<string>, now: Date): GuestProfile[] {
  const byGuest = new Map<string, GuestBookingRow[]>();
  for (const r of rows) {
    if (r.status === "cancelled") continue;
    const key = phoneKey(r.guestPhone);
    if (!key) continue;
    const list = byGuest.get(key);
    if (list) list.push(r);
    else byGuest.set(key, [r]);
  }

  const nowMs = now.getTime();
  const profiles: GuestProfile[] = [];
  for (const [key, list] of byGuest) {
    const newestFirst = [...list].sort((a, b) => b.startTime.localeCompare(a.startTime));
    const started = newestFirst.filter((r) => new Date(r.startTime).getTime() <= nowMs);
    const last = started[0] ?? newestFirst[newestFirst.length - 1]!;
    const earliest = newestFirst[newestFirst.length - 1]!;

    const perCourt = new Map<string, number>();
    for (const r of newestFirst) perCourt.set(r.courtName, (perCourt.get(r.courtName) ?? 0) + 1);
    let preferredCourt = newestFirst[0]!.courtName;
    for (const r of newestFirst) {
      if ((perCourt.get(r.courtName) ?? 0) > (perCourt.get(preferredCourt) ?? 0)) preferredCourt = r.courtName;
    }

    const totalSpentMinor = list.reduce((sum, r) => sum + r.paidMinor, 0);
    const months = Math.max(1, (nowMs - new Date(earliest.startTime).getTime()) / DAY_MS / MONTH_DAYS);
    const lastMs = new Date(last.startTime).getTime();
    profiles.push({
      key,
      name: newestFirst[0]!.guestName,
      phone: newestFirst[0]!.guestPhone,
      bookings: list.length,
      lastBookingAt: last.startTime,
      totalSpentMinor,
      preferredCourt,
      label: lastMs <= nowMs && nowMs - lastMs <= 30 * DAY_MS ? "Frequent" : "Returning",
      monthlySpendMinor: Math.round(totalSpentMinor / months),
      isMember: memberKeys.has(key),
    });
  }
  return profiles;
}

export interface SegmentStats {
  /** Potential members. */
  count: number;
  /** What they would bring in a month, if each paid what they already spend on bookings. */
  monthlyRevenueMinor: number;
  /** Potential members as a share of every frequent guest (3+ bookings), members included. 0–100. */
  conversionPercent: number;
  /** Bookings per potential member. */
  avgBookings: number;
}

export function potentialMembers(guests: GuestProfile[]): GuestProfile[] {
  return guests.filter((g) => !g.isMember && g.bookings >= POTENTIAL_MIN_BOOKINGS);
}

export function segmentStats(guests: GuestProfile[]): SegmentStats {
  const potential = potentialMembers(guests);
  const frequent = guests.filter((g) => g.bookings >= POTENTIAL_MIN_BOOKINGS).length;
  return {
    count: potential.length,
    monthlyRevenueMinor: potential.reduce((sum, g) => sum + g.monthlySpendMinor, 0),
    conversionPercent: frequent > 0 ? (potential.length / frequent) * 100 : 0,
    avgBookings: potential.length > 0 ? potential.reduce((sum, g) => sum + g.bookings, 0) / potential.length : 0,
  };
}

export type LastBookingFilter = "any" | "7" | "30" | "90";

export interface PotentialFilters {
  search: string;
  /** "" = any court. */
  court: string;
  minBookings: number;
  lastBooking: LastBookingFilter;
  /** Minor units; 0 = any amount. */
  minSpentMinor: number;
}

export function filterPotential(guests: GuestProfile[], f: PotentialFilters, now: Date): GuestProfile[] {
  const q = f.search.trim().toLowerCase();
  const qDigits = q.replace(/\D/g, "");
  const cutoff = f.lastBooking === "any" ? null : now.getTime() - Number(f.lastBooking) * DAY_MS;
  return guests.filter((g) => {
    if (g.bookings < f.minBookings) return false;
    if (f.court && g.preferredCourt !== f.court) return false;
    if (g.totalSpentMinor < f.minSpentMinor) return false;
    if (cutoff !== null && new Date(g.lastBookingAt).getTime() < cutoff) return false;
    if (!q) return true;
    return g.name.toLowerCase().includes(q) || (qDigits.length >= 3 && (g.phone ?? "").replace(/\D/g, "").includes(qDigits));
  });
}

export type PotentialSortDir = "asc" | "desc";

/** Most bookings first by default; ties go to whoever booked most recently. */
export function sortByBookings(guests: GuestProfile[], dir: PotentialSortDir): GuestProfile[] {
  const sign = dir === "asc" ? 1 : -1;
  return [...guests].sort((a, b) => sign * (a.bookings - b.bookings) || b.lastBookingAt.localeCompare(a.lastBookingAt));
}
