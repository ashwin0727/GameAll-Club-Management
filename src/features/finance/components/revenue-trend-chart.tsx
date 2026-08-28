"use client";

import { Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { formatCurrency } from "@/features/pricing/money";
import type { RevenueTrendPoint } from "@/features/finance/types";

function formatAxisDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", { day: "numeric", month: "short" });
}

/** The chart's ONLY data source is get_revenue_trend (backend-aggregated) — never computed from a client-side transaction list (spec §"Revenue Chart"). */
export function RevenueTrendChart({ points }: { points: RevenueTrendPoint[] }) {
  if (points.length === 0) {
    return <p className="py-8 text-center text-sm text-muted-foreground">No revenue data for this period.</p>;
  }

  return (
    <div className="h-64 w-full overflow-hidden" role="img" aria-label="Revenue trend chart">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={points} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
          <defs>
            <linearGradient id="financeGrossGradient" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor="hsl(var(--primary))" stopOpacity={0.35} />
              <stop offset="95%" stopColor="hsl(var(--primary))" stopOpacity={0.02} />
            </linearGradient>
          </defs>
          <CartesianGrid strokeDasharray="3 3" vertical={false} className="stroke-border" />
          <XAxis dataKey="date" tickFormatter={formatAxisDate} fontSize={11} tickLine={false} axisLine={false} className="fill-muted-foreground" />
          <YAxis tickFormatter={(v: number) => formatCurrency(v, "INR")} fontSize={11} tickLine={false} axisLine={false} width={70} className="fill-muted-foreground" />
          <Tooltip
            formatter={(value: number, name: string) => [formatCurrency(value, "INR"), name === "netMinor" ? "Net" : name === "refundMinor" ? "Refunds" : "Gross"]}
            labelFormatter={(label: string) => formatAxisDate(label)}
          />
          <Area type="monotone" dataKey="grossMinor" stroke="hsl(var(--primary))" fill="url(#financeGrossGradient)" strokeWidth={2} name="grossMinor" />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}