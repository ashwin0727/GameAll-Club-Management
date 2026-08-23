import type { PricingDayType } from "@/features/pricing/types";

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