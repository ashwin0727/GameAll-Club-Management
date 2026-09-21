"use client";

import { ArrowRight, Check, Filter, Lightbulb, Mail, Target } from "lucide-react";
import { Card } from "@/components/ui/card";
import { SelectField } from "@/features/bookings/components/select-field";
import { SELECT } from "@/features/bookings/components/booking-toolbar";
import type { LastBookingFilter, PotentialFilters } from "@/features/bookings/potential-members";
import { cn } from "@/lib/utils";

export const BOOKING_COUNT_OPTIONS = [
  { value: "3", label: "3 or more" },
  { value: "5", label: "5 or more" },
  { value: "10", label: "10 or more" },
];

export const LAST_BOOKING_OPTIONS: { value: LastBookingFilter; label: string }[] = [
  { value: "any", label: "Any time" },
  { value: "7", label: "Last 7 days" },
  { value: "30", label: "Last 30 days" },
  { value: "90", label: "Last 90 days" },
];

export const TOTAL_SPENT_OPTIONS = [
  { value: "0", label: "Any amount" },
  { value: "100000", label: "₹1,000 or more" },
  { value: "500000", label: "₹5,000 or more" },
  { value: "1000000", label: "₹10,000 or more" },
];

const OUTLINE_BTN =
  "flex h-10 w-full items-center justify-center gap-2 rounded-[10px] border border-[#0B7A55] bg-card px-4 text-sm font-medium text-[#0B7A55] transition-colors hover:bg-[#0B7A55]/10 disabled:opacity-50 dark:border-primary dark:text-primary dark:hover:bg-primary/10";

const FIELD = cn(SELECT, "transition-colors hover:border-foreground/30");

function Labelled({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <p className="text-xs text-muted-foreground">{label}</p>
      {children}
    </div>
  );
}

/**
 * The column to the right of the table: why these guests are listed, sending invitations to
 * several at once, the filters, and a tip. Invitations here copy the club's join link together
 * with the selected guests' numbers, for pasting into a message.
 */
export function PotentialMembersPanels({
  filters,
  onFiltersChange,
  showFilters,
  selectedCount,
  onSelectGuests,
  onCopySelected,
  onClearSelection,
  bulkCopied,
}: {
  filters: PotentialFilters;
  onFiltersChange: (next: PotentialFilters) => void;
  showFilters: boolean;
  selectedCount: number;
  onSelectGuests: () => void;
  onCopySelected: () => void;
  onClearSelection: () => void;
  bulkCopied: boolean;
}) {
  return (
    <div className="space-y-4">
      <Card className="flex items-start gap-3 bg-success/5 p-4">
        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-success/15 text-success">
          <Target className="h-5 w-5" aria-hidden />
        </span>
        <div className="space-y-1">
          <p className="text-sm font-semibold">Why These Guests?</p>
          <p className="text-xs leading-relaxed text-muted-foreground">
            These guests have made 3 or more bookings and are not yet members. They may be interested in a membership plan.
          </p>
        </div>
      </Card>

      <Card className="space-y-3 p-4">
        <div className="flex items-start gap-3">
          <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-blue-500/15 text-blue-600 dark:text-blue-400">
            <Mail className="h-5 w-5" aria-hidden />
          </span>
          <div className="space-y-1">
            <p className="text-sm font-semibold">Send Invitations</p>
            <p className="text-xs text-muted-foreground">
              {selectedCount > 0
                ? `${selectedCount} guest${selectedCount === 1 ? "" : "s"} selected. Copy their numbers with the join link.`
                : "Invite multiple guests at once."}
            </p>
          </div>
        </div>
        {selectedCount === 0 ? (
          <button type="button" onClick={onSelectGuests} className={OUTLINE_BTN}>
            Select Guests
            <ArrowRight className="h-4 w-4" aria-hidden />
          </button>
        ) : (
          <div className="space-y-2">
            <button type="button" onClick={onCopySelected} className={OUTLINE_BTN}>
              {bulkCopied ? (
                <>
                  <Check className="h-4 w-4" aria-hidden />
                  Copied
                </>
              ) : (
                "Copy numbers & link"
              )}
            </button>
            <button type="button" onClick={onClearSelection} className="w-full text-center text-xs text-muted-foreground hover:text-foreground">
              Clear selection
            </button>
          </div>
        )}
      </Card>

      {showFilters && (
        <Card className="space-y-4 p-4">
          <p className="flex items-center gap-2 text-sm font-semibold">
            <Filter className="h-4 w-4" aria-hidden />
            Filters
          </p>
          <Labelled label="Booking Count">
            <SelectField
              ariaLabel="Booking count"
              value={String(filters.minBookings)}
              onValueChange={(v) => onFiltersChange({ ...filters, minBookings: Number(v) })}
              options={BOOKING_COUNT_OPTIONS}
              className={FIELD}
            />
          </Labelled>
          <Labelled label="Last Booking">
            <SelectField
              ariaLabel="Last booking"
              value={filters.lastBooking}
              onValueChange={(v) => onFiltersChange({ ...filters, lastBooking: v as LastBookingFilter })}
              options={LAST_BOOKING_OPTIONS}
              className={FIELD}
            />
          </Labelled>
          <Labelled label="Total Spent">
            <SelectField
              ariaLabel="Total spent"
              value={String(filters.minSpentMinor)}
              onValueChange={(v) => onFiltersChange({ ...filters, minSpentMinor: Number(v) })}
              options={TOTAL_SPENT_OPTIONS}
              className={FIELD}
            />
          </Labelled>
        </Card>
      )}

      <Card className="flex items-start gap-3 bg-purple-500/5 p-4">
        <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-purple-500/15 text-purple-600 dark:text-purple-400">
          <Lightbulb className="h-4 w-4" aria-hidden />
        </span>
        <div className="space-y-1">
          <p className="text-sm font-semibold">Tip</p>
          <p className="text-xs leading-relaxed text-muted-foreground">
            Personalize your message with special offers or trial memberships to increase conversions.
          </p>
        </div>
      </Card>
    </div>
  );
}
