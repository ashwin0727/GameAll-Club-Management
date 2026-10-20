import type { FinanceDateRange } from "@/features/finance/types";

/** An inclusive range of calendar days, yyyy-mm-dd. */
export interface DayRange {
  from: string;
  to: string;
}

/** A local calendar date as yyyy-mm-dd. */
export function iso(date: Date): string {
  return `${date.getFullYear()}-${`${date.getMonth() + 1}`.padStart(2, "0")}-${`${date.getDate()}`.padStart(2, "0")}`;
}

/** The first and last day of the current month — what every Finance list opens on. */
export function currentMonthRange(now: Date = new Date()): DayRange {
  return { from: iso(new Date(now.getFullYear(), now.getMonth(), 1)), to: iso(new Date(now.getFullYear(), now.getMonth() + 1, 0)) };
}

export function isCurrentMonth(range: DayRange, now: Date = new Date()): boolean {
  const month = currentMonthRange(now);
  return range.from === month.from && range.to === month.to;
}

/** The explicit-dates form the Finance functions take. */
export function toFinanceDateRange(range: DayRange): FinanceDateRange {
  return { preset: "CUSTOM", startDate: range.from, endDate: range.to };
}

const DAY_MS = 86_400_000;

function parseDay(day: string): Date {
  const [y, m, d] = day.split("-").map(Number);
  return new Date(y!, (m ?? 1) - 1, d ?? 1, 12); // noon: immune to daylight-saving shifts
}

/**
 * The server only returns buckets that had activity. A trend should span the dates that were picked, so this adds the
 * quiet days / weeks / months back as zeros. Buckets are named the way the database names them: the day itself, the
 * Monday of the week, the 1st of the month.
 */
export function fillTrendBuckets<T extends { date: string }>(
  points: T[],
  range: DayRange,
  granularity: "daily" | "weekly" | "monthly",
  empty: (date: string) => T,
): T[] {
  if (!range.from || !range.to || range.from > range.to) return points;
  const start = parseDay(range.from);
  const end = parseDay(range.to);
  if ((end.getTime() - start.getTime()) / DAY_MS > 3700) return points;

  const have = new Map(points.map((p) => [p.date.slice(0, 10), p] as const));
  const keys: string[] = [];
  const cursor = new Date(start);
  if (granularity === "weekly") cursor.setDate(cursor.getDate() - ((cursor.getDay() + 6) % 7));
  if (granularity === "monthly") cursor.setDate(1);
  while (cursor <= end) {
    keys.push(iso(cursor));
    if (granularity === "daily") cursor.setDate(cursor.getDate() + 1);
    else if (granularity === "weekly") cursor.setDate(cursor.getDate() + 7);
    else cursor.setMonth(cursor.getMonth() + 1);
  }

  // Anything the server sent that is not in the generated list (an unexpected bucket name) is kept, not dropped.
  const extra = points.filter((p) => !keys.includes(p.date.slice(0, 10)));
  return [...keys.map((k) => have.get(k) ?? empty(k)), ...extra].sort((a, b) => a.date.localeCompare(b.date));
}
