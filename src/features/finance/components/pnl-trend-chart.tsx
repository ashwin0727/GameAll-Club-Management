"use client";

import { Bar, CartesianGrid, ComposedChart, Line, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { formatCurrency } from "@/features/pricing/money";
import type { PnlTrendPoint } from "@/features/finance/types";

function formatAxisDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", { day: "2-digit", month: "short" });
}

function formatAxisAmount(amountMinor: number): string {
  const rupees = amountMinor / 100;
  if (Math.abs(rupees) >= 10000000) return `₹${(rupees / 10000000).toFixed(1).replace(/\.0$/, "")}Cr`;
  if (Math.abs(rupees) >= 100000) return `₹${(rupees / 100000).toFixed(1).replace(/\.0$/, "")}L`;
  if (Math.abs(rupees) >= 1000) return `₹${Math.round(rupees / 1000)}K`;
  return `₹${Math.round(rupees)}`;
}

const LABELS: Record<string, string> = {
  revenueMinor: "Revenue",
  expenseMinor: "Expenses",
  netMinor: "Net",
};

/** Data source: get_pnl_trend, aggregated in the database. */
export function PnlTrendChart({ points }: { points: PnlTrendPoint[] }) {
  if (points.length === 0) {
    return <p className="py-8 text-center text-sm text-muted-foreground">Not enough financial data to chart this period.</p>;
  }

  // Keyed on the actual values so a filter change remounts the chart and
  // re-plays its entrance animation instead of silently re-plotting.
  const dataKey = points.map((p) => `${p.date}:${p.revenueMinor}:${p.expenseMinor}:${p.netMinor}`).join(",");

  return (
    <div key={dataKey} className="h-72 w-full" role="img" aria-label="Revenue versus expenses over time">
      <ResponsiveContainer width="100%" height="100%">
        <ComposedChart data={points} margin={{ top: 12, right: 12, left: 4, bottom: 4 }}>
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
            contentStyle={{
              borderRadius: 12,
              border: "1px solid var(--border)",
              background: "var(--popover)",
              color: "var(--popover-foreground)",
              fontSize: 12,
            }}
            formatter={(value: number, name: string) => [formatCurrency(value, "INR"), LABELS[name] ?? name]}
            labelFormatter={(label: string) => formatAxisDate(label)}
          />
          <Bar
            dataKey="revenueMinor"
            fill="#00D084"
            radius={[3, 3, 0, 0]}
            name="revenueMinor"
            isAnimationActive
            animationDuration={600}
            animationEasing="ease-out"
          />
          <Bar
            dataKey="expenseMinor"
            fill="#F59E0B"
            radius={[3, 3, 0, 0]}
            name="expenseMinor"
            isAnimationActive
            animationDuration={600}
            animationEasing="ease-out"
          />
          <Line
            type="monotone"
            dataKey="netMinor"
            stroke="#6366F1"
            strokeWidth={2}
            dot={false}
            name="netMinor"
            isAnimationActive
            animationDuration={700}
            animationEasing="ease-out"
          />
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  );
}
