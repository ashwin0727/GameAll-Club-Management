import type { DayOfWeek, OperatingDay } from "@/features/operating-hours/types";
import type { PricingRule } from "@/features/pricing/types";

const TIME_RE = /^([01]\d|2[0-3]):([0-5]\d)$/;

function toMinutes(time: string): number {
  const [h, m] = time.split(":").map(Number);
  return (h ?? 0) * 60 + (m ?? 0);
}

export function validatePriceAmount(amountMinor: number): string | null {
  if (!Number.isInteger(amountMinor)) return "Enter a valid amount.";
  if (amountMinor <= 0) return "Amount must be greater than 0.";
  return null;
}

export function validatePricingRule(rule: Pick<PricingRule, "coversFullDay" | "startTime" | "endTime" | "amountMinor">): string | null {
  const amountError = validatePriceAmount(rule.amountMinor);
  if (amountError) return amountError;

  if (rule.coversFullDay) return null;

  if (!rule.startTime || !TIME_RE.test(rule.startTime)) return "Start time is required.";
  if (!rule.endTime || !TIME_RE.test(rule.endTime)) return "End time is required.";
  if (rule.startTime === rule.endTime) return "Start and end time cannot be the same.";
  return null;
}

/** Scope key: rules only need to avoid overlapping other rules in the same sport/area + day-type bucket. */
function scopeKey(rule: Pick<PricingRule, "facilitySportId" | "playingAreaId" | "dayType">): string {
  return `${rule.facilitySportId}|${rule.playingAreaId ?? ""}|${rule.dayType}`;
}

export function hasOverlappingPricingPeriods(
  rules: Pick<PricingRule, "facilitySportId" | "playingAreaId" | "dayType" | "coversFullDay" | "startTime" | "endTime">[],
): boolean {
  const byScope = new Map<string, { start: number; end: number }[]>();
  for (const rule of rules) {
    if (rule.coversFullDay || !rule.startTime || !rule.endTime) continue;
    const key = scopeKey(rule);
    const list = byScope.get(key) ?? [];
    list.push({ start: toMinutes(rule.startTime), end: toMinutes(rule.endTime) });
    byScope.set(key, list);
  }

  for (const intervals of byScope.values()) {
    for (let i = 0; i < intervals.length; i++) {
      for (let j = i + 1; j < intervals.length; j++) {
        const a = intervals[i]!;
        const b = intervals[j]!;
        if (a.start < b.end && b.start < a.end) return true;
      }
    }
  }
  return false;
}

/** Which days of week a PricingDayType covers, for the operating-hours compatibility check. */
function dayNumbersFor(dayType: PricingRule["dayType"]): DayOfWeek[] {
  if (dayType === "WEEKDAYS") return [1, 2, 3, 4, 5];
  if (dayType === "WEEKENDS") return [0, 6];
  return [0, 1, 2, 3, 4, 5, 6];
}

function windowFitsSlot(
  rule: Pick<PricingRule, "startTime" | "endTime">,
  slot: { startTime: string; endTime: string },
): boolean {
  const ruleStart = toMinutes(rule.startTime!);
  let ruleEnd = toMinutes(rule.endTime!);
  if (ruleEnd <= ruleStart) ruleEnd += 24 * 60;

  const slotStart = toMinutes(slot.startTime);
  let slotEnd = toMinutes(slot.endTime);
  if (slotEnd <= slotStart) slotEnd += 24 * 60;

  return ruleStart >= slotStart && ruleEnd <= slotEnd;
}

/**
 * A pricing window must fall within at least one operating-hours slot on
 * every day it applies to (a full-day rule just needs the facility to be
 * open at all that day). Returns a friendly message, or null if compatible.
 */
export function validatePricingAgainstOperatingHours(
  rule: Pick<PricingRule, "dayType" | "coversFullDay" | "startTime" | "endTime">,
  operatingDays: OperatingDay[],
): string | null {
  const days = dayNumbersFor(rule.dayType);

  for (const dow of days) {
    const day = operatingDays.find((d) => d.dayOfWeek === dow);
    if (!day || day.isClosed) {
      return "This pricing period falls on a day the facility is closed.";
    }
    if (day.is24Hours) continue;
    if (rule.coversFullDay) {
      if (day.slots.length === 0) return "This pricing period falls on a day the facility is closed.";
      continue;
    }
    const fits = day.slots.some((slot) => windowFitsSlot(rule, slot));
    if (!fits) return "Pricing hours must fall within your facility's operating hours.";
  }
  return null;
}

export interface PricingValidationResult {
  isValid: boolean;
  ruleErrors: string[];
  overlapError: string | null;
}

export function validatePricingRules(
  rules: (Pick<PricingRule, "facilitySportId" | "playingAreaId" | "dayType" | "coversFullDay" | "startTime" | "endTime" | "amountMinor">)[],
  operatingDays?: OperatingDay[],
): PricingValidationResult {
  const ruleErrors: string[] = [];
  for (const rule of rules) {
    const error = validatePricingRule(rule);
    if (error) ruleErrors.push(error);
    if (!error && operatingDays) {
      const compatError = validatePricingAgainstOperatingHours(rule, operatingDays);
      if (compatError) ruleErrors.push(compatError);
    }
  }

  const overlapError = hasOverlappingPricingPeriods(rules) ? "Pricing periods cannot overlap." : null;

  return { isValid: ruleErrors.length === 0 && !overlapError, ruleErrors, overlapError };
}

/**
 * Resolves the applicable rule for a given facility sport / playing area /
 * date+time, following the priority playing-area rule > sport rule > none.
 * Pure and reusable — this is what Bookings/Memberships/Guest/Reports will
 * eventually call.
 */
export function resolvePrice(
  rules: PricingRule[],
  facilitySportId: string,
  playingAreaId: string | null,
  date: Date,
  time: string,
): PricingRule | null {
  const dow = date.getDay() as DayOfWeek;
  const isWeekend = dow === 0 || dow === 6;
  const minutes = toMinutes(time);

  function matches(rule: PricingRule): boolean {
    if (rule.facilitySportId !== facilitySportId) return false;
    if (rule.dayType === "WEEKDAYS" && isWeekend) return false;
    if (rule.dayType === "WEEKENDS" && !isWeekend) return false;
    if (rule.coversFullDay) return true;
    if (!rule.startTime || !rule.endTime) return false;
    const start = toMinutes(rule.startTime);
    let end = toMinutes(rule.endTime);
    if (end <= start) end += 24 * 60;
    let t = minutes;
    if (t < start) t += 24 * 60;
    return t >= start && t < end;
  }

  // A more specific rule wins over a broader one at the same priority: a
  // day-scoped rule (WEEKDAYS/WEEKENDS) beats ALL_DAYS, and a time-windowed
  // rule beats a full-day one. So an "all days ₹300" base with a "weekends
  // 6-9pm ₹350" override resolves to ₹350 inside that window.
  const specificity = (r: PricingRule) => (r.coversFullDay ? 0 : 2) + (r.dayType === "ALL_DAYS" ? 0 : 1);
  const pick = (a: PricingRule, b: PricingRule) => b.priority - a.priority || specificity(b) - specificity(a);

  const areaRules = playingAreaId ? rules.filter((r) => r.playingAreaId === playingAreaId && matches(r)) : [];
  if (areaRules.length > 0) return areaRules.sort(pick)[0]!;

  const sportRules = rules.filter((r) => !r.playingAreaId && matches(r));
  if (sportRules.length > 0) return sportRules.sort(pick)[0]!;

  return null;
}