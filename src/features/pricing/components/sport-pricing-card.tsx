"use client";

import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { PricingPeriodsEditor } from "@/features/pricing/components/pricing-periods-editor";
import type { PeriodDraft } from "@/features/pricing/components/types";
import type { PlayingArea } from "@/features/courts-setup/types";
import { pluralizeLabel, type PlayingAreaLabel } from "@/features/courts-setup/constants";

export interface OverrideDraft {
  active: boolean;
  periods: PeriodDraft[];
  advancedEnabled: boolean;
  errors: string[];
}

export function SportPricingCard({
  sportName,
  sportIcon,
  areaLabel,
  playingAreas,
  currency,
  periods,
  advancedEnabled,
  errors,
  customizeAreas,
  overrides,
  onChangePeriods,
  onToggleAdvanced,
  onToggleCustomizeAreas,
  onCustomizeArea,
  onUseDefaultForArea,
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
  customizeAreas: boolean;
  overrides: Record<string, OverrideDraft>;
  onChangePeriods: (periods: PeriodDraft[]) => void;
  onToggleAdvanced: (enabled: boolean) => void;
  onToggleCustomizeAreas: (enabled: boolean) => void;
  onCustomizeArea: (areaId: string) => void;
  onUseDefaultForArea: (areaId: string) => void;
  onOverrideChange: (areaId: string, periods: PeriodDraft[]) => void;
  onOverrideToggleAdvanced: (areaId: string, enabled: boolean) => void;
  onCopyRequest: () => void;
}) {
  return (
    <Card className="space-y-4 p-5">
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <span className="text-xl" aria-hidden="true">
            {sportIcon}
          </span>
          <h2 className="text-sm font-semibold">{sportName}</h2>
        </div>
        <Button type="button" variant="ghost" size="sm" className="h-8 px-2 text-xs" onClick={onCopyRequest}>
          Copy pricing
        </Button>
      </div>

      <PricingPeriodsEditor
        periods={periods}
        advancedEnabled={advancedEnabled}
        currency={currency}
        errors={errors}
        onChangePeriods={onChangePeriods}
        onToggleAdvanced={onToggleAdvanced}
      />

      <p className="text-xs text-muted-foreground">
        {playingAreas.length} {pluralizeLabel(areaLabel, playingAreas.length)}
      </p>

      <button
        type="button"
        role="checkbox"
        aria-checked={customizeAreas}
        onClick={() => onToggleCustomizeAreas(!customizeAreas)}
        className="text-xs font-medium text-primary underline underline-offset-2"
      >
        {customizeAreas ? "Hide individual pricing" : `Customize individual ${areaLabel.toLowerCase()} pricing →`}
      </button>

      {customizeAreas && (
        <div className="space-y-2 border-t border-border pt-3">
          {playingAreas.map((area) => {
            const override = overrides[area.id];
            const isCustom = override?.active ?? false;
            return (
              <div key={area.id} className="space-y-2 rounded-lg border border-border p-3">
                <div className="flex items-center justify-between gap-3">
                  <span className="text-sm font-medium">{area.name}</span>
                  {isCustom ? (
                    <Button type="button" variant="ghost" size="sm" className="h-8 px-2 text-xs" onClick={() => onUseDefaultForArea(area.id)}>
                      Use sport default
                    </Button>
                  ) : (
                    <Button type="button" variant="outline" size="sm" className="h-8 px-2 text-xs" onClick={() => onCustomizeArea(area.id)}>
                      Customize
                    </Button>
                  )}
                </div>
                {!isCustom && <p className="text-xs text-muted-foreground">Uses default ✓</p>}
                {isCustom && override && (
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