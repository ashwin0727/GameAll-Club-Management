import { Card } from "@/components/ui/card";
import { groupOperatingDays } from "@/features/operating-hours/summary";
import type { OperatingDay } from "@/features/operating-hours/types";

export function ScheduleSummary({
  days,
  playingAreaCount,
  customizedCount,
}: {
  days: OperatingDay[];
  playingAreaCount: number;
  customizedCount: number;
}) {
  const groups = groupOperatingDays(days);

  return (
    <Card className="space-y-3 p-4 sm:p-5">
      <h3 className="text-sm font-semibold">Operating Hours</h3>
      <div className="space-y-1.5">
        {groups.map((group) => (
          <div key={group.label} className="flex flex-col text-sm sm:flex-row sm:items-baseline sm:gap-2">
            <span className="font-medium text-foreground">{group.label}</span>
            <span className="text-muted-foreground">{group.description}</span>
          </div>
        ))}
      </div>

      <div className="border-t border-border pt-3 text-sm">
        <p className="font-medium text-foreground">{playingAreaCount} Playing Areas</p>
        <p className="text-muted-foreground">
          {customizedCount === 0
            ? "All playing areas currently follow facility hours."
            : `${customizedCount} playing ${customizedCount === 1 ? "area has" : "areas have"} custom hours.`}
        </p>
      </div>
    </Card>
  );
}