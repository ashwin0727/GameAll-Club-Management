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
 * [format]. It also carries a soft shadow and border tinted with its own
 * [accent], so a row of tiles reads as distinct cards rather than identical
 * white boxes. Both motions are skipped under reduced motion.
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
      className={cn(
        "stat-enter p-4 transition-shadow",
        "border-[var(--kpi-tint)] shadow-[0_6px_20px_-8px_var(--kpi-shadow)] hover:shadow-[0_10px_26px_-8px_var(--kpi-shadow-hover)]",
        className,
      )}
      style={
        {
          "--stat-delay": `${index * 70}ms`,
          "--kpi-tint": `${accent}3d`,
          "--kpi-shadow": `${accent}40`,
          "--kpi-shadow-hover": `${accent}66`,
        } as React.CSSProperties
      }
    >
      <div className="flex items-start justify-between gap-2">
        <p className="text-xs font-medium text-muted-foreground">{label}</p>
        {Icon && (
          <span
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full"
            style={{ backgroundColor: `${accent}1f`, color: accent }}
          >
            <Icon className="h-4 w-4" aria-hidden />
          </span>
        )}
      </div>
      {/* The animated figure is decorative motion over the same number — the
          accessible name always carries the settled value. */}
      <p className="mt-1 text-2xl font-semibold tabular-nums text-foreground" aria-label={value}>
        <span aria-hidden>{animating ? format(Math.round(animated)) : value}</span>
      </p>
      {hint && <div className={cn("mt-0.5 text-xs", hintClass ?? "text-muted-foreground")}>{hint}</div>}
    </Card>
  );
}
