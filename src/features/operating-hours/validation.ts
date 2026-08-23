import type { DayOfWeek, OperatingDay, OperatingTimeSlot } from "@/features/operating-hours/types";

const TIME_RE = /^([01]\d|2[0-3]):([0-5]\d)$/;

/** "6:5" -> "06:05". Throws-free: returns the input unchanged if it isn't a recognizable time. */
export function normalizeTime(value: string): string {
  const trimmed = value.trim();
  const match = /^(\d{1,2}):(\d{1,2})$/.exec(trimmed);
  if (!match) return trimmed;
  const [, h, m] = match;
  return `${h!.padStart(2, "0")}:${m!.padStart(2, "0")}`;
}

function toMinutes(time: string): number {
  const [h, m] = time.split(":").map(Number);
  return (h ?? 0) * 60 + (m ?? 0);
}

/** A slot wraps past midnight when its end clock-time is not after its start. */
export function isOvernightSlot(slot: Pick<OperatingTimeSlot, "startTime" | "endTime">): boolean {
  return toMinutes(slot.endTime) <= toMinutes(slot.startTime);
}

export function sortTimeSlots<T extends Pick<OperatingTimeSlot, "startTime">>(slots: T[]): T[] {
  return [...slots].sort((a, b) => toMinutes(a.startTime) - toMinutes(b.startTime));
}

interface Interval {
  start: number;
  end: number;
}

function slotToInterval(slot: Pick<OperatingTimeSlot, "startTime" | "endTime">): Interval {
  const start = toMinutes(slot.startTime);
  let end = toMinutes(slot.endTime);
  if (end <= start) end += 24 * 60;
  return { start, end };
}

function intervalsOverlap(a: Interval, b: Interval): boolean {
  // Compare against the previous/next day's occurrence of b too, so an
  // overnight slot correctly collides with an early-morning slot the next
  // calendar day it actually spans into.
  for (const shift of [-1440, 0, 1440]) {
    const start = b.start + shift;
    const end = b.end + shift;
    if (a.start < end && start < a.end) return true;
  }
  return false;
}

export function hasOverlappingSlots(slots: Pick<OperatingTimeSlot, "startTime" | "endTime">[]): boolean {
  const intervals = slots.map(slotToInterval);
  for (let i = 0; i < intervals.length; i++) {
    for (let j = i + 1; j < intervals.length; j++) {
      if (intervalsOverlap(intervals[i]!, intervals[j]!)) return true;
    }
  }
  return false;
}

export function validateTimeSlot(slot: Pick<OperatingTimeSlot, "startTime" | "endTime">): string | null {
  if (!slot.startTime || !TIME_RE.test(slot.startTime)) return "Opening time is required.";
  if (!slot.endTime || !TIME_RE.test(slot.endTime)) return "Closing time is required.";
  if (slot.startTime === slot.endTime) return "Opening and closing time cannot be the same.";
  return null;
}

/** Returns a single user-facing message for the day, or null if it's valid. */
export function validateOperatingDay(day: Pick<OperatingDay, "isClosed" | "is24Hours" | "slots">): string | null {
  if (day.isClosed || day.is24Hours) return null;

  if (day.slots.length === 0) return "Add at least one time slot, or mark the day Closed.";

  for (const slot of day.slots) {
    const error = validateTimeSlot(slot);
    if (error) return error;
  }

  if (hasOverlappingSlots(day.slots)) return "Operating hours cannot overlap.";

  return null;
}

export interface ScheduleValidationResult {
  isValid: boolean;
  dayErrors: Partial<Record<DayOfWeek, string>>;
}

export function validateSchedule(days: OperatingDay[]): ScheduleValidationResult {
  const dayErrors: Partial<Record<DayOfWeek, string>> = {};
  for (const day of days) {
    const error = validateOperatingDay(day);
    if (error) dayErrors[day.dayOfWeek] = error;
  }
  return { isValid: Object.keys(dayErrors).length === 0, dayErrors };
}