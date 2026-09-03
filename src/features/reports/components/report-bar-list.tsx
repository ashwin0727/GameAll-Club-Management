"use client";

export interface ReportBar {
  label: string;
  value: number;
  color?: string;
  /** Shown in place of the formatted value (e.g. "₹50,000 (50%)"). */
  caption?: string;
}

/**
 * Labelled horizontal bars — the readable companion to a chart, and the
 * whole widget where a chart would be overkill (spec §7, §14, §42). Bar
 * length is relative to the largest value in the set.
 */
export function ReportBarList({ items, max }: { items: ReportBar[]; max?: number }) {
  const peak = Math.max(max ?? 0, ...items.map((i) => i.value), 1);
  return (
    <ul className="space-y-2.5">
      {items.map((item) => (
        <li key={item.label} className="space-y-1">
          <div className="flex items-baseline justify-between gap-3 text-sm">
            <span className="truncate">{item.label}</span>
            <span className="shrink-0 font-medium tabular-nums">
              {item.caption ?? item.value.toLocaleString("en-IN")}
            </span>
          </div>
          <div className="h-2 overflow-hidden rounded-full bg-muted">
            <div
              data-bar
              className="h-full rounded-full"
              style={{
                width: `${Math.round((item.value / peak) * 100)}%`,
                backgroundColor: item.color ?? "var(--primary)",
              }}
            />
          </div>
        </li>
      ))}
    </ul>
  );
}
