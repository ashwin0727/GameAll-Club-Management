/**
 * One-hour blocks covering the full day, 12 AM through to midnight — courts can be booked any
 * hour, not just the daytime span the first pass of this grid covered. Postgres's `time` type
 * accepts "24:00" as end-of-day, so the last block (11 PM - 12 AM) is a valid end_time.
 */
export const HOUR_BLOCKS: { start: string; end: string; label: string }[] = Array.from({ length: 24 }, (_, i) => {
  const startHour = i;
  const endHour = startHour + 1;
  const label = (h: number) => {
    const h12 = h % 12 === 0 ? 12 : h % 12;
    return `${h12} ${h < 12 || h === 24 ? "AM" : "PM"}`;
  };
  return {
    start: `${String(startHour).padStart(2, "0")}:00`,
    end: `${String(endHour).padStart(2, "0")}:00`,
    label: `${label(startHour)} - ${label(endHour)}`,
  };
});

export type DayPresetKey = "weekdays" | "mon-sat" | "weekend" | "custom";

export const DAY_PRESETS: { key: DayPresetKey; label: string; days: number[] }[] = [
  { key: "weekdays", label: "Mon - Fri", days: [1, 2, 3, 4, 5] },
  { key: "mon-sat", label: "Mon - Sat", days: [1, 2, 3, 4, 5, 6] },
  { key: "weekend", label: "Weekends", days: [0, 6] },
  { key: "custom", label: "Custom", days: [] },
];

/** Which preset (if any) the given days exactly match — "custom" when they match none. */
export function matchingPreset(days: number[]): DayPresetKey {
  const sorted = [...days].sort();
  const found = DAY_PRESETS.find((p) => p.key !== "custom" && JSON.stringify([...p.days].sort()) === JSON.stringify(sorted));
  return found?.key ?? "custom";
}

export interface PlayingScheduleDraft {
  facilitySportId: string;
  courtId: string;
  daysOfWeek: number[];
  /** Selected hour blocks, each this block's start time ("06:00", "07:00", ...). */
  times: string[];
}

export interface ScheduleRange {
  startTime: string;
  endTime: string;
}

/**
 * Selected hours merged into as few contiguous ranges as possible — picking 6-7 and 7-8
 * becomes one 6-8 range; picking 6-7 and 2-4 PM (non-adjacent) stays two separate ranges, each
 * booked as its own dedicated slot for this member.
 */
export function groupContiguousRanges(times: string[]): ScheduleRange[] {
  const starts = [...new Set(times)].sort();
  const blockByStart = new Map(HOUR_BLOCKS.map((b) => [b.start, b]));
  const ranges: ScheduleRange[] = [];

  for (const start of starts) {
    const block = blockByStart.get(start);
    if (!block) continue;
    const last = ranges[ranges.length - 1];
    if (last && last.endTime === start) {
      last.endTime = block.end;
    } else {
      ranges.push({ startTime: block.start, endTime: block.end });
    }
  }
  return ranges;
}

/**
 * The schedule is entirely optional — a membership can have no dedicated court time. But once
 * any hour is picked, a court and at least one day are required to actually reserve it.
 */
export function validatePlayingSchedule(draft: PlayingScheduleDraft): string | null {
  if (draft.times.length === 0) return null;
  if (!draft.courtId) return "Select a court for the selected time slots.";
  if (draft.daysOfWeek.length === 0) return "Select at least one playing day.";
  return null;
}

/** The subset of `AssignableBatch` this matcher needs — kept narrow so it doesn't import the
 *  service types module. */
export interface BatchSlot {
  batchId: string;
  courtId: string;
  daysOfWeek: number[];
  startTime: string;
  endTime: string;
}

/**
 * Several members sharing a court's day/time slot should end up on the *same* batch, not one
 * each — so before creating a new one, this looks for an existing active batch that's an exact
 * match: same court, same clock range, and the exact same set of days (a batch's days apply to
 * every member on it, so a partial-day match would silently change other members' schedule).
 * No match just means a new batch is warranted, not an error.
 */
export function findMatchingBatch(
  batches: BatchSlot[],
  wanted: { courtId: string; daysOfWeek: number[]; startTime: string; endTime: string },
): BatchSlot | undefined {
  // Postgres `time` columns round-trip as "HH:MM:SS"; the wizard works in "HH:MM" — compare
  // just the HH:MM prefix so a stray ":00" seconds suffix doesn't break an otherwise-exact match.
  const clock = (t: string) => t.slice(0, 5);
  const wantedDays = [...new Set(wanted.daysOfWeek)].sort().join(",");
  return batches.find(
    (b) =>
      b.courtId === wanted.courtId &&
      clock(b.startTime) === clock(wanted.startTime) &&
      clock(b.endTime) === clock(wanted.endTime) &&
      [...new Set(b.daysOfWeek)].sort().join(",") === wantedDays,
  );
}
