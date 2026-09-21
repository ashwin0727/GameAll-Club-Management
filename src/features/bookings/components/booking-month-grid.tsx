"use client";

import { eventsOnDay, isSameDay, monthGridDays, type CalEvent } from "@/features/bookings/calendar-events";
import {
  courtShortName,
  EVENT_CHIP_STYLE,
  EVENT_SHORT_LABEL,
  formatClock,
} from "@/features/bookings/components/booking-event-style";
import { cn } from "@/lib/utils";

const HEADERS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
/** Pills shown per day before the rest fold into "+N more". */
const MAX_CHIPS = 2;

/**
 * Month overview. Every day lists its items as tinted pills — "Members - C01",
 * "Guest - C02", "Coaching - C03" — Court 1's before Court 2's, then "+N more".
 * Each pill leads with its start time. Today's date sits in a green circle;
 * days from the neighbouring months are dimmed. Clicking a day opens it in Day view.
 */
export function BookingMonthGrid({
  anchor,
  events,
  onPickDay,
  courtOrder,
  courtName,
  now,
}: {
  anchor: Date;
  events: CalEvent[];
  onPickDay: (day: Date) => void;
  /** Court rank (0 = first) — a day lists Court 1's items before Court 2's. */
  courtOrder: (courtId: string) => number;
  courtName: (courtId: string) => string;
  now: Date;
}) {
  const days = monthGridDays(anchor);
  return (
    <div className="overflow-hidden rounded-xl border border-border bg-card">
      <div className="grid grid-cols-7 border-b border-border">
        {HEADERS.map((h) => (
          <div key={h} className="px-3 py-3 text-center text-sm font-semibold">
            {h}
          </div>
        ))}
      </div>
      <div className="grid grid-cols-7">
        {days.map((day) => {
          const inMonth = day.getMonth() === anchor.getMonth();
          const today = isSameDay(day, now);
          const dayEvents = eventsOnDay(events, day).sort(
            (a, b) => courtOrder(a.courtId) - courtOrder(b.courtId) || a.start.getTime() - b.start.getTime(),
          );
          const extra = dayEvents.length - MAX_CHIPS;
          return (
            <button
              key={day.getTime()}
              type="button"
              onClick={() => onPickDay(day)}
              className={cn(
                "flex min-h-[112px] flex-col items-stretch gap-1.5 border-b border-r border-border/60 p-2 text-left transition-colors hover:bg-accent/40",
                today && "bg-primary/[0.04]",
                !inMonth && "opacity-50",
              )}
            >
              <span className="flex items-center justify-between">
                <span
                  className={cn(
                    "flex h-7 min-w-7 items-center justify-center rounded-full px-1 text-sm font-medium",
                    today ? "bg-[#0B7A55] text-white dark:bg-primary dark:text-primary-foreground" : "text-foreground",
                  )}
                >
                  {day.getDate()}
                </span>
              </span>
              {dayEvents.slice(0, MAX_CHIPS).map((e) => (
                <span
                  key={e.id}
                  className={cn("truncate rounded-[6px] px-2 py-1 text-[11px] font-medium", EVENT_CHIP_STYLE[e.kind])}
                >
                  <span className="mr-1.5 text-[9px] font-normal opacity-70">{formatClock(e.start)}</span>
                  {EVENT_SHORT_LABEL[e.kind]} - {courtShortName(courtName(e.courtId))}
                </span>
              ))}
              {extra > 0 && (
                <span className="text-[11px] font-medium text-blue-600 dark:text-blue-400">+{extra} more</span>
              )}
            </button>
          );
        })}
      </div>
    </div>
  );
}
