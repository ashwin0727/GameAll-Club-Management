import type { ScheduleBlock, ScheduleCourtRow } from "@/features/dashboard/types";

/**
 * live       something is on this court right now
 * booked     the court has a booking still to come today
 * available  nothing more today
 */
export type ActivityStatus = "live" | "booked" | "available";

export interface CourtNow {
  court: ScheduleCourtRow;
  block: ScheduleBlock | null;
  status: ActivityStatus;
  /** Until when a live court stays busy, in minutes from midnight. */
  busyUntil: number | null;
}

/** Per court: what is on right now, else its next booking, else it is free. */
export function courtsNow(courts: ScheduleCourtRow[], nowMinute: number, isToday: boolean): CourtNow[] {
  return courts.map((court) => {
    const sorted = [...court.blocks].sort((a, b) => a.startMinute - b.startMinute);
    const live = isToday ? sorted.find((b) => b.startMinute <= nowMinute && nowMinute < b.endMinute) : undefined;
    if (live) return { court, block: live, status: "live", busyUntil: live.endMinute };
    const upcoming = sorted.find((b) => b.startMinute > (isToday ? nowMinute : -1));
    if (upcoming) return { court, block: upcoming, status: "booked", busyUntil: null };
    return { court, block: null, status: "available", busyUntil: null };
  });
}
