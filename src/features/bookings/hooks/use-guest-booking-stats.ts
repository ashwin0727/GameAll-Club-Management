"use client";

import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { getBookingService } from "@/services/bookings";
import { buildGuestStats, countUpcoming, parseIsoDate, previousRange, type GuestStats } from "@/features/bookings/guest-booking-stats";
import type { GuestBookingListParams, GuestBookingRow } from "@/features/bookings/types";

/** Rows per request, and a ceiling on requests so a runaway range can't hammer the database. */
const PAGE_SIZE = 500;
const MAX_PAGES = 20;

function iso(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

/**
 * Every guest booking in [from, to] for one sport — the list, fetched a page at a time until it is
 * all here. Leave `from` / `to` out for the sport's whole history. `extra` narrows it further with the same filters the table has (search, court, …).
 */
export async function fetchAllGuestBookings(
  facilityId: string,
  facilitySportId: string,
  from: string | undefined,
  to: string | undefined,
  extra: Partial<Pick<GuestBookingListParams, "search" | "courtId" | "status" | "paymentStatus">> = {},
): Promise<GuestBookingRow[]> {
  const svc = getBookingService();
  const out: GuestBookingRow[] = [];
  for (let page = 1; page <= MAX_PAGES; page++) {
    const result = await svc.listGuestBookings(facilityId, { ...extra, facilitySportId, from, to, page, perPage: PAGE_SIZE });
    out.push(...result.rows);
    if (out.length >= result.totalCount || result.rows.length === 0) break;
  }
  return out;
}

/**
 * The Guest Bookings header figures for one sport: the selected period, the period just
 * before it (for the comparison lines), and the bookings still to come. Worked out from
 * the same list the table uses, so the cards and the table always agree — and, because the
 * list is sport-aware, so are they. The previous result stays on screen while a new one loads.
 */
export function useGuestBookingStats(facilityId: string | null, facilitySportId: string, from: string, to: string) {
  return useQuery({
    queryKey: ["guest-booking-stats", facilityId, facilitySportId, from, to],
    enabled: Boolean(facilityId) && Boolean(facilitySportId),
    placeholderData: keepPreviousData,
    staleTime: 15_000,
    queryFn: async (): Promise<GuestStats & { upcoming: number }> => {
      const fid = facilityId!;
      const before = previousRange(from, to);
      const today = new Date();
      const horizon = parseIsoDate(iso(today));
      horizon.setDate(horizon.getDate() + 365);
      const [current, previous, ahead] = await Promise.all([
        fetchAllGuestBookings(fid, facilitySportId, from, to),
        fetchAllGuestBookings(fid, facilitySportId, before.from, before.to),
        fetchAllGuestBookings(fid, facilitySportId, iso(today), iso(horizon)),
      ]);
      return { ...buildGuestStats(current, previous), upcoming: countUpcoming(ahead, new Date()) };
    },
  });
}

/** Every guest booking a sport has ever had — what the Recent Guests and Guest Insights cards are worked out from. */
export function useGuestHistory(facilityId: string | null, facilitySportId: string) {
  return useQuery({
    queryKey: ["guest-history", facilityId, facilitySportId],
    enabled: Boolean(facilityId) && Boolean(facilitySportId),
    placeholderData: keepPreviousData,
    staleTime: 30_000,
    queryFn: () => fetchAllGuestBookings(facilityId!, facilitySportId, undefined, undefined),
  });
}
