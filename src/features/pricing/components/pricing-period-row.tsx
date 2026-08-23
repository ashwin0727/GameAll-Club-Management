"use client";

import { Button } from "@/components/ui/button";
import { AmountInput } from "@/features/pricing/components/amount-input";
import type { PeriodDraft } from "@/features/pricing/components/types";
import { TimeSelect } from "@/features/operating-hours/components/time-select";
import { PRICING_UNIT_LABEL } from "@/features/pricing/money";
import { cn } from "@/lib/utils";

const DAY_TYPE_OPTIONS: { value: PeriodDraft["dayType"]; label: string }[] = [
  { value: "ALL_DAYS", label: "All days" },
  { value: "WEEKDAYS", label: "Weekdays" },
  { value: "WEEKENDS", label: "Weekends" },
];

export function PricingPeriodRow({
  period,
  currency,
  canRemove,
  error,
  onChange,
  onRemove,
}: {
  period: PeriodDraft;
  currency: string;
  canRemove: boolean;
  error?: string;
  onChange: (period: PeriodDraft) => void;
  onRemove: () => void;
}) {
  return (
    <div className="space-y-2 rounded-lg border border-border p-3">
      <div className="flex items-center gap-2">
        <select
          aria-label="Applies to"
          value={period.dayType}
          onChange={(e) => onChange({ ...period, dayType: e.target.value as PeriodDraft["dayType"] })}
          className="h-11 flex-1 rounded-md border border-input bg-secondary/60 px-2 text-sm"
        >
          {DAY_TYPE_OPTIONS.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </select>

        <button
          type="button"
          role="checkbox"
          aria-checked={!period.coversFullDay}
          onClick={() => onChange({ ...period, coversFullDay: !period.coversFullDay })}
          className={cn(
            "flex h-11 shrink-0 items-center justify-center rounded-md border px-3 text-xs font-medium",
            !period.coversFullDay ? "border-primary bg-primary/10 text-primary" : "border-input text-muted-foreground",
          )}
        >
          {period.coversFullDay ? "Full day" : "Time window"}
        </button>
      </div>

      {!period.coversFullDay && (
        <div className="grid grid-cols-2 gap-2">
          <TimeSelect aria-label="Period start time" value={period.startTime} onChange={(v) => onChange({ ...period, startTime: v })} />
          <TimeSelect aria-label="Period end time" value={period.endTime} onChange={(v) => onChange({ ...period, endTime: v })} />
        </div>
      )}

      <div className="flex items-center gap-2">
        <div className="flex-1">
          <AmountInput
            aria-label="Rate"
            value={period.amountInput}
            onChange={(v) => onChange({ ...period, amountInput: v })}
            currency={currency}
            unitLabel={PRICING_UNIT_LABEL.PER_HOUR!}
          />
        </div>
        {canRemove && (
          <Button type="button" variant="ghost" size="sm" className="h-9 shrink-0 px-2 text-xs text-destructive" onClick={onRemove}>
            Remove
          </Button>
        )}
      </div>

      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  );
}