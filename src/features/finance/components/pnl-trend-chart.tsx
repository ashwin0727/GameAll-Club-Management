"use client";

import { useId, useState } from "react";
import { Area, CartesianGrid, ComposedChart, Line, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis, type TooltipProps } from "recharts";
import { cn } from "@/lib/utils";
import { formatCurrency } from "@/features/pricing/money";
import type { PnlTrendPoint } from "@/features/finance/types";

const SERIES = [
  { key: "revenueMinor", label: "Revenue", color: "#00D084" },
  { key: "expenseMinor", label: "Expenses", color: "#FF4D67" },
  { key: "netMinor", label: "Net profit", color: "#6366F1" },
] as const;

type SeriesKey = (typeof SERIES)[number]["key"];

/** When every bucket starts on the 1st the chart is monthly, and "Oct 26" reads better than "01 Oct". */
function isMonthly(points: PnlTrendPoint[]): boolean {
  return points.length > 1 && points.every((p) => new Date(p.date).getDate() === 1);
}

function axisLabel(iso: string, monthly: boolean): string {
  return new Date(iso).toLocaleDateString("en-IN", monthly ? { month: "short", year: "2-digit" } : { day: "2-digit", month: "short" });
}

function formatAxisAmount(amountMinor: number): string {
  const rupees = amountMinor / 100;
  const sign = rupees < 0 ? "-" : "";
  const abs = Math.abs(rupees);
  if (abs >= 10000000) return `${sign}₹${(abs / 10000000).toFixed(1).replace(/\.0$/, "")}Cr`;
  if (abs >= 100000) return `${sign}₹${(abs / 100000).toFixed(1).replace(/\.0$/, "")}L`;
  if (abs >= 1000) return `${sign}₹${Math.round(abs / 1000)}K`;
  return `${sign}₹${Math.round(abs)}`;
}

