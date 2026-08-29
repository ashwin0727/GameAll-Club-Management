import type { LucideIcon } from "lucide-react";
import { Card } from "@/components/ui/card";
import type { KpiValue } from "@/features/dashboard/types";
import { cn } from "@/lib/utils";

export function KpiCard({
  label,
  kpi,
  format,
  icon: Icon,
  accentColor,
}: {
  label: string;
  kpi: KpiValue;
  format: (value: number) => string;
  icon?: LucideIcon;
  accentColor?: string;
}) {
  const trendUp = kpi.changePercent !== null && kpi.changePercent > 0;
  const trendDown = kpi.changePercent !== null && kpi.changePercent < 0;

  return (
    <Card className="space-y-1.5 p-4 sm:p-5">
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
      <p className="text-2xl font-semibold text-foreground">{format(kpi.value)}</p>
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