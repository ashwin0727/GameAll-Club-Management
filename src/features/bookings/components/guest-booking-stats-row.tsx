"use client";

import { CheckCircle2, Clock, UserRound, Wallet, XCircle, type LucideIcon } from "lucide-react";
import { Card } from "@/components/ui/card";
import { percentDelta, type StatDelta } from "@/features/bookings/booking-stats";
import type { GuestStats } from "@/features/bookings/guest-booking-stats";
import { formatCurrency } from "@/features/pricing/money";
import { cn } from "@/lib/utils";

const DELTA_TONE: Record<StatDelta["tone"], string> = {
  up: "text-success",
  down: "text-destructive",
  flat: "text-muted-foreground",
};

interface Card5 {
  key: string;
  icon: LucideIcon;
  tone: string;
  label: string;
  value: string;
  delta?: StatDelta | null;
  /** Shown in place of a comparison (Upcoming has none). */
  link?: { text: string; onClick: () => void };
  /** Shown when there is no earlier period to compare with. */
  fallback?: string;
}

/**
 * The five figures at the top of Guest Bookings: total, completed, upcoming, cancelled and
 * revenue — each with its own coloured icon, and a "↑ 18% from previous period" line
 * where there is an earlier period to compare with.
 */
export function GuestBookingStatsRow({
  stats,
  upcoming,
  currency,
  onViewToday,
}: {
  stats: GuestStats;
  upcoming: number;
  currency: string;
  onViewToday: () => void;
}) {
  const { summary, previous } = stats;
  const versus = "from previous period";
  const cards: Card5[] = [
    {
      key: "total",
      icon: UserRound,
      tone: "bg-success/15 text-success",
      label: "Total Guest Bookings",
      value: String(summary.total),
      delta: percentDelta(summary.total, previous.total, versus),
      fallback: "In the selected period",
    },
    {
      key: "completed",
      icon: CheckCircle2,
      tone: "bg-success/15 text-success",
      label: "Completed Bookings",
      value: String(summary.completed),
      delta: percentDelta(summary.completed, previous.completed, versus),
      fallback: "In the selected period",
    },
    {
      key: "upcoming",
      icon: Clock,
      tone: "bg-warning/15 text-warning",
      label: "Upcoming Bookings",
      value: String(upcoming),
      link: { text: "View today's bookings →", onClick: onViewToday },
    },
    {
      key: "cancelled",
      icon: XCircle,
      tone: "bg-destructive/15 text-destructive",
      label: "Cancelled Bookings",
      value: String(summary.cancelled),
      delta: percentDelta(summary.cancelled, previous.cancelled, versus),
      fallback: "In the selected period",
    },
    {
      key: "revenue",
      icon: Wallet,
      tone: "bg-purple-500/15 text-purple-600 dark:text-purple-400",
      label: "Total Revenue",
      value: formatCurrency(summary.totalRevenueMinor, currency),
      delta: percentDelta(summary.totalRevenueMinor, previous.revenueMinor, versus),
      fallback: "Money collected",
    },
  ];

  return (
    <div className="grid grid-cols-2 gap-3 lg:grid-cols-3 xl:grid-cols-5">
      {cards.map(({ key, icon: Icon, tone, label, value, delta, link, fallback }) => (
        <Card key={key} className="flex items-center gap-4 p-4">
          <span className={cn("flex h-12 w-12 shrink-0 items-center justify-center rounded-xl", tone)}>
            <Icon className="h-6 w-6" aria-hidden />
          </span>
          <div className="min-w-0 space-y-0.5">
            <p className="truncate text-xs text-muted-foreground">{label}</p>
            <p className="truncate text-2xl font-semibold leading-tight tabular-nums">{value}</p>
            {link ? (
              <button type="button" onClick={link.onClick} className="truncate text-[11px] font-medium text-blue-600 hover:underline dark:text-blue-400">
                {link.text}
              </button>
            ) : (
              <p className={cn("truncate text-[11px]", delta ? DELTA_TONE[delta.tone] : "text-muted-foreground")}>
                {delta ? delta.text : fallback}
              </p>
            )}
          </div>
        </Card>
      ))}
    </div>
  );
}
