import { Card } from "@/components/ui/card";
import type { KpiValue } from "@/features/dashboard/types";
import { cn } from "@/lib/utils";

export function KpiCard({
  label,
  kpi,
  format,
}: {
  label: string;
  kpi: KpiValue;
  format: (value: number) => string;
}) {
  const trendUp = kpi.changePercent !== null && kpi.changePercent > 0;
  const trendDown = kpi.changePercent !== null && kpi.changePercent < 0;

  return (
    <Card className="space-y-1.5 p-4 sm:p-5">
      <p className="text-xs font-medium text-muted-foreground">{label}</p>
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