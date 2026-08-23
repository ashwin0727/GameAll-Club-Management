import { Card } from "@/components/ui/card";
import { formatCurrency, toMinorUnits, PRICING_UNIT_LABEL } from "@/features/pricing/money";
import type { PeriodDraft } from "@/features/pricing/components/types";
import { pluralizeLabel, type PlayingAreaLabel } from "@/features/courts-setup/constants";

export function PricingSummary({
  entries,
  currency,
  totalPlayingAreas,
}: {
  entries: { sportName: string; areaLabel: PlayingAreaLabel; areaCount: number; defaultPeriod: PeriodDraft | undefined }[];
  currency: string;
  totalPlayingAreas: number;
}) {
  const configuredCount = entries.filter((e) => e.defaultPeriod?.amountInput).length;

  return (
    <Card className="space-y-3 p-4 sm:p-5">
      <h3 className="text-sm font-semibold">Pricing Summary</h3>
      <div className="space-y-2">
        {entries.map((entry) => (
          <div key={entry.sportName} className="flex items-center justify-between text-sm">
            <span className="font-medium text-foreground">{entry.sportName}</span>
            <span className="text-muted-foreground">
              {entry.defaultPeriod?.amountInput
                ? `${formatCurrency(toMinorUnits(entry.defaultPeriod.amountInput, currency), currency)} ${PRICING_UNIT_LABEL.PER_HOUR}`
                : "Not set"}
              {" · "}
              {entry.areaCount} {pluralizeLabel(entry.areaLabel, entry.areaCount)}
            </span>
          </div>
        ))}
      </div>
      <div className="border-t border-border pt-3 text-sm">
        <p className="text-muted-foreground">
          {entries.length} Sports · {totalPlayingAreas} Playing Areas · {configuredCount} priced
        </p>
      </div>
    </Card>
  );
}