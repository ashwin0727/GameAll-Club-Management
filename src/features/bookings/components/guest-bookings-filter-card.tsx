"use client";

import { Download, Search, X } from "lucide-react";
import type { BookingStatus } from "@/features/bookings/types";
import { DateRangePicker } from "@/features/bookings/components/date-range-picker";
import { SelectField } from "@/features/bookings/components/select-field";
import { SELECT } from "@/features/bookings/components/booking-toolbar";
import { Card } from "@/components/ui/card";
import { cn } from "@/lib/utils";

export type GuestTab = "all" | "upcoming" | "completed" | "cancelled";

const TABS: { key: GuestTab; label: string }[] = [
  { key: "all", label: "All Bookings" },
  { key: "upcoming", label: "Upcoming" },
  { key: "completed", label: "Completed" },
  { key: "cancelled", label: "Cancelled" },
];

const STATUS_OPTIONS: { value: BookingStatus | ""; label: string }[] = [
  { value: "", label: "All Status" },
  { value: "confirmed", label: "Confirmed" },
  { value: "completed", label: "Completed" },
  { value: "cancelled", label: "Cancelled" },
  { value: "pending", label: "Pending" },
];

/** Every control here: the calendar's height, border and 10px radius, with a border that darkens on hover. */
const CONTROL = cn(SELECT, "transition-colors hover:border-foreground/30");

/**
 * The card above the Guest Bookings table: the four tabs, then search, the sport, court and
 * status dropdowns, the date range and Export. Its controls are the same ones the Calendar
 * uses, so both pages look and behave alike.
 */
export function GuestBookingsFilterCard({
  tab,
  onTabChange,
  search,
  onSearchChange,
  sportOptions,
  sportId,
  onSportChange,
  courts,
  courtId,
  onCourtChange,
  status,
  onStatusChange,
  from,
  to,
  onRangeChange,
  rangeDisabled,
  onExport,
  exportDisabled,
}: {
  tab: GuestTab;
  onTabChange: (tab: GuestTab) => void;
  search: string;
  onSearchChange: (value: string) => void;
  /** The facility's sports. The choice is the same one the top bar makes. */
  sportOptions: { value: string; label: string }[];
  sportId: string;
  onSportChange: (sportId: string) => void;
  courts: { id: string; name: string }[];
  courtId: string;
  onCourtChange: (courtId: string) => void;
  status: BookingStatus | "";
  onStatusChange: (status: BookingStatus | "") => void;
  from: string;
  to: string;
  onRangeChange: (from: string, to: string) => void;
  /** Upcoming looks ahead from now, so the range doesn't apply to it. */
  rangeDisabled: boolean;
  onExport: () => void;
  exportDisabled: boolean;
}) {
  return (
    <Card className="space-y-4 p-4">
      <div className="flex gap-6 border-b border-border/60" role="tablist" aria-label="Booking view">
        {TABS.map((t) => (
          <button
            key={t.key}
            type="button"
            role="tab"
            aria-selected={tab === t.key}
            onClick={() => onTabChange(t.key)}
            className={cn(
              "-mb-px border-b-2 px-1 pb-3 pt-1 text-sm font-medium transition-colors",
              tab === t.key
                ? "border-[#0B7A55] text-[#0B7A55] dark:border-primary dark:text-primary"
                : "border-transparent text-foreground/80 hover:text-foreground",
            )}
          >
            {t.label}
          </button>
        ))}
      </div>

      <div className="flex flex-wrap items-center gap-x-3 gap-y-3">
        <div className="relative min-w-[240px] flex-1">
          <Search className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
          <input
            type="text"
            aria-label="Search bookings"
            placeholder="Search by name, phone, booking ID…"
            value={search}
            onChange={(e) => onSearchChange(e.target.value)}
            className={cn(CONTROL, "w-full pl-10 pr-9 placeholder:text-muted-foreground")}
          />
          {search && (
            <button
              type="button"
              aria-label="Clear search"
              onClick={() => onSearchChange("")}
              className="absolute right-2.5 top-1/2 -translate-y-1/2 rounded p-1 text-muted-foreground hover:text-foreground"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          )}
        </div>

        <SelectField
          wrapperClassName="w-[160px]"
          ariaLabel="Sport"
          value={sportId}
          onValueChange={onSportChange}
          options={sportOptions}
          className={CONTROL}
        />
        <SelectField
          wrapperClassName="w-[150px]"
          ariaLabel="Court"
          value={courtId}
          onValueChange={onCourtChange}
          options={[{ value: "", label: "All Courts" }, ...courts.map((c) => ({ value: c.id, label: c.name }))]}
          className={CONTROL}
        />
        <SelectField
          wrapperClassName="w-[150px]"
          ariaLabel="Status"
          value={status}
          onValueChange={(v) => onStatusChange(v as BookingStatus | "")}
          options={STATUS_OPTIONS}
          className={CONTROL}
        />

        <div className={cn(rangeDisabled && "pointer-events-none opacity-50")} aria-disabled={rangeDisabled}>
          <DateRangePicker
            from={from}
            to={to}
            onChange={onRangeChange}
            align="right"
            fullLabel
            triggerClassName={cn(CONTROL, "flex items-center gap-2 whitespace-nowrap px-[14px] font-medium tabular-nums")}
          />
        </div>

        <button
          type="button"
          onClick={onExport}
          disabled={exportDisabled}
          className={cn(CONTROL, "flex items-center gap-2 px-4 font-medium hover:bg-accent disabled:opacity-50")}
        >
          <Download className="h-4 w-4" aria-hidden />
          Export
        </button>
      </div>
    </Card>
  );
}
