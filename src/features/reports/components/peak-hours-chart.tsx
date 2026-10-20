"use client";

import { useMemo } from "react";
import { Bar, BarChart, CartesianGrid, Cell, ResponsiveContainer, Tooltip, XAxis, YAxis, type TooltipProps } from "recharts";
import type { PeakHourRow } from "@/features/reports/types";

const BASE = "#5B6CFF";
const PEAK = "#00D084";

function hourLabel(h: number): string {
  const hour12 = h % 12 === 0 ? 12 : h % 12;
  return `${hour12} ${h < 12 ? "AM" : "PM"}`;
}

/** "6 – 7 PM" for the hover card. */
function hourRange(h: number): string {
  const end = (h + 1) % 24;
  const a = h % 12 === 0 ? 12 : h % 12;
  const b = end % 12 === 0 ? 12 : end % 12;
  const aSuffix = h < 12 ? "AM" : "PM";
  const bSuffix = end < 12 ? "AM" : "PM";
  return aSuffix === bSuffix ? `${a} – ${b} ${bSuffix}` : `${a} ${aSuffix} – ${b} ${bSuffix}`;
}

function hours(minutes: number): string {
  return `${(minutes / 60).toFixed(1)} h`;
}

/** The hover card: the hour, the demand, a small meter, and the booked-of-open time behind it. */
function HourTip({ active, payload, peakHour }: TooltipProps<number, string> & { peakHour: number }) {
  const row = payload?.[0]?.payload as PeakHourRow | undefined;
  if (!active || !row) return null;
  const isPeak = row.hour === peakHour && row.demandPct > 0;
  return (
    <div className="min-w-[190px] rounded-xl border border-border bg-popover/95 p-3 text-popover-foreground shadow-xl backdrop-blur">
      <div className="mb-2 flex items-center justify-between gap-3">
        <p className="text-xs font-semibold text-muted-foreground">{hourRange(row.hour)}</p>
        {isPeak && <span className="rounded-full bg-success/15 px-2 py-0.5 text-[10px] font-semibold text-success">Busiest hour</span>}
      </div>
      <p className="text-2xl font-bold leading-none tabular-nums">{row.demandPct}%</p>
      <p className="mt-0.5 text-[11px] text-muted-foreground">of the court time open in this hour was used</p>
      <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-muted">
        <div className="h-full rounded-full" style={{ width: `${Math.min(100, row.demandPct)}%`, backgroundColor: isPeak ? PEAK : BASE }} />
      </div>
      <p className="mt-2 text-xs tabular-nums text-muted-foreground">
        {hours(row.bookedMinutes)} booked of {hours(row.openMinutes)} open
      </p>
    </div>
  );
}

/**
 * Demand by hour of day (from get_peak_hours: used ÷ open per hour, across the courts in view; closed hours are not
 * drawn as zero). Rounded bars shaded by how busy the hour is, the busiest hour picked out in green, and a hover card with
 * the hour, the demand and the time behind it — nothing is hidden behind the bar you point at.
 */
export function PeakHoursChart({ rows }: { rows: PeakHourRow[] }) {
  const stats = useMemo(() => {
    const max = Math.max(0, ...rows.map((r) => r.demandPct));
    const peak = rows.find((r) => r.demandPct === max && max > 0);
    const quiet = [...rows].filter((r) => r.openMinutes > 0).sort((a, b) => a.demandPct - b.demandPct)[0];
    // A tidy top for the axis (a multiple of 20), so a quiet facility still reads clearly instead of hugging the floor, and
    // four equal steps up to it — 0, 5, 10, 15, 20 / 0, 10, 20, 30, 40 — so the labels are evenly spaced and round.
    const top = Math.min(100, Math.max(20, Math.ceil((max * 1.15) / 20) * 20));
    const ticks = [0, top / 4, top / 2, (top * 3) / 4, top];
    return { max, peak, quiet, top, ticks };
  }, [rows]);

  if (rows.length === 0) {
    return <p className="py-8 text-center text-sm text-muted-foreground">No booking activity in this period.</p>;
  }

  // Keyed on the values so a filter change remounts the chart and re-plays its entrance animation.
  const dataKey = rows.map((r) => `${r.hour}:${r.demandPct}`).join(",");

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2 text-xs">
        {stats.peak && (
          <span className="inline-flex items-center gap-1.5 rounded-full border border-border bg-muted/40 px-3 py-1 font-medium">
            <span className="h-2 w-2 rounded-full" style={{ backgroundColor: PEAK }} aria-hidden />
            Busiest: {hourLabel(stats.peak.hour)} · {stats.peak.demandPct}%
          </span>
        )}
        {stats.quiet && stats.peak && stats.quiet.hour !== stats.peak.hour && (
          <span className="inline-flex items-center gap-1.5 rounded-full border border-border bg-muted/40 px-3 py-1 font-medium text-muted-foreground">
            <span className="h-2 w-2 rounded-full" style={{ backgroundColor: BASE, opacity: 0.4 }} aria-hidden />
            Quietest: {hourLabel(stats.quiet.hour)} · {stats.quiet.demandPct}%
          </span>
        )}
      </div>

      <div key={dataKey} className="h-64 w-full" role="img" aria-label="Peak Booking Hours">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={rows} margin={{ top: 8, right: 8, left: 0, bottom: 0 }} barCategoryGap="22%">
            <CartesianGrid vertical={false} strokeDasharray="2 6" className="stroke-border/70" />
            <XAxis dataKey="hour" tickFormatter={hourLabel} fontSize={11} tickLine={false} axisLine={false} tickMargin={10} minTickGap={8} className="fill-muted-foreground" />
            <YAxis
              domain={[0, stats.top]}
              ticks={stats.ticks}
              interval={0}
              tickFormatter={(v: number) => `${v}%`}
              allowDecimals={false}
              fontSize={11}
              tickLine={false}
              axisLine={false}
              tickMargin={8}
              width={44}
              className="fill-muted-foreground"
            />
            {/* The band behind the hovered hour is a soft tint BEHIND the bar — never an opaque block over it. */}
            <Tooltip
              cursor={{ fill: "hsl(var(--muted))", fillOpacity: 0.55, radius: 10 }}
              content={<HourTip peakHour={stats.peak?.hour ?? -1} />}
              wrapperStyle={{ outline: "none", zIndex: 20 }}
            />
            <Bar dataKey="demandPct" radius={[8, 8, 3, 3]} maxBarSize={44} animationDuration={700} animationEasing="ease-out">
              {rows.map((r) => {
                const isPeak = stats.peak?.hour === r.hour;
                // Busier hours are more opaque; a quiet hour is a pale bar, not a missing one.
                const opacity = stats.max > 0 ? 0.35 + 0.65 * (r.demandPct / stats.max) : 0.5;
                return <Cell key={r.hour} fill={isPeak ? PEAK : BASE} fillOpacity={isPeak ? 1 : opacity} />;
              })}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
