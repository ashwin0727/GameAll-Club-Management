const DAY_ABBR = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

/** "06:00:00" | "06:00" → "6:00 AM" */
export function formatClock(time: string): string {
  const [hStr, mStr] = time.split(":");
  const h = Number(hStr ?? 0);
  const m = Number(mStr ?? 0);
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}:${String(m).padStart(2, "0")} ${h < 12 ? "AM" : "PM"}`;
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