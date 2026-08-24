import type { OperatingDay } from "@/features/operating-hours/types";
import type { TimeSlot } from "@/features/bookings/types";

/**
 * Splits a day's open windows into fixed-size candidate slots and flags each
 * as available/unavailable against existing bookings. Operates on wall-clock
 * time for the given calendar `date` — same simplification the rest of the
 * operating-hours feature already makes (browser-local ≈ facility-local),
 * and matches the backend's own same-local-day restriction on bookings.
 */
export function computeAvailableSlots(
  date: Date,
  day: OperatingDay,
  existingBookings: { startTime: string; endTime: string }[],
  slotMinutes = 60,
): TimeSlot[] {
  const windows = windowsForDay(day);
  const slots: TimeSlot[] = [];

  for (const window of windows) {
    for (let start = window.startMin; start + slotMinutes <= window.endMin; start += slotMinutes) {
      const end = start + slotMinutes;
      const startTime = atMinutes(date, start);
      const endTime = atMinutes(date, end);
      const available = !existingBookings.some((b) => rangesOverlap(startTime, endTime, new Date(b.startTime), new Date(b.endTime)));
      slots.push({ startTime: startTime.toISOString(), endTime: endTime.toISOString(), available });
    }
  }

  return slots;
}

interface Window {
  startMin: number;
  endMin: number;
}

/** Windows are capped at end-of-day (1440) — bookings may not cross a local calendar day (see 0007_bookings.sql). */
function windowsForDay(day: OperatingDay): Window[] {
  if (day.isClosed) return [];
  if (day.is24Hours) return [{ startMin: 0, endMin: 1440 }];

  return day.slots.map((slot) => {
    const start = toMinutes(slot.startTime);
    let end = toMinutes(slot.endTime);
    if (slot.crossesMidnight || end <= start) end += 1440;
    return { startMin: start, endMin: Math.min(end, 1440) };
  });
}

function toMinutes(time: string): number {
  const [h, m] = time.split(":").map(Number);
  return (h ?? 0) * 60 + (m ?? 0);
}

function atMinutes(date: Date, minutes: number): Date {
  const result = new Date(date);
  result.setHours(0, 0, 0, 0);
  result.setMinutes(minutes);
  return result;
}

function rangesOverlap(aStart: Date, aEnd: Date, bStart: Date, bEnd: Date): boolean {
  return aStart < bEnd && bStart < aEnd;
}