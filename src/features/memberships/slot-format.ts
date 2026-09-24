const DAY_ABBR = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

/** "06:00:00" | "06:00" → "6:00 AM" */
export function formatClock(time: string): string {
  const [hStr, mStr] = time.split(":");
  const h = Number(hStr ?? 0);
  const m = Number(mStr ?? 0);
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}:${String(m).padStart(2, "0")} ${h < 12 ? "AM" : "PM"}`;
}

/**
 * [1,2,3,4,5] → "Mon - Fri", wrapping the week where it needs to ([3,4,5,6,0] → "Wed - Sun").
 * Days that don't form one unbroken run are listed instead ([1,3,5] → "Mon, Wed, Fri").
 */
export function formatDayRange(daysOfWeek: number[]): string {
  const days = [...new Set(daysOfWeek)].filter((d) => d >= 0 && d <= 6).sort((a, b) => a - b);
  if (days.length === 0) return "—";
  if (days.length === 1) return DAY_ABBR[days[0]!]!;
  if (days.length === 7) return "Every day";

  // Walk the week from each day in turn; a single unbroken run means we can show it as a range.
  for (const start of days) {
    let count = 1;
    while (count < days.length && days.includes((start + count) % 7)) count++;
    if (count === days.length) return `${DAY_ABBR[start]} - ${DAY_ABBR[(start + count - 1) % 7]}`;
  }
  return days.map((d) => DAY_ABBR[d]).join(", ");
}

/** [1,3,5] + times → "Mon/Wed/Fri · 5:00 AM – 6:00 AM" */
export function formatSlot(daysOfWeek: number[], startTime: string, endTime: string): string {
  const days = [...daysOfWeek]
    .sort((a, b) => a - b)
    .map((d) => DAY_ABBR[d] ?? "")
    .filter(Boolean)
    .join("/");
  return `${days} · ${formatClock(startTime)} – ${formatClock(endTime)}`;
}