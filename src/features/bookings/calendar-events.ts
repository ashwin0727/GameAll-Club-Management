import type { Booking } from "@/features/bookings/types";
import type { MembershipSessionSlot } from "@/features/membership-sessions/types";
import type { OperatingDay } from "@/features/operating-hours/types";
import { windowsForDay } from "@/features/bookings/slots";

/** What a block on the calendar is. Each kind has its own colour. */
/**
 * GUEST is every court booking — whoever it is for, including an existing member.
 * Memberships appear as SESSION (their batch window), coaching as COACHING.
 */
export type CalEventKind = "GUEST" | "SESSION" | "COACHING" | "MAINTENANCE";

export interface CalEvent {
  id: string;
  courtId: string;
  start: Date;
  end: Date;
  kind: CalEventKind;
  title: string;
  subtitle: string;
  /** Booking status (pending / confirmed / completed); unset for non-bookings. */
  status?: string;
  paymentStatus?: string;
  /** Set for GUEST (a court booking) — opens the booking details dialog. */
  booking?: Booking;
  /** Set for SESSION — opens the membership-session dialog. */
  membershipSlot?: MembershipSessionSlot;
  /** Set for COACHING / MAINTENANCE — the existing page that owns the record. */
  href?: string;
}

/** Agenda covers the same period as Month, listed by day instead of drawn as a grid. */
export type CalView = "day" | "week" | "month" | "agenda";

export const EVENT_KIND_LABEL: Record<CalEventKind, string> = {
  GUEST: "Guest",
  SESSION: "Members",
  COACHING: "Coaching",
  MAINTENANCE: "Maintenance",
};

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const MONTHS_LONG = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

export function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

export function addDays(d: Date, n: number): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
}

