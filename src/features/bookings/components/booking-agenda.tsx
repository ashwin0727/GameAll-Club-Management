"use client";

import { agendaDays, isSameDay, type CalEvent } from "@/features/bookings/calendar-events";
import { EVENT_DOT_STYLE, formatRange } from "@/features/bookings/components/booking-event-style";
import { cn } from "@/lib/utils";

/**
 * The Agenda view: the period as a list, one block per day that has anything on it —
 * bookings, membership sessions, coaching and maintenance blocks, in time order.
 */
export function BookingAgenda({
  events,
  days,
  courtOrder,
  courtName,
  onEventClick,
  now,
}: {
  events: CalEvent[];
  /** The days of the period (a month's days). */
  days: Date[];
  courtOrder: (courtId: string) => number;
  courtName: (courtId: string) => string;
  onEventClick: (event: CalEvent) => void;
  now: Date;
}) {
  const groups = agendaDays(events, days, courtOrder);

  if (groups.length === 0) {
    return (
      <div className="rounded-xl border border-border bg-card p-10 text-center text-sm text-muted-foreground">
        Nothing is scheduled in this period.
      </div>
    );
  }

  return (
    <div className="divide-y divide-border/60 overflow-hidden rounded-xl border border-border bg-card">
      {groups.map(({ day, events: items }) => {
        const today = isSameDay(day, now);
        return (
          <section key={day.getTime()} className="grid grid-cols-[4.5rem_minmax(0,1fr)] gap-3 p-4">
            <div className="text-center leading-tight">
              <p className={cn("text-xs font-medium uppercase text-muted-foreground", today && "text-primary")}>
                {day.toLocaleDateString("en-IN", { weekday: "short" })}
              </p>
              <p
                className={cn(
                  "mx-auto mt-1 flex h-9 w-9 items-center justify-center rounded-full text-lg font-semibold",
                  today && "bg-[#0B7A55] text-white dark:bg-primary dark:text-primary-foreground",
                )}
              >
                {day.getDate()}
              </p>
              <p className="mt-0.5 text-[11px] text-muted-foreground">{day.toLocaleDateString("en-IN", { month: "short" })}</p>
            </div>

            <ul className="min-w-0 space-y-1.5">
              {items.map((e) => (
                <li key={e.id}>
                  <button
                    type="button"
                    onClick={() => onEventClick(e)}
                    className="grid w-full grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-3 rounded-lg px-3 py-2 text-left transition-colors hover:bg-accent/50"
                  >
                    <span className={cn("h-2.5 w-2.5 rounded-full", EVENT_DOT_STYLE[e.kind])} aria-hidden />
                    <span className="min-w-0">
                      <span className="block truncate text-sm font-medium">{e.title}</span>
                      <span className="block truncate text-xs text-muted-foreground">
                        {e.subtitle} · {courtName(e.courtId)}
                      </span>
                    </span>
                    <span className="whitespace-nowrap text-xs tabular-nums text-muted-foreground">{formatRange(e.start, e.end)}</span>
                  </button>
                </li>
              ))}
            </ul>
          </section>
        );
      })}
    </div>
  );
}
