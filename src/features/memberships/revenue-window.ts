/** First day of the month `monthsBack` months before the month of `now`, as yyyy-mm-dd (local calendar). */
export function monthStartIso(now: Date, monthsBack: number): string {
  const d = new Date(now.getFullYear(), now.getMonth() - monthsBack, 1);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-01`;
}

/** Today as yyyy-mm-dd (local calendar). */
export function todayIso(now: Date): string {
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
}

export interface RevenuePoint {
  bucket: string;
  amountInr: number;
}

/**
 * The last `months` calendar months (this month included, up to today) against the same number of months before
 * them: the total, and the change in percent (null when there was nothing before to compare with).
 */
export function revenueOverMonths(
  points: RevenuePoint[],
  now: Date,
  months = 3,
): { total: number; previous: number; changePct: number | null; current: RevenuePoint[] } {
  const currentStart = monthStartIso(now, months - 1);
  const previousStart = monthStartIso(now, months * 2 - 1);
  const current = points.filter((p) => p.bucket.slice(0, 10) >= currentStart);
  const total = current.reduce((s, p) => s + p.amountInr, 0);
  const previous = points
    .filter((p) => p.bucket.slice(0, 10) >= previousStart && p.bucket.slice(0, 10) < currentStart)
    .reduce((s, p) => s + p.amountInr, 0);
  return { total, previous, changePct: previous > 0 ? ((total - previous) / previous) * 100 : null, current };
}
