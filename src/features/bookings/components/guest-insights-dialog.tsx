"use client";

import { useMemo, useState } from "react";
import { ArrowRight, Coins, Crown, Clock, RefreshCw, Star, UserPlus, Users, type LucideIcon } from "lucide-react";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { percentDelta, pointsDelta, type StatDelta } from "@/features/bookings/booking-stats";
import { DateRangePicker } from "@/features/bookings/components/date-range-picker";
import { SelectField } from "@/components/shared/select-field";
import { computeInsights, periodRange, type InsightPeriod } from "@/features/bookings/guest-insights";
import type { GuestBookingRow } from "@/features/bookings/types";
import { formatCurrency } from "@/features/pricing/money";
import { cn } from "@/lib/utils";

const PERIODS: { value: InsightPeriod; label: string }[] = [
  { value: "7", label: "Last 7 Days" },
  { value: "30", label: "Last 30 Days" },
  { value: "90", label: "Last 90 Days" },
  { value: "custom", label: "Custom" },
];

const DELTA_TONE: Record<StatDelta["tone"], string> = {
  up: "text-success",
  down: "text-destructive",
  flat: "text-muted-foreground",
};

function iso(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function Tile({
  icon: Icon,
  tone,
  value,
  label,
  sub,
  delta,
}: {
  icon: LucideIcon;
  tone: string;
  value: string;
  label: string;
  sub: string;
  delta: StatDelta | null;
}) {
  return (
    <div className="rounded-xl border border-border bg-card p-4">
      <div className="flex items-center gap-3">
        <span className={cn("flex h-10 w-10 shrink-0 items-center justify-center rounded-lg", tone)}>
          <Icon className="h-5 w-5" aria-hidden />
        </span>
        <p className="text-2xl font-semibold tabular-nums leading-none">{value}</p>
      </div>
      <p className="mt-3 text-sm font-medium">{label}</p>
      <p className="text-xs text-muted-foreground">{sub}</p>
      {delta && <p className={cn("mt-2 text-xs font-medium", DELTA_TONE[delta.tone])}>{delta.text.trim()}</p>}
    </div>
  );
}

/**
 * Guest Insights: what the club's guests are doing, for the sport on screen.
 *
 * Unique Guests, the two averages and New Guests follow the period picked at the top. Repeat
 * and Frequent Guests look at every guest the sport has ever had. Each arrow compares with the
 * previous period of the same length — for Repeat and Frequent, with how many there were the
 * day this period began.
 */
export function GuestInsightsDialog({
  open,
  onOpenChange,
  rows,
  currency,
  onViewPotentialMembers,
}: {
  onViewPotentialMembers: () => void;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** The sport's whole guest-booking history; undefined while it loads. */
  rows: GuestBookingRow[] | undefined;
  currency: string;
}) {
  const [period, setPeriod] = useState<InsightPeriod>("30");
  const [custom, setCustom] = useState(() => {
    const to = new Date();
    const from = new Date(to);
    from.setDate(from.getDate() - 29);
    return { from: iso(from), to: iso(to) };
  });

  const insights = useMemo(() => {
    if (!rows) return null;
    const range = periodRange(period, custom);
    return computeInsights(rows, range.from, range.to);
  }, [rows, period, custom]);

  const cur = insights?.current;
  const prev = insights?.previous;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl gap-5">
        <DialogHeader>
          <div className="mr-8 flex flex-wrap items-start justify-between gap-3">
            <div className="flex items-center gap-3">
              <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-success/15 text-success">
                <Users className="h-5 w-5" aria-hidden />
              </span>
              <div className="space-y-1">
                <DialogTitle>Guest Insights</DialogTitle>
                <DialogDescription>Key insights about your guest bookings and players.</DialogDescription>
              </div>
            </div>
            <SelectField
              wrapperClassName="w-[150px]"
              ariaLabel="Period"
              value={period}
              onValueChange={(v) => setPeriod(v as InsightPeriod)}
              options={PERIODS}
              className="h-10 rounded-[10px] border border-input bg-card px-4 text-sm outline-none transition-colors hover:border-foreground/30 focus-visible:border-foreground/40"
            />
          </div>
        </DialogHeader>

        {period === "custom" && (
          <div className="flex justify-end">
            <DateRangePicker
              from={custom.from}
              to={custom.to}
              onChange={(from, to) => setCustom({ from, to })}
              align="right"
              fullLabel
              triggerClassName="flex h-10 items-center gap-2 whitespace-nowrap rounded-[10px] border border-input bg-card px-4 text-sm font-medium tabular-nums outline-none transition-colors hover:border-foreground/30"
            />
          </div>
        )}

        {!insights || !cur || !prev ? (
          <Skeleton className="h-64 w-full rounded-xl" />
        ) : (
          <>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
              <Tile
                icon={Users}
                tone="bg-blue-500/15 text-blue-600 dark:text-blue-400"
                value={String(cur.unique)}
                label="Unique Guests"
                sub="Guests who made at least one booking"
                delta={percentDelta(cur.unique, prev.unique, "")}
              />
              <Tile
                icon={RefreshCw}
                tone="bg-success/15 text-success"
                value={String(insights.repeat)}
                label="Repeat Guests"
                sub="Booked more than once"
                delta={percentDelta(insights.repeat, insights.repeatAtStart, "")}
              />
              <Tile
                icon={Star}
                tone="bg-warning/15 text-warning"
                value={String(insights.frequent)}
                label="Frequent Guests"
                sub="Guests with 3+ bookings"
                delta={percentDelta(insights.frequent, insights.frequentAtStart, "")}
              />
              <Tile
                icon={Clock}
                tone="bg-warning/15 text-warning"
                value={cur.avgBookings.toFixed(1)}
                label="Avg. Bookings per Guest"
                sub="Per unique guest"
                delta={percentDelta(cur.avgBookings, prev.avgBookings, "")}
              />
              <Tile
                icon={Coins}
                tone="bg-blue-500/15 text-blue-600 dark:text-blue-400"
                value={formatCurrency(cur.avgValueMinor, currency)}
                label="Avg. Booking Value"
                sub="Per guest booking"
                delta={percentDelta(cur.avgValueMinor, prev.avgValueMinor, "")}
              />
              <Tile
                icon={UserPlus}
                tone="bg-purple-500/15 text-purple-600 dark:text-purple-400"
                value={`${Math.round(cur.newPercent)}%`}
                label="New Guests"
                sub="First time visitors"
                delta={pointsDelta(cur.newPercent, prev.newPercent, "")}
              />
            </div>

            <div className="flex flex-wrap items-center gap-3 rounded-xl bg-success/10 p-4">
              <Crown className="h-5 w-5 shrink-0 text-warning" aria-hidden />
              <div className="min-w-[200px] flex-1 space-y-0.5">
                <p className="text-sm font-semibold">Opportunity: Convert Guests to Members</p>
                <p className="text-sm text-muted-foreground">
                  {insights.frequent > 0
                    ? `${insights.frequent} ${insights.frequent === 1 ? "guest has" : "guests have"} made 3 or more bookings. Consider reaching out with a membership offer.`
                    : "No guest has made 3 or more bookings yet. Guests who do will be highlighted here."}
                </p>
              </div>
              <button
                type="button"
                onClick={onViewPotentialMembers}
                className="flex h-10 items-center gap-2 whitespace-nowrap rounded-[10px] bg-[#0B7A55] px-4 text-sm font-medium text-white transition-colors hover:bg-[#0B7A55]/90"
              >
                View Potential Members
                <ArrowRight className="h-4 w-4" aria-hidden />
              </button>
            </div>
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}
