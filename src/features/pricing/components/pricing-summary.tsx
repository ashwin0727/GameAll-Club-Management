import { Card } from "@/components/ui/card";
import { formatCurrency, toMinorUnits, PRICING_UNIT_LABEL } from "@/features/pricing/money";
import type { PeriodDraft } from "@/features/pricing/components/types";
import { pluralizeLabel, type PlayingAreaLabel } from "@/features/courts-setup/constants";

const DAY_TYPE_LABEL: Record<PeriodDraft["dayType"], string> = {
  ALL_DAYS: "All days",
  WEEKDAYS: "Weekdays",
  WEEKENDS: "Weekends",
};

/** "05:00" -> "5:00 AM" */
function formatHour(hhmm: string): string {
  const [h, m] = hhmm.split(":");
  const hour24 = Number(h ?? 0);
  const hour12 = hour24 % 12 === 0 ? 12 : hour24 % 12;
  return `${hour12}:${(m ?? "00").padStart(2, "0")} ${hour24 < 12 ? "AM" : "PM"}`;
}

function periodWindowLabel(p: PeriodDraft): string {
  if (p.coversFullDay) return "Full day";
  return `${formatHour(p.startTime)} – ${formatHour(p.endTime)}`;
}

export function PricingSummary({
  entries,
  currency,
  totalPlayingAreas,
}: {
  entries: { sportName: string; areaLabel: PlayingAreaLabel; areaCount: number; periods: PeriodDraft[] }[];
  currency: string;
  totalPlayingAreas: number;
}) {
  const configuredCount = entries.filter((e) => e.periods.some((p) => p.amountInput)).length;

  return (
    <Card className="space-y-3 p-4 sm:p-5">
      <h3 className="text-sm font-semibold">Pricing Summary</h3>
      <div className="space-y-3">
        {entries.map((entry) => {
          const priced = entry.periods.filter((p) => p.amountInput);
          return (
            <div key={entry.sportName} className="space-y-1 text-sm">
              <div className="flex items-center justify-between">
                <span className="font-medium text-foreground">{entry.sportName}</span>
                <span className="text-muted-foreground">
                  {entry.areaCount} {pluralizeLabel(entry.areaLabel, entry.areaCount)}
                </span>
              </div>
              {priced.length === 0 ? (
                <p className="text-muted-foreground">Not set</p>
              ) : (
                <ul className="space-y-0.5">
                  {priced.map((p, i) => (
                    <li key={i} className="flex items-center justify-between text-muted-foreground">
                      <span>
                        {DAY_TYPE_LABEL[p.dayType]} · {periodWindowLabel(p)}
                      </span>
                      <span className="text-foreground">
                        {formatCurrency(toMinorUnits(p.amountInput, currency), currency)} {PRICING_UNIT_LABEL.PER_HOUR}
                      </span>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          );
        })}
      </div>
      <div className="border-t border-border pt-3 text-sm">
        <p className="text-muted-foreground">
          {entries.length} Sports · {totalPlayingAreas} Playing Areas · {configuredCount} priced
        </p>
      </div>
    </Card>
  );
}