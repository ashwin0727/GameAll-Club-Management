"use client";

import { useId } from "react";
import { Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis, type TooltipProps } from "recharts";
import { formatCurrency } from "@/features/pricing/money";
import type { MetricKind } from "@/features/reports/overview-metrics";
import type { OverviewTrendPoint } from "@/features/reports/types";

function isMonthly(points: OverviewTrendPoint[]): boolean {
  return points.length > 1 && points.every((p) => new Date(p.date).getDate() === 1);
}

function axisLabel(iso: string, monthly: boolean): string {
  return new Date(iso).toLocaleDateString("en-IN", monthly ? { month: "short", year: "2-digit" } : { day: "2-digit", month: "short" });
}

function compactMoney(minor: number): string {
  const rupees = minor / 100;
  const sign = rupees < 0 ? "-" : "";
  const abs = Math.abs(rupees);
  if (abs >= 10000000) return `${sign}₹${(abs / 10000000).toFixed(1).replace(/\.0$/, "")}Cr`;
  if (abs >= 100000) return `${sign}₹${(abs / 100000).toFixed(1).replace(/\.0$/, "")}L`;
  if (abs >= 1000) return `${sign}₹${Math.round(abs / 1000)}K`;
  return `${sign}₹${Math.round(abs)}`;
}

function Tip({ active, payload, label, monthly, kind, name }: TooltipProps<number, string> & { monthly: boolean; kind: MetricKind; name: string }) {
  if (!active || !payload?.length || typeof label !== "string") return null;
  const value = Number(payload[0]?.value ?? 0);
  const heading = new Date(label).toLocaleDateString("en-IN", monthly ? { month: "long", year: "numeric" } : { weekday: "short", day: "numeric", month: "short", year: "numeric" });
  return (
    <div className="min-w-[170px] rounded-xl border border-border bg-popover/95 p-3 text-popover-foreground shadow-xl backdrop-blur">
      <p className="mb-1.5 text-xs font-semibold text-muted-foreground">{heading}</p>
      <div className="flex items-center justify-between gap-6 text-xs">
        <span className="flex items-center gap-2 text-muted-foreground">
          <span className="h-2 w-2 rounded-full" style={{ backgroundColor: payload[0]?.color }} aria-hidden />
          {name}
        </span>
        <span className="font-semibold tabular-nums">{kind === "money" ? formatCurrency(value, "INR") : value.toLocaleString("en-IN")}</span>
      </div>
    </div>
  );
}

/** One figure over time: a smooth gradient area with a crosshair and a card of the exact value on hover. */
export function MetricTrendChart({
  points,
  kind,
  color,
  name,
}: {
  points: OverviewTrendPoint[];
  kind: MetricKind;
  color: string;
  /** The series name shown in the hover card. */
  name: string;
}) {
  const gradientId = useId().replace(/:/g, "");
  if (points.length === 0) {
    return <p className="py-8 text-center text-sm text-muted-foreground">Nothing to chart for these dates.</p>;
  }
  const monthly = isMonthly(points);
  const sparse = points.length < 3;
  // Re-mount on new data so the entrance animation replays when a different card is chosen.
  const dataKey = `${name}:` + points.map((p) => `${p.date}:${p.value}`).join(",");

  return (
    <div key={dataKey} className="h-72 w-full" role="img" aria-label={`${name} over time`}>
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={points} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
          <defs>
            <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={color} stopOpacity={0.32} />
              <stop offset="100%" stopColor={color} stopOpacity={0} />
            </linearGradient>
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
          <YAxis
            tickFormatter={(v: number) => (kind === "money" ? compactMoney(v) : String(Math.round(v)))}
            allowDecimals={false}
            fontSize={11}
            tickLine={false}
            axisLine={false}
            tickMargin={8}
            width={48}
            className="fill-muted-foreground"
          />
          <Tooltip cursor={{ stroke: "currentColor", strokeOpacity: 0.2, strokeWidth: 1, strokeDasharray: "4 4" }} content={<Tip monthly={monthly} kind={kind} name={name} />} />
          <Area
            type="monotone"
            dataKey="value"
            stroke={color}
            strokeWidth={2.5}
            strokeLinecap="round"
            fill={`url(#${gradientId})`}
            dot={sparse ? { r: 4, strokeWidth: 2, fill: "hsl(var(--card))" } : false}
            activeDot={{ r: 5, strokeWidth: 2, fill: "hsl(var(--card))", stroke: color }}
            animationDuration={700}
            animationEasing="ease-out"
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
