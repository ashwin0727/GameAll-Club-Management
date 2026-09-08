"use client";

import { TrendingDown, TrendingUp } from "lucide-react";

/** Percent change vs the preceding window of equal length, or null when there
 *  is no comparable prior figure. */
export function changePct(current: number, previous: number | null): number | null {
  if (previous === null || previous === 0) return null;
  return Math.round(((current - previous) / Math.abs(previous)) * 1000) / 10;
}

/**
 * "+12.4%" vs the previous period, coloured by what the move means for the
 * facility (for expenses / money owed a rise is bad — pass `invert`).
 */
export function KpiDelta({ pct, invert }: { pct: number | null; invert?: boolean }) {
  if (pct === null) return <span className="text-muted-foreground">vs last period</span>;
  const good = invert ? pct <= 0 : pct >= 0;
  const Icon = pct >= 0 ? TrendingUp : TrendingDown;
  return (
    <span
      className={`inline-flex items-center gap-0.5 font-medium ${good ? "text-success" : "text-destructive"}`}
    >
      <Icon className="h-3 w-3" aria-hidden />
      {pct > 0 ? "+" : ""}
      {pct}%
    </span>
  );
}
