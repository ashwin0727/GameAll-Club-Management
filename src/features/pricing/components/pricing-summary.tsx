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

/** A court's priced periods as one comparable string — two courts with the same string charge the same. */
function pricingSignature(periods: PeriodDraft[]): string {
  return periods
    .filter((p) => p.amountInput)
    .map((p) => `${p.dayType}|${p.coversFullDay ? "full" : `${p.startTime}-${p.endTime}`}|${Number(p.amountInput)}`)
    .sort()
    .join(";");
}

/**
 * Courts / turfs that charge exactly the same are shown once — "Court 1, Court 2, Court 3" with one price list —
 * instead of repeating the same lines for each. Order of first appearance is kept.
 */
export function groupCustomized(customized: { areaName: string; periods: PeriodDraft[] }[]): { areaNames: string[]; periods: PeriodDraft[] }[] {
  const groups = new Map<string, { areaNames: string[]; periods: PeriodDraft[] }>();
  for (const c of customized) {
    const key = pricingSignature(c.periods);
    const existing = groups.get(key);
    if (existing) existing.areaNames.push(c.areaName);
    else groups.set(key, { areaNames: [c.areaName], periods: c.periods });
  }
  return [...groups.values()];
}

function PeriodList({ periods, currency }: { periods: PeriodDraft[]; currency: string }) {
  return (
    <ul className="space-y-0.5">
      {periods.map((p, i) => (
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
  );
}

export function PricingSummary({
  entries,
  currency,
  totalPlayingAreas,
}: {
  entries: {
    sportName: string;
    areaLabel: PlayingAreaLabel;
    areaCount: number;
    periods: PeriodDraft[];
    /** Courts / turfs priced on their own, overriding the sport's rate. */
    customized?: { areaName: string; periods: PeriodDraft[] }[];
  }[];
  currency: string;
  totalPlayingAreas: number;
}) {
  const configuredCount = entries.filter((e) => e.periods.some((p) => p.amountInput) || (e.customized ?? []).some((c) => c.periods.some((p) => p.amountInput))).length;
  const customizedCount = entries.reduce((n, e) => n + (e.customized?.length ?? 0), 0);

  return (
    <Card className="space-y-3 p-4 sm:p-5">
      <h3 className="text-sm font-semibold">Pricing Summary</h3>
      <div className="space-y-3">
        {entries.map((entry) => {
          const priced = entry.periods.filter((p) => p.amountInput);
          const customized = entry.customized ?? [];
          // When every court has its own pricing, the sport's default rate applies to none of them.
          const allCustomized = entry.areaCount > 0 && customized.length >= entry.areaCount;
          return (
            <div key={entry.sportName} className="space-y-1 text-sm">
              <div className="flex items-center justify-between">
                <span className="font-medium text-foreground">{entry.sportName}</span>
                <span className="text-muted-foreground">
                  {entry.areaCount} {pluralizeLabel(entry.areaLabel, entry.areaCount)}
                </span>
              </div>
              {!allCustomized &&
                (priced.length === 0 ? (
                  <p className="text-muted-foreground">{customized.length > 0 ? "No default rate" : "Not set"}</p>
                ) : (
                  <PeriodList periods={priced} currency={currency} />
                ))}
              {groupCustomized(customized).map((g) => {
                const own = g.periods.filter((p) => p.amountInput);
                // Every court on the same price reads "All 3 Courts", not a list of names.
                const coversAll = allCustomized && g.areaNames.length === entry.areaCount && entry.areaCount > 1;
                const name = coversAll ? `All ${entry.areaCount} ${pluralizeLabel(entry.areaLabel, entry.areaCount)}` : g.areaNames.join(", ");
                return (
                  <div key={g.areaNames.join("|")} className={coversAll ? "space-y-0.5" : "mt-1.5 space-y-0.5 border-l-2 border-primary/30 pl-3"}>
                    <p className="text-xs font-medium text-foreground">{name}{coversAll ? "" : " · custom"}</p>
                    {own.length === 0 ? <p className="text-xs text-muted-foreground">Not set</p> : <PeriodList periods={own} currency={currency} />}
                  </div>
                );
              })}
            </div>
          );
        })}
      </div>
      <div className="border-t border-border pt-3 text-sm">
        <p className="text-muted-foreground">
          {entries.length} Sports · {totalPlayingAreas} Playing Areas · {configuredCount} priced
          {customizedCount > 0 ? ` · ${customizedCount} custom` : ""}
        </p>
      </div>
    </Card>
  );
}