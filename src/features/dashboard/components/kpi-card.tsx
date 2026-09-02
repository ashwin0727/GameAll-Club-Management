"use client";

import type { LucideIcon } from "lucide-react";
import { StatCard } from "@/components/shared/stat-card";
import type { KpiValue } from "@/features/dashboard/types";
import { cn } from "@/lib/utils";

/** Dashboard KPI tile — a [StatCard] fed from a [KpiValue] with its trend line. */
export function KpiCard({
  label,
  kpi,
  format,
  icon,
  accentColor,
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

  return (
    <StatCard
      icon={icon}
      label={label}
      value={format(kpi.value)}
      countTo={kpi.value}
      format={format}
      accent={accentColor ?? "#00D084"}
      index={index}
      hint={
        kpi.changePercent === null
          ? undefined
          : `${trendUp ? "↑" : trendDown ? "↓" : "→"} ${Math.abs(Math.round(kpi.changePercent))}% vs previous period`
      }
      hintClass={cn("font-medium", trendUp && "text-success", trendDown && "text-destructive")}
    />
  );
}
