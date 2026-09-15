import { cn } from "@/lib/utils";

// Deterministic (not random) so server and client render the same markup.
const BAR_HEIGHTS_PCT = [38, 62, 48, 78, 55, 88, 58, 72, 46, 82, 60, 92];

/**
 * Chart-shaped loading placeholder — a row of bars pulsing in a staggered
 * wave, rather than one flat pulsing rectangle. Shown wherever a Recharts
 * component (trend/bar charts in finance and reports) is still loading, so
 * the wait reads as "a chart is on its way" instead of a content-agnostic
 * gray block.
 */
export function ChartSkeleton({ className }: { className?: string }) {
  return (
    <div
      aria-hidden="true"
      className={cn(
        "flex w-full items-end gap-1.5 rounded-xl border border-border bg-card p-4",
        className,
      )}
    >
      {BAR_HEIGHTS_PCT.map((height, i) => (
        <div
          key={i}
          className="flex-1 animate-pulse rounded-t-sm bg-muted"
          style={{ height: `${height}%`, animationDelay: `${i * 70}ms` }}
        />
      ))}
    </div>
  );
}
