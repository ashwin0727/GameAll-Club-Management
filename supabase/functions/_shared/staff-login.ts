// Generated staff credentials. Pure functions so the formats are easy to test.
//
//   login    : <first name><DDMMYYYY of joining><HHMMSS of creation>@gameall.co   e.g. ravi23102026153045@gameall.co
//   password : <Facility full name>@<HH:MM:SS>                                  e.g. Champz Turf@15:30:45
//
// Date and time are read in the facility's own timezone, so they match the clock the owner sees.

export const STAFF_LOGIN_DOMAIN = "gameall.co";

export interface ClockParts {
  dd: string;
  mm: string;
  yyyy: string;
  hh: string;
  mi: string;
  ss: string;
}

/** The wall-clock date and time of [now] in [timeZone]. */
export function clockParts(now: Date, timeZone = "Asia/Kolkata"): ClockParts {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(now);
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "00";
  return { dd: get("day"), mm: get("month"), yyyy: get("year"), hh: get("hour"), mi: get("minute"), ss: get("second") };
}

/** Lower-case letters and digits only, so the login is a clean email local-part ("Anne-Marie" → "annemarie"). */
export function loginNamePart(firstName: string): string {
  const cleaned = firstName
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
  return cleaned || "staff";
}

/** [attempt] > 0 only when the login is already taken (two people with the same first name created in the same second). */
export function buildStaffLogin(firstName: string, now: Date, timeZone?: string, attempt = 0): string {
  const c = clockParts(now, timeZone);
  const suffix = attempt > 0 ? String(attempt) : "";
  return `${loginNamePart(firstName)}${c.dd}${c.mm}${c.yyyy}${c.hh}${c.mi}${c.ss}${suffix}@${STAFF_LOGIN_DOMAIN}`;
}

export function buildDefaultPassword(facilityName: string, now: Date, timeZone?: string): string {
  const c = clockParts(now, timeZone);
  return `${facilityName.trim()}@${c.hh}:${c.mi}:${c.ss}`;
}
