"use client";

import { useMemo } from "react";
import { ArrowRight, CalendarPlus, Plus, UserRound, Users, type LucideIcon } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { CustomerAvatar } from "@/features/bookings/components/customer-avatar";
import { guestsWithAtLeast, recentGuests } from "@/features/bookings/guest-insights";
import type { GuestBookingRow } from "@/features/bookings/types";
import { cn } from "@/lib/utils";

const OUTLINE_BTN =
  "flex h-9 shrink-0 items-center justify-center gap-1.5 whitespace-nowrap rounded-[10px] border border-[#0B7A55] bg-card px-4 text-sm font-medium text-[#0B7A55] transition-colors hover:bg-[#0B7A55]/10 dark:border-primary dark:text-primary dark:hover:bg-primary/10";

function IconTile({ icon: Icon, tone }: { icon: LucideIcon; tone: string }) {
  return (
    <span className={cn("flex h-12 w-12 shrink-0 items-center justify-center rounded-xl", tone)}>
      <Icon className="h-6 w-6" aria-hidden />
    </span>
  );
}

/**
 * The row of three cards under the Guest Bookings table: Quick Actions, Recent Guests and a
 * short Guest Insights summary whose button opens the full insights.
 */
export function GuestBookingsHighlights({
  history,
  canBook,
  onNewBooking,
  onViewAllGuests,
  onViewInsights,
}: {
  /** The sport's whole guest-booking history; undefined while it loads. */
  history: GuestBookingRow[] | undefined;
  canBook: boolean;
  onNewBooking: () => void;
  onViewAllGuests: () => void;
  onViewInsights: () => void;
}) {
  const recent = useMemo(() => (history ? recentGuests(history, new Date()) : null), [history]);
  const repeat = useMemo(() => (history ? guestsWithAtLeast(history, 2) : null), [history]);

  return (
    <div className="grid gap-4 lg:grid-cols-3">
      {/* Quick Actions */}
      <Card className="flex items-center gap-4 p-4">
        <IconTile icon={CalendarPlus} tone="bg-blue-500/15 text-blue-600 dark:text-blue-400" />
        <div className="min-w-0 flex-1 space-y-1">
          <p className="font-semibold">Quick Actions</p>
          <p className="text-sm text-muted-foreground">Create a new guest booking, manage guest details and more.</p>
        </div>
        {canBook && (
          <button type="button" onClick={onNewBooking} className={OUTLINE_BTN}>
            <Plus className="h-4 w-4" aria-hidden />
            New Guest Booking
          </button>
        )}
      </Card>

      {/* Recent Guests */}
      <Card className="flex items-center gap-4 p-4">
        <IconTile icon={UserRound} tone="bg-success/15 text-success" />
        <div className="min-w-0 flex-1 space-y-2">
          <p className="font-semibold">Recent Guests</p>
          {recent === null ? (
            <Skeleton className="h-9 w-full max-w-[14rem] rounded-full" />
          ) : recent.shown.length === 0 ? (
            <p className="text-sm text-muted-foreground">No guests yet.</p>
          ) : (
            <div className="flex flex-wrap items-center gap-2">
              {recent.shown.map((g) => (
                <span key={g.key} title={g.name}>
                  <CustomerAvatar name={g.name} />
                </span>
              ))}
              {recent.more > 0 && (
                <span
                  className="flex h-9 min-w-9 items-center justify-center rounded-full bg-secondary px-2 text-xs font-medium text-muted-foreground"
                  title={`${recent.more} more guests booked in the last 30 days`}
                >
                  +{recent.more}
                </span>
              )}
            </div>
          )}
        </div>
        <button
          type="button"
          onClick={onViewAllGuests}
          className="flex shrink-0 items-center gap-1 whitespace-nowrap text-sm font-medium text-blue-600 hover:underline dark:text-blue-400"
        >
          View All
          <ArrowRight className="h-4 w-4" aria-hidden />
        </button>
      </Card>

      {/* Guest Insights */}
      <Card className="flex items-center gap-4 p-4">
        <IconTile icon={Users} tone="bg-success/15 text-success" />
        <div className="min-w-0 flex-1 space-y-1">
          <p className="font-semibold">Guest Insights</p>
          {repeat === null ? (
            <Skeleton className="h-10 w-full rounded-md" />
          ) : repeat > 0 ? (
            <p className="text-sm text-muted-foreground">
              {repeat} {repeat === 1 ? "guest has" : "guests have"} made multiple bookings. Consider inviting them to become members!
            </p>
          ) : (
            <p className="text-sm text-muted-foreground">No guest has booked more than once yet. Repeat guests will show up here.</p>
          )}
        </div>
        <button type="button" onClick={onViewInsights} className={OUTLINE_BTN}>
          View Insights
          <ArrowRight className="h-4 w-4" aria-hidden />
        </button>
      </Card>
    </div>
  );
}
