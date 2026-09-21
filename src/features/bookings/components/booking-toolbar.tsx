"use client";

import { CalendarDays, ChevronLeft, ChevronRight, Plus } from "lucide-react";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import { rangeLabel, type CalView } from "@/features/bookings/calendar-events";
import { cn } from "@/lib/utils";

/** Shared by the calendar and list toolbars so every control is the same height, border and radius. */
export const SELECT =
  "h-[42px] rounded-[10px] border border-input bg-card px-[18px] text-sm outline-none focus-visible:border-foreground/40";
export const ICON_BTN =
  "flex h-[42px] w-[42px] items-center justify-center rounded-[10px] border border-input bg-card text-muted-foreground transition-colors hover:text-foreground";

const VIEWS: { value: CalView; label: string }[] = [
  { value: "day", label: "Day" },
  { value: "week", label: "Week" },
  { value: "month", label: "Month" },
  { value: "agenda", label: "Agenda" },
];

/**
 * The calendar's toolbar: previous / next, Today and the current period on the left;
 * Day · Week · Month · Agenda in the middle, and + Guest Booking at the right end. The selected
 * view is a filled deep-green pill.
 */
export function BookingToolbar({
  view,
  onViewChange,
  anchor,
  onPrev,
  onNext,
  onToday,
  onGuestBooking,
}: {
  view: CalView;
  onViewChange: (v: CalView) => void;
  anchor: Date;
  onPrev: () => void;
  onNext: () => void;
  onToday: () => void;
  /** Opens the guest booking page. */
  onGuestBooking: () => void;
}) {
  const perms = usePermissionContext();
  // Without a permission context (e.g. mid-onboarding) the page's own role gate already applied.
  const canBook =
    !perms ||
    perms.can("GUEST_BOOKINGS_CREATE") ||
    perms.can("BOOKINGS_CREATE");
  return (
    <div className="grid items-center gap-3 lg:grid-cols-[1fr_auto_1fr]">
      <div className="flex flex-wrap items-center gap-3">
        <button
          type="button"
          aria-label="Previous"
          onClick={onPrev}
          className={ICON_BTN}
        >
          <ChevronLeft className="h-4 w-4" />
        </button>
        <button
          type="button"
          aria-label="Next"
          onClick={onNext}
          className={ICON_BTN}
        >
          <ChevronRight className="h-4 w-4" />
        </button>
        <button
          type="button"
          onClick={onToday}
          className="h-[42px] rounded-[10px] border border-[#0B7A55] bg-card px-4 text-sm font-medium text-[#0B7A55] transition-colors hover:bg-[#0B7A55]/10 dark:border-primary dark:text-primary dark:hover:bg-primary/10"
        >
          Today
        </button>
        <div className="flex h-[42px] items-center gap-2 rounded-[10px] border border-input bg-card px-4 text-sm font-medium">
          <CalendarDays className="h-4 w-4 text-muted-foreground" aria-hidden />
          <span className="whitespace-nowrap tabular-nums">
            {rangeLabel(view, anchor)}
          </span>
        </div>
      </div>

      <div
        className="flex items-center gap-1 rounded-[8px] border border-input bg-card p-1"
        role="group"
        aria-label="View"
      >
        {VIEWS.map((v) => (
          <button
            key={v.value}
            type="button"
            aria-pressed={view === v.value}
            onClick={() => onViewChange(v.value)}
            className={cn(
              "h-9 min-w-[4.5rem] rounded-[6px] px-4 text-sm font-medium transition-colors",
              view === v.value
                ? "bg-[#0B7A55] text-white shadow-sm dark:bg-primary dark:text-primary-foreground"
                : "text-foreground hover:bg-accent",
            )}
          >
            {v.label}
          </button>
        ))}
      </div>

      <div className="flex justify-start lg:justify-end">
        {canBook && (
          <button
            type="button"
            onClick={onGuestBooking}
            className="flex h-[42px] items-center justify-center gap-2 rounded-[10px] bg-[#0B7A55] px-5 text-sm font-semibold text-white shadow-sm transition-opacity hover:opacity-90 dark:bg-primary dark:text-primary-foreground"
          >
            <Plus className="h-4 w-4" aria-hidden />
            Guest Booking
          </button>
        )}
      </div>
    </div>
  );
}
