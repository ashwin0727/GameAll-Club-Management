/**
 * A plan's slot is named after the plan plus its time. Slots made before the full range was used carry only the
 * START time ("Morning Monthly Membership (5 AM to 6 AM) — 05:00"); this shows them the way new ones are named
 * ("… — 05:00 to 06:00") so nobody has to guess where the slot ends. A name that is anything else is left alone.
 */
// Names saved before the dash was dropped still carry one; show them with a colon.
const cleanDash = (s: string) => s.replace(/s\u2014s/g, ": ");

export function displayBatchName(name: string, startTime: string, endTime: string): string {
  const m = name.trim().match(/^(.*?)\s*[\u2014\u2013-]\s*\d{1,2}:\d{2}(?::\d{2})?$/);
  if (!m || startTime.length < 5 || endTime.length < 5) return cleanDash(name);
  return `${m[1]}: ${startTime.slice(0, 5)} to ${endTime.slice(0, 5)}`;
}

/** The name a new slot is created with: the plan's name, then its whole time range. */
export function newBatchName(planName: string, startTime: string, endTime: string): string {
  return `${planName}: ${startTime.slice(0, 5)} to ${endTime.slice(0, 5)}`;
}
