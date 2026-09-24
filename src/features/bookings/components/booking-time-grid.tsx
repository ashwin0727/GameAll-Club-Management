"use client";

import type { CalEvent } from "@/features/bookings/calendar-events";
import { closedSpans, layoutWithOverflow } from "@/features/bookings/calendar-layout";
import type { MinuteWindow } from "@/features/bookings/slots";
import { EVENT_BLOCK_STYLE, formatRange } from "@/features/bookings/components/booking-event-style";
import { cn } from "@/lib/utils";

/** One hour is this tall, so 30 min = 30px and a booking's block is exactly as tall as its length. */
export const HOUR_PX = 60;
const PX_PER_MIN = HOUR_PX / 60;
const MIN_BLOCK_PX = 30;
const GUTTER_PX = 64;
const COL_MIN_PX = 132;

export interface GridColumn {
  key: string;
  header: React.ReactNode;
  day: Date;
  events: CalEvent[];
  /** Operating windows; time outside them is shaded. Omit to shade nothing. */
  open?: MinuteWindow[];
  today?: boolean;
}

function hourLabel(hour: number): string {
  const h = hour % 24;
  return `${h % 12 === 0 ? 12 : h % 12}:00 ${h < 12 ? "AM" : "PM"}`;
}

/**
 * The time grid behind Day (a column per court) and Week (a column per day).
 * Hours run down the side; each booking is one block placed by its real start
 * and end, so it always lines up with the rows it occupies.
 */
export function BookingTimeGrid({
  columns,
  startHour,
  endHour,
  onEventClick,
  onEmptyClick,
  courtName,
  courtOrder,
  maxLanes,
  onOverflowClick,
  now,
}: {
  columns: GridColumn[];
  startHour: number;
  endHour: number;
  onEventClick: (event: CalEvent) => void;
  /** Called with the minute-of-day of a click on empty space in a column. */
  onEmptyClick?: (column: GridColumn, minuteOfDay: number) => void;
  /** When set, blocks name their court (Week view, where columns are days). */
  courtName?: (courtId: string) => string;
  /** Court rank (0 = first): in a busy slot Court 1 is drawn first, then Court 2. */
  courtOrder?: (courtId: string) => number;
  /** Most bookings drawn side by side in one slot; the rest collapse into a "+N more" pill. */
  maxLanes?: number;
  onOverflowClick?: (column: GridColumn) => void;
  now: Date;
}) {
  const startMin = startHour * 60;
  const endMin = endHour * 60;
  const bodyHeight = (endHour - startHour) * HOUR_PX;
  const hours = Array.from({ length: endHour - startHour }, (_, i) => startHour + i);
  const template = `${GUTTER_PX}px repeat(${columns.length}, minmax(${COL_MIN_PX}px, 1fr))`;
  const minWidth = GUTTER_PX + columns.length * COL_MIN_PX;

  const nowMin = now.getHours() * 60 + now.getMinutes();
  const showNow = columns.some((c) => c.today) && nowMin >= startMin && nowMin <= endMin;
  const nowTop = (nowMin - startMin) * PX_PER_MIN;

  return (
    <div className="max-h-[680px] overflow-auto rounded-xl border border-border bg-card">
      <div style={{ minWidth }}>
        {/* Column headers stay put while the body scrolls. */}
        <div className="sticky top-0 z-30 grid border-b border-border bg-card" style={{ gridTemplateColumns: template }}>
          <div className="flex items-center px-3 text-xs font-medium text-muted-foreground">Time</div>
          {columns.map((c) => (
            <div key={c.key} className="border-l border-border/60 px-3 py-2.5">
              {c.header}
            </div>
          ))}
        </div>

        <div className="relative grid" style={{ gridTemplateColumns: template, height: bodyHeight }}>
          {/* Time gutter */}
          <div className="relative">
            {hours.map((h, i) => (
              <span
                key={h}
                className="absolute right-2 -translate-y-1/2 text-[11px] tabular-nums text-muted-foreground"
                style={{ top: i * HOUR_PX + (i === 0 ? 8 : 0) }}
              >
                {hourLabel(h)}
              </span>
            ))}
          </div>

          {columns.map((col) => {
            const { blocks: positioned, overflow } = layoutWithOverflow(col.events, col.day, {
              startMin,
              endMin,
              pxPerMin: PX_PER_MIN,
              minHeightPx: MIN_BLOCK_PX,
              maxLanes,
              courtOrder,
            });
            const shaded = col.open ? closedSpans(col.open, startMin, endMin) : [];
            return (
              <div
                key={col.key}
                role={onEmptyClick ? "button" : undefined}
                tabIndex={-1}
                aria-label={onEmptyClick ? "Empty time — click to book" : undefined}
                onClick={(e) => {
                  if (!onEmptyClick) return;
                  const rect = e.currentTarget.getBoundingClientRect();
                  onEmptyClick(col, startMin + (e.clientY - rect.top) / PX_PER_MIN);
                }}
                className={cn("relative border-l border-border/60", onEmptyClick && "cursor-pointer", col.today && "bg-primary/[0.03]")}
                style={{
                  backgroundImage: "linear-gradient(to bottom, hsl(var(--border) / 0.7) 1px, transparent 1px)",
                  backgroundSize: `100% ${HOUR_PX}px`,
                }}
              >
                {shaded.map((s) => (
                  <div
                    key={s.startMin}
                    aria-hidden
                    className="pointer-events-none absolute inset-x-0 bg-muted/70"
                    style={{ top: (s.startMin - startMin) * PX_PER_MIN, height: (s.endMin - s.startMin) * PX_PER_MIN }}
                  />
                ))}

                {positioned.map(({ event, top, height, lane, lanes }) => (
                  <button
                    key={event.id}
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation();
                      onEventClick(event);
                    }}
                    title={`${event.title} · ${formatRange(event.start, event.end)}`}
                    className={cn(
                      "absolute overflow-hidden rounded-md border-l-[3px] px-1.5 py-1 text-left text-[11px] leading-tight shadow-sm transition-shadow hover:z-10 hover:shadow-md",
                      EVENT_BLOCK_STYLE[event.kind],
                    )}
                    style={{
                      top: top + 1,
                      height: height - 2,
                      left: `calc(${(lane / lanes) * 100}% + 2px)`,
                      width: `calc(${100 / lanes}% - 4px)`,
                    }}
                  >
                    <p className="truncate font-semibold">{event.title}</p>
                    {height >= 44 && (
                      <p className="truncate opacity-80">
                        {courtName ? courtName(event.courtId) : event.subtitle}
                      </p>
                    )}
                    {height >= 58 && <p className="truncate opacity-80">{formatRange(event.start, event.end)}</p>}
                  </button>
                ))}

                {overflow.map((o) => (
                  <button
                    key={o.key}
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation();
                      onOverflowClick?.(col);
                    }}
                    title="Open this day to see every booking"
                    className="absolute right-1 z-10 h-[18px] rounded-full border border-border bg-card px-2 text-[10px] font-semibold text-primary shadow-sm hover:bg-accent"
                    style={{ top: Math.max(o.bottom - 20, o.top) }}
                  >
                    +{o.count} more
                  </button>
                ))}
              </div>
            );
          })}

          {showNow && (
            <div
              aria-hidden
              className="pointer-events-none absolute inset-x-0 z-20 border-t border-dashed border-destructive"
              style={{ top: nowTop }}
            >
              <span className="absolute -top-2 left-1 rounded bg-destructive px-1 text-[10px] font-semibold text-white">
                {now.toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit", hour12: true })}
              </span>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
