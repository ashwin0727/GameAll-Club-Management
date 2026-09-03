"use client";

import { Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { formatCurrency } from "@/features/pricing/money";
import type { RevenueTrendPoint } from "@/features/finance/types";

function formatAxisDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", { day: "2-digit", month: "short" });
}

/**
 * Axis labels are compact — ₹80K, not ₹80,000. A full amount on every tick
 * eats a third of the plot width and adds nothing: the axis is for reading
 * shape, and the tooltip carries the exact figure.
 */
function formatAxisAmount(amountMinor: number): string {
  const rupees = amountMinor / 100;
  if (Math.abs(rupees) >= 10000000) return `₹${(rupees / 10000000).toFixed(1).replace(/\.0$/, "")}Cr`;
  if (Math.abs(rupees) >= 100000) return `₹${(rupees / 100000).toFixed(1).replace(/\.0$/, "")}L`;
  if (Math.abs(rupees) >= 1000) return `₹${Math.round(rupees / 1000)}K`;
  return `₹${Math.round(rupees)}`;
}

/**
 * The chart's only data source is get_revenue_trend, aggregated in the
 * database — never summed from a client-side transaction list.
 */
export function RevenueTrendChart({ points }: { points: RevenueTrendPoint[] }) {
  if (points.length === 0) {
    return <p className="py-8 text-center text-sm text-muted-foreground">No revenue data for this period.</p>;
  }

  return (
    <div className="h-72 w-full" role="img" aria-label="Revenue trend chart">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={points} margin={{ top: 12, right: 12, left: 4, bottom: 4 }}>
          <defs>
            <linearGradient id="financeGrossGradient" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#00D084" stopOpacity={0.45} />
              <stop offset="100%" stopColor="#00D084" stopOpacity={0.02} />
            </linearGradient>
          </defs>

          <CartesianGrid strokeDasharray="3 3" vertical={false} className="stroke-border" />

          <XAxis
            dataKey="date"
            tickFormatter={formatAxisDate}
            fontSize={11}
            tickLine={false}
            axisLine={false}
            tickMargin={10}
            className="fill-muted-foreground"
          />
          <YAxis
            tickFormatter={formatAxisAmount}
            fontSize={11}
            tickLine={false}
            axisLine={false}
            tickMargin={8}
            width={52}
            className="fill-muted-foreground"
          />

          <Tooltip
            cursor={{ stroke: "#00D084", strokeWidth: 1, strokeDasharray: "3 3" }}
            contentStyle={{
              borderRadius: 12,
              border: "1px solid var(--border)",
              background: "var(--popover)",
              color: "var(--popover-foreground)",
              fontSize: 12,
            }}
            formatter={(value: number) => [formatCurrency(value, "INR"), "Revenue"]}
            labelFormatter={(label: string) => formatAxisDate(label)}
          />

          <Area
            type="monotone"
            dataKey="grossMinor"
            stroke="#00D084"
            strokeWidth={2.5}
            fill="url(#financeGrossGradient)"
            name="grossMinor"
            // A dot per reading, so a flat stretch still shows where the
            // readings actually are rather than reading as one long segment.
            dot={{ r: 3, fill: "#00D084", strokeWidth: 0 }}
            activeDot={{ r: 5, fill: "#00D084", stroke: "var(--background)", strokeWidth: 2 }}
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
