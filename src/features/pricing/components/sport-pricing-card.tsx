"use client";

import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { PricingPeriodsEditor } from "@/features/pricing/components/pricing-periods-editor";
import type { PeriodDraft } from "@/features/pricing/components/types";
import type { PlayingArea } from "@/features/courts-setup/types";
import { pluralizeLabel, type PlayingAreaLabel } from "@/features/courts-setup/constants";
import { cn } from "@/lib/utils";

export interface OverrideDraft {
  active: boolean;
  periods: PeriodDraft[];
  advancedEnabled: boolean;
  errors: string[];
}

/**
 * One sport's pricing. The owner first chooses how the sport is priced:
 *  - Default rate: one rate that every court / turf of the sport charges.
 *  - Individual rate: each court / turf has its own rate, and there is no sport-wide default to fill in.
 * Only the chosen mode's fields are shown and collected.
 */
export function SportPricingCard({
  sportName,
  sportIcon,
  areaLabel,
  playingAreas,
  currency,
  periods,
  advancedEnabled,
  errors,
  individualPricing,
  overrides,
  onChangePeriods,
  onToggleAdvanced,
  onChangePricingMode,
  onOverrideChange,
  onOverrideToggleAdvanced,
  onCopyRequest,
}: {
  sportName: string;
  sportIcon: string;
  areaLabel: PlayingAreaLabel;
  playingAreas: PlayingArea[];
  currency: string;
  periods: PeriodDraft[];
  advancedEnabled: boolean;
  errors?: string[];
  individualPricing: boolean;
  overrides: Record<string, OverrideDraft>;
  onChangePeriods: (periods: PeriodDraft[]) => void;
  onToggleAdvanced: (enabled: boolean) => void;
  onChangePricingMode: (individual: boolean) => void;
  onOverrideChange: (areaId: string, periods: PeriodDraft[]) => void;
  onOverrideToggleAdvanced: (areaId: string, enabled: boolean) => void;
  onCopyRequest: () => void;
}) {
  const noun = areaLabel.toLowerCase();
  const modes = [
    { individual: false, title: "Default rate", hint: `One rate for every ${noun}` },
    { individual: true, title: "Individual rate", hint: `A different rate for each ${noun}` },
  ];

  return (
    <Card className="space-y-4 p-5">
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <span className="text-xl" aria-hidden="true">
            {sportIcon}
          </span>
          <h2 className="text-sm font-semibold">{sportName}</h2>
        </div>
        {!individualPricing && (
          <Button type="button" variant="ghost" size="sm" className="h-8 px-2 text-xs" onClick={onCopyRequest}>
            Copy Pricing
          </Button>
        )}
      </div>

      <div role="radiogroup" aria-label={`How do you price ${sportName}?`} className="grid grid-cols-2 gap-1 rounded-lg bg-muted p-1">
        {modes.map((m) => {
          const selected = individualPricing === m.individual;
          return (
            <button
              key={m.title}
              type="button"
              role="radio"
              aria-checked={selected}
              onClick={() => !selected && onChangePricingMode(m.individual)}
              className={cn(
                "rounded-md px-3 py-2 text-left outline-none transition-colors focus-visible:ring-2 focus-visible:ring-ring",
                selected ? "bg-card shadow-sm" : "text-muted-foreground hover:text-foreground",
              )}
            >
              <span className="block text-sm font-medium">{m.title}</span>
              <span className="block text-[11px] text-muted-foreground">{m.hint}</span>
            </button>
          );
        })}
      </div>

      {!individualPricing ? (
        <>
          <PricingPeriodsEditor
            periods={periods}
            advancedEnabled={advancedEnabled}
            currency={currency}
            errors={errors}
            onChangePeriods={onChangePeriods}
            onToggleAdvanced={onToggleAdvanced}
          />
          <p className="text-xs text-muted-foreground">
            Applies to all {playingAreas.length} {pluralizeLabel(areaLabel, playingAreas.length)}
          </p>
        </>
      ) : (
        <div className="space-y-3">
          {playingAreas.map((area) => {
            const override = overrides[area.id];
            return (
              <div key={area.id} className="space-y-2 rounded-lg border border-border p-3">
                <span className="text-sm font-medium">{area.name}</span>
                {override && (
                  <PricingPeriodsEditor
                    periods={override.periods}
                    advancedEnabled={override.advancedEnabled}
                    currency={currency}
                    errors={override.errors}
                    onChangePeriods={(next) => onOverrideChange(area.id, next)}
                    onToggleAdvanced={(enabled) => onOverrideToggleAdvanced(area.id, enabled)}
                  />
                )}
              </div>
            );
          })}
        </div>
      )}
    </Card>
  );
}
