import type { Booking } from "@/features/bookings/types";

export interface TodaysOperationsSummary {
  totalBookings: number;
  upcoming: number;
  currentlyOccupied: number;
}

/**
 * Owner-facing "what's happening right now" counts (spec: Today's
 * Operations). Only counts live bookings (pending/confirmed) — cancelled
 * bookings never occupy a slot, completed ones are in the past.
 */
export function computeTodaysOperations(bookings: Booking[], now: Date): TodaysOperationsSummary {
  const live = bookings.filter((b) => b.status === "pending" || b.status === "confirmed");
  const upcoming = live.filter((b) => new Date(b.startTime) > now);
  const currentlyOccupied = live.filter((b) => new Date(b.startTime) <= now && now < new Date(b.endTime));
  return {
    totalBookings: live.length,
    upcoming: upcoming.length,
    currentlyOccupied: currentlyOccupied.length,
  };
}

export type CourtLiveStatus =
  | { state: "occupied"; booking: Booking }
  | { state: "available" };

/** "What is happening on this court right now?" — one booking wins if several overlap (shouldn't, given the exclusion constraint), earliest start first. */
export function currentCourtStatus(courtId: string, bookings: Booking[], now: Date): CourtLiveStatus {
  const active = bookings
    .filter((b) => b.courtId === courtId && (b.status === "pending" || b.status === "confirmed"))
    .filter((b) => new Date(b.startTime) <= now && now < new Date(b.endTime))
    .sort((a, b) => new Date(a.startTime).getTime() - new Date(b.startTime).getTime());

  if (active.length > 0) return { state: "occupied", booking: active[0]! };
  return { state: "available" };
}