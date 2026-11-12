import { DISPLAY_ORDER, DEFAULT_CLOSE_TIME, DEFAULT_OPEN_TIME } from "@/features/operating-hours/constants";
import type { DayOfWeek, FacilityClosure, OperatingDay, OperatingTimeSlot } from "@/features/operating-hours/types";
import { DAYS_OF_WEEK } from "@/features/operating-hours/types";
import { isOvernightSlot } from "@/features/operating-hours/validation";

/**
 * The Operating Hours step edits one simple plan per day — open or closed, from one time to another — and turns it into the
 * schedule the database stores (a day with one time slot, or two when there is a daily break). These helpers are pure so the same
 * rules can be tested without the screen.
 */

export type HoursMode = "standard" | "custom";

export interface DayPlan {
  dayOfWeek: DayOfWeek;
  isOpen: boolean;
  /** "HH:MM" (24-hour). */
  open: string;
  close: string;
  /** Open all day (no times). */
  is24Hours: boolean;
}

export interface BreakTime {
  start: string;
  end: string;
}

export const SHORT_DAY: Record<DayOfWeek, string> = { 0: "Sun", 1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat" };

export function toMinutes(time: string): number {
  const [h, m] = time.split(":").map(Number);
  return (h ?? 0) * 60 + (m ?? 0);
}

export function fromMinutes(total: number): string {
  const t = ((total % 1440) + 1440) % 1440;
  return `${String(Math.floor(t / 60)).padStart(2, "0")}:${String(t % 60).padStart(2, "0")}`;
}

/** "6:00 AM" */
export function formatClock(time: string): string {
  const [h, m] = time.split(":").map(Number);
  const hour = h ?? 0;
  return `${hour % 12 === 0 ? 12 : hour % 12}:${String(m ?? 0).padStart(2, "0")} ${hour < 12 ? "AM" : "PM"}`;
}

/** Every half hour of the day, the way the pickers list them. */
export const TIME_OPTIONS: { value: string; label: string }[] = Array.from({ length: 48 }, (_, i) => {
  const value = fromMinutes(i * 30);
  return { value, label: formatClock(value) };
});

export function defaultPlan(dayOfWeek: DayOfWeek, isOpen = true): DayPlan {
  return { dayOfWeek, isOpen, open: DEFAULT_OPEN_TIME, close: DEFAULT_CLOSE_TIME, is24Hours: false };
}

/** A new venue starts open Monday to Saturday, 6 AM to 11 PM, closed on Sunday (the design's example). */
export function defaultPlans(): DayPlan[] {
  return DAYS_OF_WEEK.map((d) => defaultPlan(d, d !== 0));
}

export function orderedPlans(plans: DayPlan[]): DayPlan[] {
  return DISPLAY_ORDER.map((d) => plans.find((p) => p.dayOfWeek === d)).filter((p): p is DayPlan => Boolean(p));
}

/** Minutes from [from] forward to [to] around the clock (a close at or before the open lands the next day). */
function span(from: string, to: string): number {
  const d = toMinutes(to) - toMinutes(from);
  return d > 0 ? d : d + 1440;
}

/** Whether the break sits inside a day's working hours (so it can split them into two slots). */
export function breakFitsDay(plan: Pick<DayPlan, "open" | "close">, brk: BreakTime): boolean {
  const total = span(plan.open, plan.close);
  const from = (toMinutes(brk.start) - toMinutes(plan.open) + 1440) % 1440;
  const to = from + span(brk.start, brk.end);
  return from > 0 && to < total;
}

// ── schedule <-> plans ───────────────────────────────────────────────────

function sameBreakPattern(day: OperatingDay, brk: BreakTime): boolean {
  if (day.slots.length !== 2) return false;
  const [a, b] = day.slots as [OperatingTimeSlot, OperatingTimeSlot];
  return a.endTime === brk.start && b.startTime === brk.end;
}

/** Reads the stored schedule back as plans (a daily break, when present, is folded back into one span). */
export function plansFromSchedule(days: OperatingDay[], brk?: BreakTime | null): DayPlan[] {
  return DAYS_OF_WEEK.map((d) => {
    const day = days.find((x) => x.dayOfWeek === d);
    if (!day) return defaultPlan(d, false);
    if (day.isClosed || (!day.is24Hours && day.slots.length === 0)) return { ...defaultPlan(d, false) };
    if (day.is24Hours) return { dayOfWeek: d, isOpen: true, open: DEFAULT_OPEN_TIME, close: DEFAULT_CLOSE_TIME, is24Hours: true };
    const slots = day.slots;
    const first = slots[0]!;
    const last = slots[slots.length - 1]!;
    if (brk && sameBreakPattern(day, brk)) return { dayOfWeek: d, isOpen: true, open: first.startTime, close: last.endTime, is24Hours: false };
    return { dayOfWeek: d, isOpen: true, open: first.startTime, close: last.endTime, is24Hours: false };
  });
}

/** Turns the plans (and the optional daily break) into the schedule that is stored. */
export function scheduleFromPlans(plans: DayPlan[], brk?: BreakTime | null): OperatingDay[] {
  return DAYS_OF_WEEK.map((d) => {
    const plan = plans.find((p) => p.dayOfWeek === d) ?? defaultPlan(d, false);
    if (!plan.isOpen) return { dayOfWeek: d, isClosed: true, is24Hours: false, slots: [] };
    if (plan.is24Hours) return { dayOfWeek: d, isClosed: false, is24Hours: true, slots: [] };

    const slot = (start: string, end: string, order: number): OperatingTimeSlot => ({
      startTime: start,
      endTime: end,
      crossesMidnight: isOvernightSlot({ startTime: start, endTime: end }),
      displayOrder: order,
    });
    if (brk && breakFitsDay(plan, brk)) {
      return { dayOfWeek: d, isClosed: false, is24Hours: false, slots: [slot(plan.open, brk.start, 0), slot(brk.end, plan.close, 1)] };
    }
    return { dayOfWeek: d, isClosed: false, is24Hours: false, slots: [slot(plan.open, plan.close, 0)] };
  });
}

/** Standard when every open day shares the same hours (the simple case), otherwise custom. */
export function detectMode(plans: DayPlan[]): HoursMode {
  const open = plans.filter((p) => p.isOpen);
  if (open.length === 0) return "standard";
  const key = (p: DayPlan) => (p.is24Hours ? "24h" : `${p.open}-${p.close}`);
  return open.every((p) => key(p) === key(open[0]!)) ? "standard" : "custom";
}

/** Standard mode: the chosen days all get the same hours; the others are closed. */
export function applyStandard(openDays: DayOfWeek[], open: string, close: string, is24Hours = false): DayPlan[] {
  return DAYS_OF_WEEK.map((d) => ({ dayOfWeek: d, isOpen: openDays.includes(d), open, close, is24Hours }));
}

// ── hours ────────────────────────────────────────────────────────────────

/** Working hours in a day, minus the break when it falls inside them. */
export function dailyMinutes(plan: DayPlan, brk?: BreakTime | null): number {
  if (!plan.isOpen) return 0;
  if (plan.is24Hours) return 1440;
  const total = span(plan.open, plan.close);
  return brk && breakFitsDay(plan, brk) ? total - span(brk.start, brk.end) : total;
}

export function weeklyMinutes(plans: DayPlan[], brk?: BreakTime | null): number {
  return plans.reduce((sum, p) => sum + dailyMinutes(p, brk), 0);
}

/** "17 Hours", "1 Hour", "17.5 Hours" */
export function formatHours(minutes: number): string {
  const hours = Math.round((minutes / 60) * 10) / 10;
  return `${Number.isInteger(hours) ? hours : hours.toFixed(1)} ${hours === 1 ? "Hour" : "Hours"}`;
}

/** "6:00 AM – 11:00 PM", with "(next day)" when it closes after midnight. */
export function describePlan(plan: DayPlan): string {
  if (!plan.isOpen) return "Closed";
  if (plan.is24Hours) return "Open 24 hours";
  const next = toMinutes(plan.close) <= toMinutes(plan.open) ? " (next day)" : "";
  return `${formatClock(plan.open)} – ${formatClock(plan.close)}${next}`;
}

// ── validation ───────────────────────────────────────────────────────────

export interface PlanProblems {
  /** the whole step: no day open */
  general?: string;
  byDay: Partial<Record<DayOfWeek, string>>;
  breakTime?: string;
}

export function validatePlans(plans: DayPlan[], brk?: BreakTime | null): PlanProblems {
  const byDay: PlanProblems["byDay"] = {};
  const open = plans.filter((p) => p.isOpen);
  const problems: PlanProblems = { byDay };
  if (open.length === 0) problems.general = "Select at least one operating day.";

  for (const p of open) {
    if (p.is24Hours) continue;
    if (!p.open || !p.close) byDay[p.dayOfWeek] = "Select opening and closing time.";
    else if (p.open === p.close) byDay[p.dayOfWeek] = "Opening and closing time cannot be the same.";
  }

  if (brk) {
    if (!brk.start || !brk.end) problems.breakTime = "Select the break's start and end time.";
    else if (brk.start === brk.end) problems.breakTime = "The break's start and end time cannot be the same.";
    else {
      const timed = open.filter((p) => !p.is24Hours && p.open !== p.close);
      if (timed.length > 0 && timed.some((p) => !breakFitsDay(p, brk))) {
        problems.breakTime = "The break must fall inside the working hours of every open day.";
      }
    }
  }
  return problems;
}

export function hasProblems(p: PlanProblems): boolean {
  return Boolean(p.general) || Boolean(p.breakTime) || Object.keys(p.byDay).length > 0;
}

/** "15 Aug 2026 (Sat)" */
export function formatClosureDate(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  const date = new Date(y ?? 1970, (m ?? 1) - 1, d ?? 1);
  const month = date.toLocaleString("en-GB", { month: "short" });
  const weekday = date.toLocaleString("en-GB", { weekday: "short" });
  return `${String(d).padStart(2, "0")} ${month} ${y} (${weekday})`;
}

/** What is wrong with a closure about to be added or saved (null when it is fine). [today] is "yyyy-MM-dd". */
export function closureProblem(
  closure: FacilityClosure,
  others: FacilityClosure[],
  today: string,
  editing?: FacilityClosure | null,
): string | null {
  if (!closure.date) return "Select a date.";
  if (!/^\d{4}-\d{2}-\d{2}$/.test(closure.date)) return "Select a valid date.";
  if (closure.date < today && closure.date !== editing?.date) return "Choose today or a future date.";
  const name = closure.name.trim();
  if (name.length < 2) return "Enter a name of at least 2 characters.";
  if (name.length > 60) return "Keep the name under 60 characters.";
  if (others.some((c) => c.date === closure.date && c !== editing)) return "This date is already marked as closed.";
  return null;
}

export function sortClosures(closures: FacilityClosure[]): FacilityClosure[] {
  return [...closures].sort((a, b) => a.date.localeCompare(b.date));
}
