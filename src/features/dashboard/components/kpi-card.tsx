"use client";

import type { LucideIcon } from "lucide-react";
import { Card } from "@/components/ui/card";
import type { KpiValue } from "@/features/dashboard/types";
import { useCountUp } from "@/features/dashboard/use-count-up";
import { cn } from "@/lib/utils";

export function KpiCard({
  label,
  kpi,
  format,
  icon: Icon,
  accentColor,
  /** Position in the KPI row — staggers the entrance so the row reads left-to-right. */
  index = 0,
}: {
  label: string;
  kpi: KpiValue;
  format: (value: number) => string;
  icon?: LucideIcon;
  accentColor?: string;
  index?: number;
}) {
  const trendUp = kpi.changePercent !== null && kpi.changePercent > 0;
  const trendDown = kpi.changePercent !== null && kpi.changePercent < 0;
  const animated = useCountUp(kpi.value);

  return (
    <Card
      className={cn(
        "stat-enter space-y-1.5 p-4 transition-shadow sm:p-5",
        // A soft lift tinted with the tile's own accent, so each KPI reads
        // as its own colour rather than four identical white boxes.
        accentColor && "border-[var(--kpi-tint)] shadow-[0_6px_20px_-8px_var(--kpi-shadow)] hover:shadow-[0_10px_26px_-8px_var(--kpi-shadow-hover)]",
      )}
      style={
        {
          "--stat-delay": `${index * 70}ms`,
          ...(accentColor
            ? {
                "--kpi-tint": `${accentColor}3d`,
                "--kpi-shadow": `${accentColor}40`,
                "--kpi-shadow-hover": `${accentColor}66`,
              }
            : {}),
        } as React.CSSProperties
      }
    >
      <div className="flex items-start justify-between gap-2">
        <p className="text-xs font-medium text-muted-foreground">{label}</p>
        {Icon && (
          <span
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full"
            style={accentColor ? { backgroundColor: `${accentColor}1f`, color: accentColor } : undefined}
          >
            <Icon className="h-4 w-4" aria-hidden />
          </span>
        )}
      </div>
      {/* The animated value is decorative motion over the same number — the
          accessible name always carries the settled figure. */}
      <p className="text-2xl font-semibold tabular-nums text-foreground" aria-label={format(kpi.value)}>
        <span aria-hidden>{format(Math.round(animated))}</span>
      </p>
      {kpi.changePercent !== null && (
        <p
          className={cn(
            "text-xs font-medium",
            trendUp && "text-success",
            trendDown && "text-destructive",
            !trendUp && !trendDown && "text-muted-foreground",
          )}
        >
          {trendUp ? "↑" : trendDown ? "↓" : "→"} {Math.abs(Math.round(kpi.changePercent))}% vs previous period
        </p>
      )}
    </Card>
  );
}
