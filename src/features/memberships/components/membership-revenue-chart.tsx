"use client";

import { ArrowDown, ArrowUp } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { axisTicks } from "@/features/memberships/dashboard-stats";
import { useMembershipRevenue } from "@/features/memberships/hooks/use-memberships";
import { cn } from "@/lib/utils";
import { monthStartIso, revenueOverMonths, todayIso } from "@/features/memberships/revenue-window";

const LINE = "#00A86B";
/** Room on the left for the y-axis figures. */
const AXIS_GUTTER = "2.75rem";
/** How many dates to caption along the bottom. */
const X_LABELS = 5;

function inr(v: number): string {
  return `₹${v.toLocaleString("en-IN")}`;
}

/** Axis figures stay short: 400000 -> "400K". */
function compact(v: number): string {
  if (v === 0) return "0";
  if (Math.abs(v) >= 1_000_000) return `${+(v / 1_000_000).toFixed(1)}M`;
  if (Math.abs(v) >= 1_000) return `${Math.round(v / 1_000)}K`;
  return String(v);
}

function dayLabel(bucket: string): string {
  return new Date(bucket).toLocaleDateString("en-IN", { day: "numeric", month: "short" });
}

/**
 * "Membership Revenue": membership payments collected so far this month and how that compares
 * with the same window last month, over a line of this month's daily takings.
 *
 * The line is drawn in a 0–100 coordinate space stretched to the plot, so it always fills the
 * card; `vector-effect` keeps its width honest under that stretch, and the point markers are
 * laid out as elements rather than SVG circles so they stay round rather than being squashed
 * into ellipses.
 */
export function MembershipRevenueChart({ facilityId }: { facilityId: string }) {
  // Six months of daily takings: the last three are shown and totalled, the three before them are only what the
  // change is measured against. The headline figure and the line come from the same data, so they always agree.
  const now = new Date();
  const { data } = useMembershipRevenue(facilityId, "day", { from: monthStartIso(now, 5), to: todayIso(now) });
  const window3 = data ? revenueOverMonths(data, now, 3) : null;
  const points = window3?.current ?? [];
  const revenueInr = window3?.total;
  const revenueChangePct = window3?.changePct;

  const ticks = axisTicks(Math.max(0, ...points.map((p) => p.amountInr)), 4);
  const axisMax = ticks[ticks.length - 1] || 1;

  const coords = points.map((p, i) => ({
    x: points.length <= 1 ? 50 : (i / (points.length - 1)) * 100,
    y: 100 - (p.amountInr / axisMax) * 100,
  }));
  const line = coords.map((c, i) => `${i === 0 ? "M" : "L"} ${c.x.toFixed(2)} ${c.y.toFixed(2)}`).join(" ");
  const area = coords.length > 1 ? `${line} L 100 100 L 0 100 Z` : "";

  const labelIndexes = points.length
    ? Array.from({ length: Math.min(X_LABELS, points.length) }, (_, i) =>
        Math.round((i * (points.length - 1)) / Math.max(1, Math.min(X_LABELS, points.length) - 1)),
      )
    : [];

  const up = (revenueChangePct ?? 0) >= 0;
  const DeltaIcon = up ? ArrowUp : ArrowDown;

  return (
    <Card className="stat-enter space-y-4 rounded-xl p-5" style={{ "--stat-delay": "340ms" } as React.CSSProperties}>
      <div className="flex items-center justify-between gap-3">
        <h3 className="text-base font-bold text-black dark:text-foreground">Membership Revenue</h3>
        {/* The window is fixed — shown, not a control. */}
        <span className="shrink-0 text-xs font-medium text-muted-foreground">Last 3 Months</span>
      </div>

      {revenueInr === undefined ? (
        <Skeleton className="h-8 w-40" />
      ) : (
        <div className="flex flex-wrap items-center gap-2.5">
          <p className="text-[26px] font-bold leading-none tabular-nums text-black dark:text-foreground">{inr(revenueInr)}</p>
          {revenueChangePct != null && (
            <>
              <span
                className={cn(
                  "flex items-center gap-0.5 rounded-md px-1.5 py-0.5 text-xs font-semibold tabular-nums",
                  up ? "bg-success/15 text-success" : "bg-destructive/15 text-destructive",
                )}
              >
                <DeltaIcon className="h-3 w-3" aria-hidden />
                {Math.abs(Math.round(revenueChangePct))}%
              </span>
              <span className="text-xs text-muted-foreground">Vs previous 3 months</span>
            </>
          )}
        </div>
      )}

      {!data ? (
        <Skeleton className="h-44 w-full rounded-xl" />
      ) : points.length === 0 ? (
        <p className="py-14 text-center text-sm text-muted-foreground">No membership revenue received yet.</p>
      ) : (
        <div>
          <div className="relative h-40">
            {/* Gridlines, nudged down half a row so each line lands exactly on its tick. */}
            {ticks.map((t) => (
              <div key={t} className="absolute inset-x-0 flex translate-y-1/2 items-center" style={{ bottom: `${(t / axisMax) * 100}%` }}>
                <span className="shrink-0 pr-2 text-right text-[11px] tabular-nums text-muted-foreground" style={{ width: AXIS_GUTTER }}>
                  {compact(t)}
                </span>
                <span className="h-px flex-1 bg-border/70" />
              </div>
            ))}

            <div className="absolute inset-y-0 right-0" style={{ left: AXIS_GUTTER }}>
              <svg viewBox="0 0 100 100" preserveAspectRatio="none" className="absolute inset-0 h-full w-full">
                <defs>
                  <linearGradient id="membership-revenue-fill" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor={LINE} stopOpacity={0.22} />
                    <stop offset="100%" stopColor={LINE} stopOpacity={0} />
                  </linearGradient>
                </defs>
                {area && <path d={area} fill="url(#membership-revenue-fill)" stroke="none" />}
                {line && (
                  <path
                    d={line}
                    fill="none"
                    stroke={LINE}
                    strokeWidth={2}
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    vectorEffect="non-scaling-stroke"
                  />
                )}
              </svg>

              {points.length <= 31 && coords.map((c, i) => (
                <span
                  key={points[i]!.bucket}
                  aria-hidden
                  className="absolute h-2 w-2 -translate-x-1/2 -translate-y-1/2 rounded-full"
                  style={{ left: `${c.x}%`, top: `${c.y}%`, backgroundColor: LINE }}
                />
              ))}
            </div>
          </div>

          <div className="relative h-5" style={{ marginLeft: AXIS_GUTTER }}>
            {labelIndexes.map((idx, i) => (
              <span
                key={points[idx]!.bucket}
                className="absolute top-1 whitespace-nowrap text-[11px] text-muted-foreground"
                style={{
                  left: `${coords[idx]!.x}%`,
                  transform: i === 0 ? "none" : i === labelIndexes.length - 1 ? "translateX(-100%)" : "translateX(-50%)",
                }}
              >
                {dayLabel(points[idx]!.bucket)}
              </span>
            ))}
          </div>
        </div>
      )}
    </Card>
  );
}
