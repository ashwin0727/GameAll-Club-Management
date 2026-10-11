/**
 * Active Sessions is a daily figure: how many coaching sessions the current day has. Sessions that are
 * still to come, under way or already done all count; only cancelled ones are left out.
 */
export function todaysActiveCount(sessions: { status: string }[]): number {
  return sessions.filter((x) => x.status !== "CANCELLED").length;
}
