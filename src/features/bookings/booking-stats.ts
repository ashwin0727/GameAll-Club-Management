import type { CalEvent, CalEventKind } from "@/features/bookings/calendar-events";
import type { BookingRow, ListKind } from "@/features/bookings/list-utils";

/**
 * Guest bookings among the listed rows. Cancelled ones don't count unless the
 * status filter is asking for exactly those.
 */
export function countGuestBookings(rows: BookingRow[], includeCancelled: boolean): number {
  return rows.filter((r) => r.kind === "GUEST" && (includeCancelled || r.status !== "cancelled")).length;
}

/** Guest bookings on the calendar that start in [from, to). Cancelled bookings are never on the calendar. */
export function countGuestEvents(events: CalEvent[], from: Date, to: Date): number {
  return events.filter((e) => e.kind === "GUEST" && e.start >= from && e.start < to).length;
}

/** Money actually collected against the listed rows, in minor units. */
export function collectedMinor(rows: BookingRow[]): number {
  return rows.reduce((sum, r) => sum + r.collectedMinor, 0);
}

/** The list's type filter, in the calendar's terms (a membership shows on the calendar as a membership session). */
export function listKindToEventKind(kind: "" | ListKind | "EVENT"): "" | CalEventKind | "EVENT" {
  return kind === "MEMBERSHIP" ? "SESSION" : kind;
}

/**
 * A utilization figure for display. Whole numbers from 10% up; one decimal below
 * that, so a light month reads "0.5%" instead of a misleading "0%"; and "<0.1%"
 * when there is some use but almost none. Exactly nothing stays "0%".
 */
export function formatUtilization(percent: number): string {
  if (!(percent > 0)) return "0%";
  if (percent < 0.1) return "<0.1%";
  if (percent < 10) return `${(Math.round(percent * 10) / 10).toString()}%`;
  return `${Math.round(percent)}%`;
}

/** A "↑ 12% vs last month" line: what it says and which way it points (for its colour). */
export interface StatDelta {
  text: string;
  tone: "up" | "down" | "flat";
}

/** Relative change, or null when there was nothing before to compare with. */
export function percentChange(current: number, previous: number): number | null {
  if (!(previous > 0)) return null;
  return ((current - previous) / previous) * 100;
}

const ARROW = { up: "↑", down: "↓", flat: "→" } as const;

/** "↑ 12% vs last month" — null when the previous period had nothing to compare against. */
export function percentDelta(current: number, previous: number, versus: string): StatDelta | null {
  const change = percentChange(current, previous);
  if (change === null) return null;
  const rounded = Math.round(Math.abs(change));
  const tone = rounded === 0 ? "flat" : change > 0 ? "up" : "down";
  return { text: `${ARROW[tone]} ${rounded}% ${versus}`, tone };
}

/** For figures that are themselves percentages (utilization): the change in points, "↑ 6 pts vs last month". */
export function pointsDelta(currentPercent: number, previousPercent: number, versus: string): StatDelta | null {
  if (currentPercent === 0 && previousPercent === 0) return null;
  const diff = currentPercent - previousPercent;
  const abs = Math.abs(diff);
  const shown = abs < 10 ? Math.round(abs * 10) / 10 : Math.round(abs);
  const tone = shown === 0 ? "flat" : diff > 0 ? "up" : "down";
  return { text: `${ARROW[tone]} ${shown} pts ${versus}`, tone };
}

/** Every calendar day from `from` to `to`, both included. */
export function daysBetween(from: Date, to: Date): Date[] {
  const out: Date[] = [];
  for (let d = new Date(from.getFullYear(), from.getMonth(), from.getDate()); d <= to; d = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1)) {
    out.push(d);
  }
  return out;
}
