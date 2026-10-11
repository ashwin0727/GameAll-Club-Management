/** How many upcoming coaching sessions the overview shows: just the next two. */
export const UPCOMING_SESSION_LIMIT = 2;

/** The next [limit] sessions in start order, whichever day they fall on. */
export function nextSessions<T extends { startAt: string }>(sessions: T[], limit: number = UPCOMING_SESSION_LIMIT): T[] {
  return [...sessions].sort((a, b) => a.startAt.localeCompare(b.startAt)).slice(0, limit);
}

function dayKey(d: Date): string {
  return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
}

/** "Today", "Tomorrow", or "Mon, 12 Oct" — so a session tomorrow isn't mistaken for one later today. */
export function sessionDayLabel(iso: string, now: Date = new Date()): string {
  const d = new Date(iso);
  if (dayKey(d) === dayKey(now)) return "Today";
  const tomorrow = new Date(now);
  tomorrow.setDate(now.getDate() + 1);
  if (dayKey(d) === dayKey(tomorrow)) return "Tomorrow";
  return d.toLocaleDateString("en-IN", { weekday: "short", day: "2-digit", month: "short" });
}
