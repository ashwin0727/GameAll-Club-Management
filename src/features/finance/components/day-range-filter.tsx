"use client";

import { useEffect, useState } from "react";
import { RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { currentMonthRange, isCurrentMonth, type DayRange } from "@/features/finance/day-range";

/**
 * Pick the dates to look at: a From and a To date, and an Apply button that loads them. The month on screen is the whole
 * current month until the user chooses otherwise; "This month" puts it back.
 *
 * Editing the dates changes only a draft — nothing reloads (and nothing exports) until Apply, so the list or figures on
 * screen always match the dates that were applied. [onDirtyChange] tells the page when there are dates not yet applied.
 */
export function DayRangeFilter({
  value,
  onApply,
  onDirtyChange,
  inline = false,
}: {
  /** The dates currently applied. */
  value: DayRange;
  onApply: (next: DayRange) => void;
  onDirtyChange?: (dirty: boolean) => void;
  /**
   * For a filter bar whose neighbours are full-height (44px) fields under their own heading: "From" and "To" sit beside
   * their fields and everything is the same height and centred on one line, instead of stacking a label over each date.
   */
  inline?: boolean;
}) {
  const [draft, setDraft] = useState<DayRange>(value);

  // The page can change the applied dates itself (Reset): follow it.
  useEffect(() => setDraft(value), [value]);

  const dirty = draft.from !== value.from || draft.to !== value.to;
  const valid = Boolean(draft.from) && Boolean(draft.to) && draft.from <= draft.to;

  useEffect(() => onDirtyChange?.(dirty), [dirty, onDirtyChange]);

  const field = inline ? "h-11 w-[150px] rounded-xl px-3 text-sm text-foreground" : "h-9 w-[150px] text-sm text-foreground";
  const button = inline ? "h-11 rounded-xl" : "min-h-9";
  const Wrap = inline ? "div" : "label";
  const wrapClass = inline ? "flex items-center gap-2 text-xs font-medium text-muted-foreground" : "space-y-1 text-xs font-medium text-muted-foreground";

  return (
    <div className="space-y-1.5">
      <div className={inline ? "flex flex-wrap items-center gap-2" : "flex flex-wrap items-end gap-2"}>
        <Wrap className={wrapClass}>
          <span>From</span>
          <Input
            type="date"
            aria-label="From date"
            value={draft.from}
            onChange={(e) => setDraft((d) => ({ from: e.target.value, to: e.target.value && d.to && e.target.value > d.to ? e.target.value : d.to }))}
            className={field}
          />
        </Wrap>
        <Wrap className={wrapClass}>
          <span>To</span>
          <Input
            type="date"
            aria-label="To date"
            value={draft.to}
            onChange={(e) => setDraft((d) => ({ to: e.target.value, from: e.target.value && d.from && e.target.value < d.from ? e.target.value : d.from }))}
            className={field}
          />
        </Wrap>
        <Button type="button" size="sm" className={button} disabled={!dirty || !valid} onClick={() => onApply(draft)}>
          <RefreshCw className="h-4 w-4" aria-hidden /> Apply
        </Button>
        {(!isCurrentMonth(value) || dirty) && (
          <Button type="button" variant="ghost" size="sm" className={button} onClick={() => onApply(currentMonthRange())}>
            This month
          </Button>
        )}
      </div>
      {dirty && valid && <p className="text-xs text-muted-foreground">Press Apply to load these dates.</p>}
      {dirty && !valid && <p className="text-xs text-destructive">The start date must be on or before the end date.</p>}
    </div>
  );
}
