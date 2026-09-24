"use client";

import Link from "next/link";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import type { PlanDistributionSlice } from "@/features/memberships/dashboard-stats";

const COLORS: Record<string, string> = {
  Monthly: "bg-success",
  "3 Months": "bg-blue-500",
  "6 Months": "bg-warning",
  "1 Year": "bg-purple-500",
  Others: "bg-muted-foreground/50",
};

/** The same plan-distribution figures as the donut, as a bar-per-bucket list with a link to plans. */
export function PlanDistributionPanel({ distribution }: { distribution: PlanDistributionSlice[] | undefined }) {
  return (
    <Card className="stat-enter space-y-3 p-4 sm:p-5" style={{ "--stat-delay": "420ms" } as React.CSSProperties}>
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-semibold">Plan Distribution</h3>
        <Link href="/memberships/v1/plans" className="text-xs font-medium text-primary hover:underline">
          View Plans
        </Link>
      </div>
      {!distribution ? (
        <Skeleton className="h-40 w-full" />
      ) : (
        <div className="space-y-3">
          {distribution.map((d) => (
            <div key={d.bucket} className="space-y-1">
              <div className="flex items-center justify-between text-xs">
                <span className="text-muted-foreground">{d.bucket}</span>
                <span className="font-medium text-foreground">
                  {d.count} <span className="text-muted-foreground">({Math.round(d.percent)}%)</span>
                </span>
              </div>
              <div className="h-2 overflow-hidden rounded-full bg-secondary">
                <div
                  className={`bar-grow h-full rounded-full ${COLORS[d.bucket] ?? "bg-muted-foreground/50"}`}
                  style={{ width: `${Math.max(d.percent, d.count > 0 ? 2 : 0)}%` }}
                />
              </div>
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}