/** The hover card: the day, then one row per series with its colour, name and exact amount. */
function ChartTooltip({ active, payload, label, monthly, hidden }: TooltipProps<number, string> & { monthly: boolean; hidden: Set<SeriesKey> }) {
  if (!active || !payload?.length || typeof label !== "string") return null;
  const values = new Map(payload.map((p) => [p.dataKey as SeriesKey, Number(p.value ?? 0)]));
  const heading = new Date(label).toLocaleDateString("en-IN", monthly ? { month: "long", year: "numeric" } : { weekday: "short", day: "numeric", month: "short", year: "numeric" });
  return (
    <div className="min-w-[180px] rounded-xl border border-border bg-popover/95 p-3 text-popover-foreground shadow-xl backdrop-blur">
      <p className="mb-2 text-xs font-semibold text-muted-foreground">{heading}</p>
      <ul className="space-y-1.5">
        {SERIES.filter((s) => !hidden.has(s.key)).map((s) => (
          <li key={s.key} className="flex items-center justify-between gap-6 text-xs">
            <span className="flex items-center gap-2 text-muted-foreground">
              <span className="h-2 w-2 rounded-full" style={{ backgroundColor: s.color }} aria-hidden />
              {s.label}
            </span>
            <span className={cn("font-semibold tabular-nums", s.key === "netMinor" && (values.get(s.key) ?? 0) < 0 && "text-destructive")}>
              {formatCurrency(values.get(s.key) ?? 0, "INR")}
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}

/**
 * Revenue, expenses and net profit over time — smooth gradient areas for the money in and out, a dashed line for what
 * is left, a crosshair with one card of exact figures on hover, and legend chips that switch a series on or off.
 * Data source: get_pnl_trend, aggregated in the database.
 */
export function PnlTrendChart({ points }: { points: PnlTrendPoint[] }) {
  const gradientId = useId().replace(/:/g, "");
  const [hidden, setHidden] = useState<Set<SeriesKey>>(new Set());

  if (points.length === 0) {
    return <p className="py-8 text-center text-sm text-muted-foreground">Not enough financial data to chart this period.</p>;
  }

  const monthly = isMonthly(points);
  const toggle = (key: SeriesKey) =>
    setHidden((current) => {
      const next = new Set(current);
      if (next.has(key)) next.delete(key);
      else if (next.size < SERIES.length - 1) next.add(key); // never hide the last series
      return next;
    });

  // Keyed on the values so a date change remounts the chart and re-plays its entrance animation.
  const dataKey = points.map((p) => `${p.date}:${p.revenueMinor}:${p.expenseMinor}:${p.netMinor}`).join(",");
  const sparse = points.length < 3;

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2" role="group" aria-label="Chart series">
        {SERIES.map((s) => {
          const off = hidden.has(s.key);
          return (
            <button
              key={s.key}
              type="button"
              aria-pressed={!off}
              onClick={() => toggle(s.key)}
              className={cn(
                "inline-flex items-center gap-2 rounded-full border px-3 py-1 text-xs font-medium transition-colors",
                off ? "border-border text-muted-foreground/60" : "border-border bg-muted/40 text-foreground hover:bg-muted",
              )}
            >
              <span className="h-2 w-2 rounded-full" style={{ backgroundColor: off ? "transparent" : s.color, boxShadow: `inset 0 0 0 1.5px ${s.color}` }} aria-hidden />
              {s.label}
            </button>
          );
        })}
      </div>

      <div key={dataKey} className="h-72 w-full" role="img" aria-label="Revenue, expenses and net profit over time">
        <ResponsiveContainer width="100%" height="100%">
          <ComposedChart data={points} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
            <defs>
              {SERIES.slice(0, 2).map((s) => (
                <linearGradient key={s.key} id={`${gradientId}-${s.key}`} x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor={s.color} stopOpacity={0.32} />
                  <stop offset="100%" stopColor={s.color} stopOpacity={0} />
                </linearGradient>
              ))}
            </defs>
            <CartesianGrid vertical={false} strokeDasharray="2 6" className="stroke-border/70" />
            <XAxis
              dataKey="date"
              tickFormatter={(v: string) => axisLabel(v, monthly)}
              fontSize={11}
              tickLine={false}
              axisLine={false}
              tickMargin={10}
              minTickGap={28}
              padding={{ left: 12, right: 12 }}
              className="fill-muted-foreground"
            />
            <YAxis tickFormatter={formatAxisAmount} fontSize={11} tickLine={false} axisLine={false} tickMargin={8} width={48} className="fill-muted-foreground" />
            <ReferenceLine y={0} className="stroke-border" strokeWidth={1} />
            <Tooltip
              cursor={{ stroke: "currentColor", strokeOpacity: 0.2, strokeWidth: 1, strokeDasharray: "4 4" }}
              content={<ChartTooltip monthly={monthly} hidden={hidden} />}
            />
            {SERIES.slice(0, 2).map((s) =>
              hidden.has(s.key) ? null : (
                <Area
                  key={s.key}
                  type="monotone"
                  dataKey={s.key}
                  stroke={s.color}
                  strokeWidth={2.5}
                  strokeLinecap="round"
                  fill={`url(#${gradientId}-${s.key})`}
                  dot={sparse ? { r: 4, strokeWidth: 2, fill: "hsl(var(--card))" } : false}
                  activeDot={{ r: 5, strokeWidth: 2, fill: "hsl(var(--card))", stroke: s.color }}
                  animationDuration={700}
                  animationEasing="ease-out"
                />
              ),
            )}
            {!hidden.has("netMinor") && (
              <Line
                type="monotone"
                dataKey="netMinor"
                stroke="#6366F1"
                strokeWidth={2}
                strokeDasharray="6 5"
                strokeLinecap="round"
                dot={sparse ? { r: 4, strokeWidth: 2, fill: "hsl(var(--card))" } : false}
                activeDot={{ r: 5, strokeWidth: 2, fill: "hsl(var(--card))", stroke: "#6366F1" }}
                animationDuration={800}
                animationEasing="ease-out"
              />
            )}
          </ComposedChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
