"use client";

import { useState } from "react";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { useMembershipRevenue } from "@/features/memberships/hooks/use-memberships";
import type { RevenueGranularity } from "@/features/memberships/types";

const GRANULARITIES: { value: RevenueGranularity; label: string }[] = [
  { value: "day", label: "Day" },
  { value: "month", label: "Month" },
  { value: "year", label: "Year" },
];

function inr(v: number): string {
  return `₹${v.toLocaleString("en-IN")}`;
}

function label(bucket: string, grain: RevenueGranularity): string {
  const d = new Date(bucket);
  if (grain === "year") return String(d.getFullYear());
  if (grain === "month") return d.toLocaleDateString("en-IN", { month: "short", year: "numeric" });
  return d.toLocaleDateString("en-IN", { day: "2-digit", month: "short" });
}

export function MembershipRevenueTrend({ facilityId }: { facilityId: string }) {
  const [grain, setGrain] = useState<RevenueGranularity>("month");
  const { data, isLoading } = useMembershipRevenue(facilityId, grain);

  const points = data ?? [];
  const max = points.reduce((m, p) => Math.max(m, p.amountInr), 0) || 1;
  const total = points.reduce((s, p) => s + p.amountInr, 0);

  return (
    <Card className="stat-enter space-y-3 p-4 sm:p-5" style={{ "--stat-delay": "360ms" } as React.CSSProperties}>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h3 className="text-sm font-semibold">Membership Revenue Received</h3>
          <p className="text-xs text-muted-foreground">{inr(total)} across the shown period</p>
        </div>
        <div className="flex gap-1">
          {GRANULARITIES.map((g) => (
            <button
              key={g.value}
              type="button"
              onClick={() => setGrain(g.value)}
              className={cn(
                "rounded-full border px-3 py-1 text-xs font-medium",
                grain === g.value
                  ? "border-primary bg-primary text-primary-foreground"
                  : "border-input bg-secondary/40 text-muted-foreground hover:bg-secondary",
              )}
            >
              {g.label}
            </button>
          ))}
        </div>
      </div>

      {isLoading ? (
        <Skeleton className="h-40 w-full" />
      ) : points.length === 0 ? (
        <p className="py-6 text-center text-sm text-muted-foreground">No membership revenue received yet.</p>
      ) : (
        <div className="space-y-1.5">
          {points.map((p, i) => (
            <div key={p.bucket} className="flex items-center gap-2 text-xs">
              <span className="w-20 shrink-0 text-muted-foreground">{label(p.bucket, grain)}</span>
              <div className="h-4 flex-1 overflow-hidden rounded bg-secondary">
                <div
                  className="bar-grow h-full rounded bg-primary"
                  style={
                    {
                      width: `${Math.max((p.amountInr / max) * 100, 2)}%`,
                      "--bar-delay": `${120 + i * 60}ms`,
                    } as React.CSSProperties
                  }
                />
              </div>
              <span className="w-20 shrink-0 text-right font-medium text-foreground">{inr(p.amountInr)}</span>
              <span className="w-10 shrink-0 text-right text-muted-foreground">{p.paymentCount}×</span>
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}