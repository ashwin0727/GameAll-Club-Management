"use client";

import { ArrowDown, ArrowUp, type LucideIcon } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { useCountUp } from "@/features/dashboard/use-count-up";
import { cn } from "@/lib/utils";

/**
 * The Membership Dashboard's own KPI tile, per the design: the icon chip on the left with the
 * figure beside it and the label directly under the figure, the change pill at the top right,
 * and the sub-line along the bottom of the card.
 */
export function MembershipStatCard({
  icon: Icon,
  iconBg,
  iconColor,
  value,
  countTo,
  format,
  deltaPct,
  sub,
  subTone,
  label,
  index = 0,
  className,
  compact = false,
}: {
  icon: LucideIcon;
  iconBg: string;
  iconColor: string;
  value: string;
  countTo?: number;
  format?: (v: number) => string;
  deltaPct?: number | null;
  /** The line along the card's bottom edge. Omit it for a shorter, two-line card. */
  sub?: string;
  /** Colour for that line; muted unless given (the design shows the month-on-month one in green). */
  subTone?: string;
  label: string;
  index?: number;
  /** Surface overrides — the Plans page uses this to drop the border for its glass treatment. */
  className?: string;
  /** The tighter tile from the Plans design: smaller chip, figure and padding. */
  compact?: boolean;
}) {
  const animated = useCountUp(countTo ?? 0);
  const animating = countTo !== undefined && format !== undefined;
  const shown = animating ? format(Math.round(animated)) : value;
  const positive = deltaPct != null && deltaPct >= 0;
  const DeltaIcon = positive ? ArrowUp : ArrowDown;

  return (
    <Card
      className={cn(
        "stat-enter flex flex-col rounded-xl shadow-sm transition-shadow hover:shadow-md",
        compact ? "gap-2 p-3" : "gap-3 p-4",
        className,
      )}
      style={{ "--stat-delay": `${index * 70}ms` } as React.CSSProperties}
    >
      {/* Icon on the left; the figure beside it with its label directly underneath, both
          top-aligned against the chip. The sub-line then runs along the card's bottom edge. */}
      <div className={cn("flex items-start", compact ? "gap-2.5" : "gap-3")}>
        <span
          className={cn(
            "flex shrink-0 items-center justify-center rounded-xl",
            compact ? "h-10 w-10" : "h-12 w-12",
            iconBg,
          )}
        >
          <Icon className={cn(compact ? "h-5 w-5" : "h-6 w-6", iconColor)} aria-hidden />
        </span>

        <div className="min-w-0 flex-1">
          <p
            className={cn(
              "truncate font-bold leading-none tabular-nums text-foreground",
              compact ? "text-[22px]" : "text-[26px]",
            )}
          >
            {shown}
          </p>
          <p className={cn("mt-1.5 truncate font-semibold text-foreground", compact ? "text-[13px]" : "text-sm")}>
            {label}
          </p>
        </div>

        {deltaPct != null && (
          <span
            className={cn(
              "flex shrink-0 items-center gap-0.5 whitespace-nowrap text-sm font-semibold",
              positive ? "text-success" : "text-destructive",
            )}
          >
            <DeltaIcon className="h-3.5 w-3.5" aria-hidden />
            {Math.abs(Math.round(deltaPct * 10) / 10)}%
          </span>
        )}
      </div>

      {/* mt-auto keeps this on the card's bottom edge when the row stretches the card taller
          than its content — otherwise it strands the line mid-card with white space beneath. */}
      {sub && <p className={cn("mt-auto line-clamp-2 text-xs leading-snug", subTone ?? "text-muted-foreground")}>{sub}</p>}
    </Card>
  );
}

export function MembershipStatCardSkeleton({ compact = false }: { compact?: boolean }) {
  return <Skeleton className={cn("rounded-xl", compact ? "h-[100px]" : "h-[112px]")} />;
}
