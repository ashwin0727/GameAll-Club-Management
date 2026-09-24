"use client";

import { ChevronDown } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { axisTicks, type MonthTrendPoint } from "@/features/memberships/dashboard-stats";

const ACTIVE = "#00A86B";
const INACTIVE = "#D9DEE5";
/** Room on the left for the y-axis figures. */
const AXIS_GUTTER = "2rem";

/**
 * "Active vs Inactive Members" per month: one column per month, the inactive count stacked
 * beneath the active one, with round-number gridlines behind and the active figure called out
 * above each column. Approximated from membership start/end dates (see dashboard-stats.ts).
 */
export function ActiveInactiveBarChart({ points }: { points: MonthTrendPoint[] | undefined }) {
  const ticks = axisTicks(points ? Math.max(0, ...points.map((p) => p.active + p.inactive)) : 0);
  const axisMax = ticks[ticks.length - 1] || 1;

  return (
    <Card className="stat-enter space-y-4 rounded-xl p-5" style={{ "--stat-delay": "300ms" } as React.CSSProperties}>
      <div className="flex items-center justify-between gap-3">
        <h3 className="text-base font-bold text-black dark:text-foreground">Active vs Inactive Members</h3>
        {/* Display-only, to match the design — the chart always covers the last six months. */}
        <span className="flex h-9 shrink-0 items-center gap-2 rounded-lg border border-input bg-card px-3 text-xs font-medium text-foreground">
          Last 6 Months
          <ChevronDown className="h-3.5 w-3.5 text-muted-foreground" aria-hidden />
        </span>
      </div>

      <div className="flex items-center justify-end gap-4 text-xs text-muted-foreground">
        <span className="flex items-center gap-1.5">
          <span className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: ACTIVE }} aria-hidden />
          Active
        </span>
        <span className="flex items-center gap-1.5">
          <span className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: INACTIVE }} aria-hidden />
          Inactive
        </span>
      </div>

      {!points ? (
        <Skeleton className="h-48 w-full rounded-xl" />
      ) : (
        <div>
          <div className="relative h-48">
            {/* Gridlines, each labelled with its figure in the gutter. The row is nudged down by
                half its own height so the line lands exactly on its tick — without that, the zero
                line floats above the baseline and the bars appear to overshoot it. */}
            {ticks.map((t) => (
              <div
                key={t}
                className="absolute inset-x-0 flex translate-y-1/2 items-center"
                style={{ bottom: `${(t / axisMax) * 100}%` }}
              >
                <span className="shrink-0 pr-2 text-right text-[11px] tabular-nums text-muted-foreground" style={{ width: AXIS_GUTTER }}>
                  {t}
                </span>
                <span className="h-px flex-1 bg-border/70" />
              </div>
            ))}

            <div className="absolute inset-y-0 right-0 flex items-end" style={{ left: AXIS_GUTTER }}>
              {points.map((p) => {
                const stack = p.active + p.inactive;
                return (
                  <div key={p.label} className="flex h-full flex-1 flex-col items-center justify-end">
                    <span className="mb-1.5 text-xs font-semibold tabular-nums text-black dark:text-foreground">{p.active}</span>
                    <div
                      className="flex w-8 flex-col justify-end overflow-hidden rounded-t-[4px]"
                      style={{ height: `${(stack / axisMax) * 100}%` }}
                      title={`${p.label}: ${p.active} active, ${p.inactive} inactive`}
                    >
                      <div style={{ backgroundColor: ACTIVE, flexGrow: p.active }} />
                      <div style={{ backgroundColor: INACTIVE, flexGrow: p.inactive }} />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          <div className="flex" style={{ paddingLeft: AXIS_GUTTER }}>
            {points.map((p) => (
              <span key={p.label} className="flex-1 pt-2 text-center text-[11px] text-muted-foreground">
                {p.label}
              </span>
            ))}
          </div>
        </div>
      )}
    </Card>
  );
}
