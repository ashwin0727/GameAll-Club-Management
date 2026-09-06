"use client";

import type { HeatmapCell } from "../types";

const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function formatHourShort(h: number): string {
  const hour12 = h % 12 === 0 ? 12 : h % 12;
  return `${hour12}${h < 12 ? "a" : "p"}`;
}

/**
 * Day-of-week × hour-of-day demand grid (spec §16). Encoded three ways so it
 * never relies on colour: cell background opacity, the number printed in the
 * cell, and a descriptive `title`. Only hours that appear in `cells` are
 * shown as columns.
 */
export function Heatmap({ cells }: { cells: HeatmapCell[] }) {
  if (cells.length === 0) {
    return <p className="py-8 text-center text-sm text-muted-foreground">No demand data for this period.</p>;
  }

  const hours = [...new Set(cells.map((c) => c.hour))].sort((a, b) => a - b);
  const byKey = new Map(cells.map((c) => [`${c.dow}-${c.hour}`, c]));

  return (
    <div className="overflow-x-auto">
      <table className="border-separate border-spacing-1 text-center text-xs">
        <caption className="sr-only">Booking demand by day of week and hour of day</caption>
        <thead>
          <tr>
            <th scope="col" className="p-1 text-left font-medium text-muted-foreground">
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
              <th scope="row" className="p-1 pr-2 text-left font-medium text-muted-foreground">
                {day}
              </th>
              {hours.map((h) => {
                const cell = byKey.get(`${dow}-${h}`);
                const pct = cell ? Math.round(cell.demandPct) : null;
                return (
                  <td
                    key={h}
                    className="w-8 rounded p-1 tabular-nums"
                    style={{
                      backgroundColor:
                        pct === null ? "var(--muted)" : `rgba(0, 240, 138, ${0.08 + (pct / 100) * 0.8})`,
                      color: pct !== null && pct >= 55 ? "#07101F" : "var(--foreground)",
                    }}
                    title={
                      cell
                        ? `${day} ${String(h).padStart(2, "0")}:00 — ${pct}% demand (${Math.round(
                            cell.bookedMinutes,
                          )}/${Math.round(cell.openMinutes)} min)`
                        : `${day} ${String(h).padStart(2, "0")}:00 — closed`
                    }
                  >
                    {pct ?? "·"}
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
