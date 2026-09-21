"use client";

import { BadgeIndianRupee, CalendarCheck2, Gauge, Users, type LucideIcon } from "lucide-react";
import { Card } from "@/components/ui/card";
import { formatUtilization, type StatDelta } from "@/features/bookings/booking-stats";
import { cn, formatCurrencyINR } from "@/lib/utils";

interface Stat {
  icon: LucideIcon;
  tone: string;
  label: string;
  value: string;
  /** What the figure covers; shown when there is no previous period to compare with. */
  sub: string;
  delta?: StatDelta | null;
}

const DELTA_TONE: Record<StatDelta["tone"], string> = {
  up: "text-success",
  down: "text-destructive",
  flat: "text-muted-foreground",
};

/**
 * The four figures under the calendar and under the list. The caller works the
 * numbers out from whatever the person has selected (period, range, filters),
 * so the cards always describe what is on screen. Where there is a previous
 * period to compare with, each card ends in a "↑ 12% vs last month" line;
 * where there isn't, it says what the figure covers instead.
 */
export function BookingStatsRow({
  totalGuestBookings,
  guestSub,
  guestDelta,
  activeMembers,
  utilizationPercent,
  courtsActive,
  courtsTotal,
  utilizationDelta,
  revenueInr,
  revenueSub,
  revenueDelta,
}: {
  totalGuestBookings: number;
  /** What the count covers: "On this day", "In the selected range". */
  guestSub: string;
  guestDelta?: StatDelta | null;
  activeMembers: number | undefined;
  /** Unrounded percent (0–100); the card decides how many decimals to show. */
  utilizationPercent: number;
  courtsActive: number;
  courtsTotal: number;
  utilizationDelta?: StatDelta | null;
  revenueInr: number | undefined;
  /** What the revenue covers, e.g. "For the selected week". */
  revenueSub: string;
  revenueDelta?: StatDelta | null;
}) {
  const stats: Stat[] = [
    {
      icon: CalendarCheck2,
      tone: "bg-blue-500/15 text-blue-600 dark:text-blue-400",
      label: "Total Guest Bookings",
      value: String(totalGuestBookings),
      sub: guestSub,
      delta: guestDelta,
    },
    {
      icon: Users,
      tone: "bg-success/15 text-success",
      label: "Active Members",
      value: activeMembers === undefined ? "—" : String(activeMembers),
      sub: "With an active membership",
    },
    {
      icon: Gauge,
      tone: "bg-purple-500/15 text-purple-600 dark:text-purple-400",
      label: "Court Utilization",
      value: formatUtilization(utilizationPercent),
      sub: `${courtsActive} / ${courtsTotal} courts active`,
      delta: utilizationDelta,
    },
    {
      icon: BadgeIndianRupee,
      tone: "bg-success/15 text-success",
      label: "Overall Revenue",
      value: revenueInr === undefined ? "—" : formatCurrencyINR(revenueInr),
      sub: revenueSub,
      delta: revenueDelta,
    },
  ];
  return (
    <div className="grid grid-cols-2 gap-3 xl:grid-cols-4">
      {stats.map(({ icon: Icon, tone, label, value, sub, delta }) => (
        <Card key={label} className="flex items-center gap-4 p-4" title={delta ? sub : undefined}>
          <span className={cn("flex h-12 w-12 shrink-0 items-center justify-center rounded-xl", tone)}>
            <Icon className="h-6 w-6" aria-hidden />
          </span>
          <div className="min-w-0 space-y-0.5">
            <p className="truncate text-xs text-muted-foreground">{label}</p>
            <p className="truncate text-2xl font-semibold leading-tight tabular-nums">{value}</p>
            <p className={cn("truncate text-[11px]", delta ? DELTA_TONE[delta.tone] : "text-muted-foreground")}>
              {delta ? delta.text : sub}
            </p>
          </div>
        </Card>
      ))}
    </div>
  );
}
