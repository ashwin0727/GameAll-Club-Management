"use client";

import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import type { PeakHourRow } from "@/features/reports/types";

function formatHourLabel(h: number): string {
  const hour12 = h % 12 === 0 ? 12 : h % 12;
  return `${hour12} ${h < 12 ? "AM" : "PM"}`;
}

/**
 * Demand % by hour of day, from get_peak_hours (booked ÷ open per hour,
 * aggregated across courts in scope; closed hours are already excluded by
 * the RPC — they are not shown as zero demand, spec §15).
 */
export function PeakHoursChart({ rows }: { rows: PeakHourRow[] }) {
  if (rows.length === 0) {
    return <p className="py-8 text-center text-sm text-muted-foreground">No booking activity in this period.</p>;
  }

  return (
    <div className="h-64 w-full" role="img" aria-label="Peak booking hours">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={rows} margin={{ top: 12, right: 12, left: 4, bottom: 4 }}>
          <CartesianGrid strokeDasharray="3 3" vertical={false} className="stroke-border" />
          <XAxis
            dataKey="hour"
            tickFormatter={formatHourLabel}
            fontSize={11}
            tickLine={false}
            axisLine={false}
            tickMargin={10}
            className="fill-muted-foreground"
          />
          <YAxis
            domain={[0, 100]}
            tickFormatter={(v: number) => `${v}%`}
            fontSize={11}
            tickLine={false}
            axisLine={false}
            tickMargin={8}
            width={44}
            className="fill-muted-foreground"
          />
          <Tooltip
            cursor={{ fill: "var(--accent)" }}
            contentStyle={{
              borderRadius: 12,
              border: "1px solid var(--border)",
              background: "var(--popover)",
              color: "var(--popover-foreground)",
              fontSize: 12,
            }}
            formatter={(value: number, _name: string, entry: { payload?: PeakHourRow }) => {
              const p = entry.payload;
              return [
                `${value}%${p ? ` (${Math.round(p.bookedMinutes)}/${Math.round(p.openMinutes)} min)` : ""}`,
                "Demand",
              ];
            }}
            labelFormatter={(label: number) => formatHourLabel(label)}
          />
          <Bar dataKey="demandPct" fill="#5B6CFF" radius={[3, 3, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
