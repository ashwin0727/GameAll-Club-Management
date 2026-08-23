"use client";

import { Button } from "@/components/ui/button";
import { AmountInput } from "@/features/pricing/components/amount-input";
import { PricingPeriodRow } from "@/features/pricing/components/pricing-period-row";
import { defaultPeriod, type PeriodDraft } from "@/features/pricing/components/types";
import { PRICING_UNIT_LABEL } from "@/features/pricing/money";

export function PricingPeriodsEditor({
  periods,
  advancedEnabled,
  currency,
  errors,
  onChangePeriods,
  onToggleAdvanced,
}: {
  periods: PeriodDraft[];
  advancedEnabled: boolean;
  currency: string;
  errors?: string[];
  onChangePeriods: (periods: PeriodDraft[]) => void;
  onToggleAdvanced: (enabled: boolean) => void;
}) {
  function updatePeriod(index: number, next: PeriodDraft) {
    onChangePeriods(periods.map((p, i) => (i === index ? next : p)));
  }

  function removePeriod(index: number) {
    if (periods.length <= 1) return;
    onChangePeriods(periods.filter((_, i) => i !== index));
  }

  function addPeriod() {
    onChangePeriods([...periods, defaultPeriod()]);
  }

  if (!advancedEnabled) {
    const first = periods[0] ?? defaultPeriod();
    return (
      <div className="space-y-2">
        <label className="text-xs font-medium text-muted-foreground">Default Rate</label>
        <AmountInput
          aria-label="Default rate"
          value={first.amountInput}
          onChange={(v) => onChangePeriods([{ ...first, amountInput: v }])}
          currency={currency}
          unitLabel={PRICING_UNIT_LABEL.PER_HOUR!}
        />
        {errors?.[0] && <p className="text-xs text-destructive">{errors[0]}</p>}
        <Button type="button" variant="ghost" size="sm" className="h-9 px-2 text-xs" onClick={() => onToggleAdvanced(true)}>
          Advanced pricing (weekday/weekend, peak hours) →
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      <p className="text-xs text-muted-foreground">
        Add a period for each day-type/time window that needs its own rate.
      </p>
      {periods.map((period, index) => (
        <PricingPeriodRow
          key={index}
          period={period}
          currency={currency}
          canRemove={periods.length > 1}
          error={errors?.[index]}
          onChange={(next) => updatePeriod(index, next)}
          onRemove={() => removePeriod(index)}
        />
      ))}
      <div className="flex flex-wrap gap-2">
        <Button type="button" variant="outline" size="sm" onClick={addPeriod}>
          + Add another period
        </Button>
        <Button
          type="button"
          variant="ghost"
          size="sm"
          className="text-xs"
          onClick={() => {
            onChangePeriods([periods[0] ?? defaultPeriod()].map((p) => ({ ...p, dayType: "ALL_DAYS", coversFullDay: true })));
            onToggleAdvanced(false);
          }}
        >
          Use simple pricing
        </Button>
      </div>
    </div>
  );
}