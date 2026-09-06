"use client";

import { Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import type { BookingTrendPoint } from "@/features/reports/types";

function formatAxisDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", { day: "2-digit", month: "short" });
}

/**
 * Booking volume over time. Data comes only from get_booking_trend,
 * zero-filled and bucketed in the database — never counted from a list here.
 */
export function BookingTrendChart({ points }: { points: BookingTrendPoint[] }) {
  if (points.length === 0) {
    return <p className="py-8 text-center text-sm text-muted-foreground">No bookings in this period.</p>;
  }

  return (
    <div className="h-72 w-full" role="img" aria-label="Booking volume trend">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={points} margin={{ top: 12, right: 12, left: 4, bottom: 4 }}>
          <defs>
            <linearGradient id="bookingTotalGradient" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#00F08A" stopOpacity={0.4} />
              <stop offset="100%" stopColor="#00F08A" stopOpacity={0.02} />
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
            allowDecimals={false}
            fontSize={11}
            tickLine={false}
            axisLine={false}
            tickMargin={8}
            width={36}
            className="fill-muted-foreground"
          />

          <Tooltip
            cursor={{ stroke: "#00F08A", strokeWidth: 1, strokeDasharray: "3 3" }}
            contentStyle={{
              borderRadius: 12,
              border: "1px solid var(--border)",
              background: "var(--popover)",
              color: "var(--popover-foreground)",
              fontSize: 12,
            }}
            formatter={(value: number, name: string) => [
              value,
              name === "total" ? "Bookings" : "Cancelled",
            ]}
            labelFormatter={(label: string) => formatAxisDate(label)}
          />

          <Area
            type="monotone"
            dataKey="total"
            stroke="#00F08A"
            strokeWidth={2.5}
            fill="url(#bookingTotalGradient)"
            name="total"
            dot={{ r: 3, fill: "#00F08A", strokeWidth: 0 }}
            activeDot={{ r: 5, fill: "#00F08A", stroke: "var(--background)", strokeWidth: 2 }}
          />
          <Area
            type="monotone"
            dataKey="cancelled"
            stroke="#FF4D67"
            strokeWidth={1.5}
            fill="none"
            name="cancelled"
            dot={false}
            activeDot={{ r: 4, fill: "#FF4D67", stroke: "var(--background)", strokeWidth: 2 }}
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
