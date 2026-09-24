"use client";

import { ChevronDown } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import type { PlanDistributionSlice } from "@/features/memberships/dashboard-stats";

const COLORS: Record<string, string> = {
  Monthly: "#00B96B",
  "3 Months": "#3B82F6",
  "6 Months": "#F5A524",
  "1 Year": "#A855F7",
  Others: "#9CA3AF",
};

const RADIUS = 58;
const STROKE = 24;
const CIRCUMFERENCE = 2 * Math.PI * RADIUS;

/**
 * "Membership Overview": current memberships split by billed period, as a donut with the total
 * in the middle and a legend listing each band's count and share.
 */
export function MembershipOverviewDonut({
  distribution,
  total,
}: {
  distribution: PlanDistributionSlice[] | undefined;
  total: number | undefined;
}) {
  let offset = 0;

  return (
    <Card className="stat-enter space-y-5 rounded-xl p-5" style={{ "--stat-delay": "260ms" } as React.CSSProperties}>
      <div className="flex items-center justify-between gap-3">
        <h3 className="text-base font-bold text-black dark:text-foreground">Membership Overview</h3>
        {/* Display-only, to match the design — the split always reflects current memberships. */}
        <span className="flex h-9 shrink-0 items-center gap-2 rounded-lg border border-input bg-card px-3 text-xs font-medium text-foreground">
          This Month
          <ChevronDown className="h-3.5 w-3.5 text-muted-foreground" aria-hidden />
        </span>
      </div>

      {!distribution ? (
        <Skeleton className="h-44 w-full rounded-xl" />
      ) : (
        <div className="flex flex-col items-center gap-6 sm:flex-row">
          <div className="relative h-[160px] w-[160px] shrink-0">
            <svg viewBox="0 0 140 140" className="h-full w-full -rotate-90">
              <circle cx="70" cy="70" r={RADIUS} fill="none" stroke="currentColor" strokeWidth={STROKE} className="text-muted/40" />
              {distribution
                .filter((d) => d.count > 0)
                .map((d) => {
                  const arc = (d.percent / 100) * CIRCUMFERENCE;
                  const dash = `${arc} ${CIRCUMFERENCE - arc}`;
                  const dashOffset = -offset;
                  offset += arc;
                  return (
                    <circle
                      key={d.bucket}
                      cx="70"
                      cy="70"
                      r={RADIUS}
                      fill="none"
                      stroke={COLORS[d.bucket] ?? COLORS.Others}
                      strokeWidth={STROKE}
                      strokeDasharray={dash}
                      strokeDashoffset={dashOffset}
                    />
                  );
                })}
            </svg>
            <div className="absolute inset-0 flex flex-col items-center justify-center">
              <p className="text-[28px] font-bold leading-none tabular-nums text-black dark:text-foreground">{total ?? 0}</p>
              <p className="mt-1 text-xs text-muted-foreground">Members</p>
            </div>
          </div>

          <ul className="w-full min-w-0 flex-1 space-y-3">
            {distribution.map((d) => (
              <li key={d.bucket} className="flex items-center gap-3 text-sm">
                <span className="h-3 w-3 shrink-0 rounded-full" style={{ backgroundColor: COLORS[d.bucket] }} aria-hidden />
                <span className="min-w-0 flex-1 truncate text-foreground">{d.bucket}</span>
                <span className="shrink-0 font-semibold tabular-nums text-foreground">{d.count}</span>
                <span className="w-12 shrink-0 text-right tabular-nums text-muted-foreground">({Math.round(d.percent)}%)</span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </Card>
  );
}
