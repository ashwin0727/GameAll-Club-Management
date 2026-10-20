"use client";

import { useMemo, useState } from "react";
import { cn } from "@/lib/utils";
import type { HeatmapCell } from "../types";

const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const DAY_NAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const GREEN = "0, 208, 132";

function formatHourShort(h: number): string {
  const hour12 = h % 12 === 0 ? 12 : h % 12;
  return `${hour12}${h < 12 ? "a" : "p"}`;
}

function hourRange(h: number): string {
  const end = (h + 1) % 24;
  const a = h % 12 === 0 ? 12 : h % 12;
  const b = end % 12 === 0 ? 12 : end % 12;
  const as = h < 12 ? "AM" : "PM";
  const bs = end < 12 ? "AM" : "PM";
  return as === bs ? `${a} – ${b} ${bs}` : `${a} ${as} – ${b} ${bs}`;
}

const hoursOf = (minutes: number) => `${(minutes / 60).toFixed(1)} h`;

/**
 * Day-of-week × hour-of-day demand. Cells are shaded relative to the busiest slot, so even a quiet facility shows where
 * its demand sits; the busiest slot is ringed, empty cells stay empty, and the number is still printed in every busy
 * cell (and a title is set on all of them) so it never relies on colour alone. Hover or focus a cell and the readout
 * above the grid spells it out. Only hours that appear in `cells` become columns.
 */
export function Heatmap({ cells }: { cells: HeatmapCell[] }) {
  const [active, setActive] = useState<string | null>(null);

  const view = useMemo(() => {
    const hours = [...new Set(cells.map((c) => c.hour))].sort((a, b) => a - b);
    const byKey = new Map(cells.map((c) => [`${c.dow}-${c.hour}`, c]));
    const max = Math.max(0, ...cells.map((c) => c.demandPct));
    const peak = max > 0 ? cells.find((c) => c.demandPct === max) : undefined;
    return { hours, byKey, max, peak };
  }, [cells]);

  if (cells.length === 0) {
    return <p className="py-8 text-center text-sm text-muted-foreground">No demand data for this period.</p>;
  }

  const { hours, byKey, max, peak } = view;
  const shown = (active ? byKey.get(active) : undefined) ?? peak;
  const showingPeak = !active || shown === peak;

  return (
    <div className="space-y-4">
      {/* Readout: the cell under the pointer, or the busiest slot when nothing is hovered. */}
      <div className="flex min-h-[3.25rem] flex-wrap items-center justify-between gap-3 rounded-xl border border-border bg-muted/30 px-4 py-2.5" aria-live="polite">
        {shown ? (
          <>
            <div>
              <p className="text-xs font-medium text-muted-foreground">{showingPeak && !active ? "Busiest slot" : "Selected slot"}</p>
              <p className="text-sm font-semibold">
                {DAY_NAMES[shown.dow]}, {hourRange(shown.hour)}
              </p>
            </div>
            <div className="flex items-center gap-5 text-right">
              <div>
                <p className="text-xl font-bold leading-none tabular-nums">{Math.round(shown.demandPct)}%</p>
                <p className="text-[11px] text-muted-foreground">demand</p>
              </div>
              <div>
                <p className="text-sm font-semibold tabular-nums">
                  {hoursOf(shown.bookedMinutes)} <span className="font-normal text-muted-foreground">of {hoursOf(shown.openMinutes)}</span>
                </p>
                <p className="text-[11px] text-muted-foreground">booked of open</p>
              </div>
            </div>
          </>
        ) : (
          <p className="text-sm text-muted-foreground">No bookings in this period yet.</p>
        )}
      </div>

      <div className="overflow-x-auto">
        <table className="w-full min-w-[620px] table-fixed border-separate border-spacing-1 text-center text-[11px]">
          <caption className="sr-only">Booking demand by day of week and hour of day</caption>
          <thead>
            <tr>
              <th scope="col" className="w-10 p-1 text-left font-medium text-muted-foreground">
                <span className="sr-only">Day</span>
              </th>
              {hours.map((h) => (
                <th key={h} scope="col" className="p-1 font-medium text-muted-foreground">
                  {formatHourShort(h)}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {DAYS.map((day, dow) => (
              <tr key={day}>
                <th scope="row" className="p-1 pr-2 text-left text-xs font-medium text-muted-foreground">
                  {day}
                </th>
                {hours.map((h) => {
                  const key = `${dow}-${h}`;
                  const cell = byKey.get(key);
                  const pct = cell ? Math.round(cell.demandPct) : null;
                  const t = cell && max > 0 ? cell.demandPct / max : 0;
                  const busy = pct !== null && pct > 0;
                  const isPeak = peak !== undefined && cell === peak;
                  return (
                    <td
                      key={h}
                      tabIndex={cell ? 0 : -1}
                      onMouseEnter={() => cell && setActive(key)}
                      onMouseLeave={() => setActive((a) => (a === key ? null : a))}
                      onFocus={() => cell && setActive(key)}
                      onBlur={() => setActive((a) => (a === key ? null : a))}
                      className={cn(
                        "h-9 rounded-lg p-0 align-middle font-semibold tabular-nums outline-none transition-all duration-150",
                        cell && "cursor-default hover:z-10 hover:scale-110 hover:shadow-md focus-visible:ring-2 focus-visible:ring-ring",
                        isPeak && "ring-2 ring-success ring-offset-1 ring-offset-card",
                        active === key && "scale-110 shadow-md",
                      )}
                      style={{
                        // empty = a faint tile; busy = green that deepens with demand, relative to the busiest slot
                        backgroundColor: pct === null ? "transparent" : busy ? `rgba(${GREEN}, ${0.14 + t * 0.78})` : "hsl(var(--muted) / 0.55)",
                        color: busy ? (t > 0.55 ? "#04281B" : "hsl(var(--foreground))") : "transparent",
                        border: pct === null ? "1px dashed hsl(var(--border))" : undefined,
                      }}
                      title={
                        cell
                          ? `${day} ${String(h).padStart(2, "0")}:00 — ${pct}% demand (${Math.round(cell.bookedMinutes)}/${Math.round(cell.openMinutes)} min)`
                          : `${day} ${String(h).padStart(2, "0")}:00 — closed`
                      }
                    >
                      {/* a quiet cell is blank to the eye but still reads "0" to a screen reader */}
                      {pct !== null ? (busy ? pct : <span className="sr-only">0</span>) : <span className="sr-only">closed</span>}
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="flex flex-wrap items-center gap-3 text-[11px] text-muted-foreground">
        <span>Quiet</span>
        <span
          className="h-2 w-40 rounded-full"
          style={{ background: `linear-gradient(to right, rgba(${GREEN}, 0.14), rgba(${GREEN}, 0.92))` }}
          aria-hidden
        />
        <span>Busy</span>
        <span className="ml-2 inline-flex items-center gap-1.5">
          <span className="h-3 w-3 rounded ring-2 ring-success" aria-hidden /> busiest slot
        </span>
        <span className="inline-flex items-center gap-1.5">
          <span className="h-3 w-3 rounded border border-dashed border-border" aria-hidden /> closed
        </span>
      </div>
    </div>
  );
}
