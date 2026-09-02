"use client";

import { Card } from "@/components/ui/card";
import { useCountUp } from "@/features/dashboard/use-count-up";
import { cn } from "@/lib/utils";

/**
 * The one KPI tile every dashboard-style page uses (Dashboard, Memberships,
 * Membership Sessions, Guest Bookings).
 *
 * On landing it fades/rises in — staggered by [index] so a row resolves
 * left-to-right — and counts its figure up from 0 when given [countTo] +
 * [format]. Both motions are skipped under reduced motion.
 *
 * The [accent] is confined to the icon chip. The card's own border and
 * shadow stay neutral so no colour bleeds along the left and right edges.
 */
export function StatCard({
  icon: Icon,
  label,
  value,
  hint,
  hintClass,
  accent,
  countTo,
  format,
  index = 0,
  className,
}: {
  icon?: React.ComponentType<{ className?: string }>;
  label: string;
  /** The settled, formatted figure. Always the accessible name. */
  value: string;
  hint?: React.ReactNode;
  hintClass?: string;
  accent: string;
  /** Numeric target for the count-up; needs [format]. Without both, [value] renders as-is. */
  countTo?: number;
  format?: (v: number) => string;
  /** Position in the row — staggers the entrance. */
  index?: number;
  className?: string;
}) {
  const animated = useCountUp(countTo ?? 0);
  const animating = countTo !== undefined && format !== undefined;

  return (
    <Card
      className={cn("stat-enter p-3 shadow-sm transition-shadow hover:shadow-md", className)}
      style={{ "--stat-delay": `${index * 70}ms` } as React.CSSProperties}
    >
      <div className="flex items-start justify-between gap-2">
        <p className="truncate text-[11px] font-medium text-muted-foreground">{label}</p>
        {Icon && (
          <span
            className="flex h-6 w-6 shrink-0 items-center justify-center rounded-md"
            style={{ backgroundColor: `${accent}1f`, color: accent }}
          >
            <Icon className="h-3.5 w-3.5" aria-hidden />
          </span>
        )}
      </div>
      {/* Figure and delta share a baseline, as in the design. The animated
          number is decorative motion over the same value — the accessible
          name always carries the settled one. */}
      <div className="mt-1.5 flex flex-wrap items-baseline gap-x-1.5 gap-y-0.5">
        <p className="text-xl font-semibold leading-none tabular-nums text-foreground" aria-label={value}>
          <span aria-hidden>{animating ? format(Math.round(animated)) : value}</span>
        </p>
        {hint && <div className={cn("text-[11px] leading-none", hintClass ?? "text-muted-foreground")}>{hint}</div>}
      </div>
    </Card>
  );
}
