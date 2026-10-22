import { fromMinorUnits } from "@/features/pricing/money";
import type { PricingDayType, PricingRule } from "@/features/pricing/types";

/** UI-only draft shape — amount stays a free-typed string until save, when it's converted to minor units. */
export interface PeriodDraft {
  dayType: PricingDayType;
  coversFullDay: boolean;
  startTime: string;
  endTime: string;
  amountInput: string;
}

export function defaultPeriod(amountInput = ""): PeriodDraft {
  return { dayType: "ALL_DAYS", coversFullDay: true, startTime: "06:00", endTime: "23:00", amountInput };
}

/** Deep-clones a period list — used by "Copy pricing" and "Customize" so the
 * copy is independent and editing one side never mutates the other. */
export function clonePeriods(periods: PeriodDraft[]): PeriodDraft[] {
  return periods.map((p) => ({ ...p }));
}

/** Saved rules as editable/displayable periods, one per rule. */
export function rulesToPeriods(rules: PricingRule[], currency: string): PeriodDraft[] {
  return rules.map((r) => ({
    dayType: r.dayType,
    coversFullDay: r.coversFullDay,
    startTime: r.startTime ?? "06:00",
    endTime: r.endTime ?? "23:00",
    amountInput: String(fromMinorUnits(r.amountMinor, currency)),
  }));
}