export function isSameDay(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

/** Monday of the week containing `d` — the calendar week starts on Monday. */
export function startOfWeek(d: Date): Date {
  return addDays(startOfDay(d), -((d.getDay() + 6) % 7));
}

/** [from, to) covering the visible period. */
export function rangeFor(view: CalView, anchor: Date): { from: Date; to: Date } {
  if (view === "day") {
    const from = startOfDay(anchor);
    return { from, to: addDays(from, 1) };
  }
  if (view === "week") {
    const from = startOfWeek(anchor);
    return { from, to: addDays(from, 7) };
  }
  return {
    from: new Date(anchor.getFullYear(), anchor.getMonth(), 1),
    to: new Date(anchor.getFullYear(), anchor.getMonth() + 1, 1),
  };
}

/**
 * What to load for a view. Day and Week load exactly their period; Month loads
 * the whole grid — the leading and trailing days of the neighbouring months are
 * drawn too, so they need their items as well.
 */
export function dataRange(view: CalView, anchor: Date): { from: Date; to: Date } {
  if (view !== "month") return rangeFor(view, anchor);
  const grid = monthGridDays(anchor);
  return { from: grid[0]!, to: addDays(grid[grid.length - 1]!, 1) };
}

/** Every calendar day inside the visible period. */
export function daysInRange(view: CalView, anchor: Date): Date[] {
  const { from, to } = rangeFor(view, anchor);
  const out: Date[] = [];
  for (let d = from; d < to; d = addDays(d, 1)) out.push(d);
  return out;
}

export function shiftAnchor(view: CalView, anchor: Date, direction: 1 | -1): Date {
  if (view === "day") return addDays(anchor, direction);
  if (view === "week") return addDays(anchor, 7 * direction);
  const first = new Date(anchor.getFullYear(), anchor.getMonth() + direction, 1);
  const daysInTarget = new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate();
  return new Date(first.getFullYear(), first.getMonth(), Math.min(anchor.getDate(), daysInTarget));
}

export function rangeLabel(view: CalView, anchor: Date): string {
  if (view === "day") {
    return `${WEEKDAYS[anchor.getDay()]}, ${String(anchor.getDate()).padStart(2, "0")} ${MONTHS[anchor.getMonth()]} ${anchor.getFullYear()}`;
  }
  if (view === "week") {
    const from = startOfWeek(anchor);
    const last = addDays(from, 6);
    const sameMonth = from.getMonth() === last.getMonth();
    return sameMonth
      ? `${from.getDate()} – ${last.getDate()} ${MONTHS[last.getMonth()]} ${last.getFullYear()}`
      : `${from.getDate()} ${MONTHS[from.getMonth()]} – ${last.getDate()} ${MONTHS[last.getMonth()]} ${last.getFullYear()}`;
  }
  return `${MONTHS_LONG[anchor.getMonth()]} ${anchor.getFullYear()}`;
}

/** The weeks shown by the month grid, Monday-first, padded with neighbouring days. */
export function monthGridDays(anchor: Date): Date[] {
  const first = new Date(anchor.getFullYear(), anchor.getMonth(), 1);
  const gridStart = startOfWeek(first);
  const daysInMonth = new Date(anchor.getFullYear(), anchor.getMonth() + 1, 0).getDate();
  const offset = (first.getDay() + 6) % 7;
  const weeks = Math.ceil((offset + daysInMonth) / 7);
  return Array.from({ length: weeks * 7 }, (_, i) => addDays(gridStart, i));
}

export interface EventFilters {
  courtId: string;
  /** "EVENT" is offered in the filter; no calendar item has that kind yet, so choosing it shows none. */
  kind: "" | CalEventKind | "EVENT";
  status: "" | "pending" | "confirmed" | "completed";
}

export function filterEvents(events: CalEvent[], filters: EventFilters): CalEvent[] {
  return events.filter((e) => {
    if (filters.courtId && e.courtId !== filters.courtId) return false;
    if (filters.kind && e.kind !== filters.kind) return false;
    // Status only exists on bookings, so picking one narrows to bookings.
    if (filters.status && e.status !== filters.status) return false;
    return true;
  });
}

/**
 * The Agenda: for each day that has anything on it, its items by time and then in court
 * order. Days with nothing are left out.
 */
export function agendaDays(
  events: CalEvent[],
  days: Date[],
  courtOrder: (courtId: string) => number,
): { day: Date; events: CalEvent[] }[] {
  const out: { day: Date; events: CalEvent[] }[] = [];
  for (const day of days) {
    const items = eventsOnDay(events, day).sort(
      (a, b) => a.start.getTime() - b.start.getTime() || courtOrder(a.courtId) - courtOrder(b.courtId),
    );
    if (items.length > 0) out.push({ day, events: items });
  }
  return out;
}

export function eventsOnDay(events: CalEvent[], day: Date): CalEvent[] {
  const from = startOfDay(day);
  const to = addDays(from, 1);
  return events.filter((e) => e.start < to && e.end > from);
}

interface Interval {
  start: number;
  end: number;
}

function mergedMinutes(intervals: Interval[]): number {
  const sorted = [...intervals].sort((a, b) => a.start - b.start);
  let total = 0;
  let curStart = -1;
  let curEnd = -1;
  for (const it of sorted) {
    if (it.start > curEnd) {
      if (curEnd > curStart) total += curEnd - curStart;
      curStart = it.start;
      curEnd = it.end;
    } else {
      curEnd = Math.max(curEnd, it.end);
    }
  }
  if (curEnd > curStart) total += curEnd - curStart;
  return total;
}

/**
 * Share of open court-time that is occupied. Maintenance blocks don't count
 * as use, and time outside a court's operating windows is neither open nor
 * used. Overlapping events on one court are merged so nothing counts twice.
 */
export function computeUtilization(
  events: CalEvent[],
  courtIds: string[],
  days: Date[],
  dayFor: (courtId: string, date: Date) => OperatingDay | null,
): { percent: number; exactPercent: number; activeCourts: number; bookedMinutes: number; openMinutes: number } {
  let open = 0;
  let booked = 0;
  const active = new Set<string>();

  for (const courtId of courtIds) {
    const courtEvents = events.filter((e) => e.courtId === courtId && e.kind !== "MAINTENANCE");
    for (const day of days) {
      const schedule = dayFor(courtId, day);
      const windows = schedule ? windowsForDay(schedule) : [];
      const dayStart = startOfDay(day).getTime();
      const used: Interval[] = [];
      for (const w of windows) {
        open += w.endMin - w.startMin;
        for (const e of courtEvents) {
          const s = Math.max((e.start.getTime() - dayStart) / 60000, w.startMin);
          const en = Math.min((e.end.getTime() - dayStart) / 60000, w.endMin);
          if (en > s) used.push({ start: s, end: en });
        }
      }
      const minutes = mergedMinutes(used);
      booked += minutes;
      if (minutes > 0) active.add(courtId);
    }
  }

  return {
    percent: open > 0 ? Math.min(100, Math.round((booked / open) * 100)) : 0,
    // Unrounded, for display: a few hours across a month is well under 1%, and "0%" would hide that.
    exactPercent: open > 0 ? Math.min(100, (booked / open) * 100) : 0,
    activeCourts: active.size,
    bookedMinutes: booked,
    openMinutes: open,
  };
}
