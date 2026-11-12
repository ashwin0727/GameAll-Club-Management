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

type OverlapRule = Pick<PricingRule, "facilitySportId" | "playingAreaId" | "dayType" | "daysOfWeek" | "audience" | "coversFullDay" | "startTime" | "endTime">;

/** Two rules can clash when they are for the same sport / court, the same audience and the same day group. */
function sameBucket(a: OverlapRule, b: OverlapRule): boolean {
  if (a.facilitySportId !== b.facilitySportId) return false;
  if ((a.playingAreaId ?? "") !== (b.playingAreaId ?? "")) return false;
  if ((a.audience ?? "GENERAL") !== (b.audience ?? "GENERAL")) return false;
  if (a.dayType !== b.dayType) return false;
  if (a.dayType === "SPECIFIC_DAYS") return (a.daysOfWeek ?? []).some((d) => (b.daysOfWeek ?? []).includes(d));
  return true;
}

export function hasOverlappingPricingPeriods(rules: OverlapRule[]): boolean {
  const timed = rules.filter((r) => !r.coversFullDay && r.startTime && r.endTime);
  for (let i = 0; i < timed.length; i++) {
    for (let j = i + 1; j < timed.length; j++) {
      const a = timed[i]!;
      const b = timed[j]!;
      if (!sameBucket(a, b)) continue;
      const aStart = toMinutes(a.startTime!);
      const aEnd = toMinutes(a.endTime!);
      const bStart = toMinutes(b.startTime!);
      const bEnd = toMinutes(b.endTime!);
      if (aStart < bEnd && bStart < aEnd) return true;
    }
  }
  return false;
}

/** Which days of week a PricingDayType covers, for the operating-hours compatibility check. */
function dayNumbersFor(dayType: PricingRule["dayType"], days?: number[]): DayOfWeek[] {
  if (dayType === "SPECIFIC_DAYS") return (days ?? []) as DayOfWeek[];
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
  rule: Pick<PricingRule, "dayType" | "daysOfWeek" | "coversFullDay" | "startTime" | "endTime">,
  operatingDays: OperatingDay[],
): string | null {
  const days = dayNumbersFor(rule.dayType, rule.daysOfWeek);

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
    // a day with a daily break has two slots; a price window may run across the break (nothing can be booked in it), so compare with
    // the whole span from the first opening to the last closing
    const first = day.slots[0];
    const last = day.slots[day.slots.length - 1];
    const span = first && last && day.slots.length > 1 ? { startTime: first.startTime, endTime: last.endTime } : null;
    const fits = day.slots.some((slot) => windowFitsSlot(rule, slot)) || (span !== null && windowFitsSlot(rule, span));
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
  rules: (Pick<PricingRule, "facilitySportId" | "playingAreaId" | "dayType" | "daysOfWeek" | "audience" | "coversFullDay" | "startTime" | "endTime" | "amountMinor">)[],
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
    // only general rates set a booking price; member / coaching rates are stored for later
    if ((rule.audience ?? "GENERAL") !== "GENERAL") return false;
    if (rule.dayType === "SPECIFIC_DAYS" && !(rule.daysOfWeek ?? []).includes(dow)) return false;
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
  const specificity = (r: PricingRule) => (r.coversFullDay ? 0 : 3) + (r.dayType === "ALL_DAYS" ? 0 : r.dayType === "SPECIFIC_DAYS" ? 2 : 1);
  const pick = (a: PricingRule, b: PricingRule) => b.priority - a.priority || specificity(b) - specificity(a);

  const areaRules = playingAreaId ? rules.filter((r) => r.playingAreaId === playingAreaId && matches(r)) : [];
  if (areaRules.length > 0) return areaRules.sort(pick)[0]!;

  const sportRules = rules.filter((r) => !r.playingAreaId && matches(r));
  if (sportRules.length > 0) return sportRules.sort(pick)[0]!;

  return null;
}