/**
 * Pure validators for the Coach Onboarding wizard (steps 2-4). Same rules as the SQL in migration 0211 and the
 * Flutter twin in mobile/lib/features/coaching/add_coach_validation.dart — one set of rules, not three that drift.
 * Codes are normalised (trim, strip spaces/dashes, upper-case) BEFORE being checked, so a pasted "sbin 0001234" works.
 */

const IFSC_RE = /^[A-Z]{4}0[A-Z0-9]{6}$/;
const PAN_RE = /^[A-Z]{5}[0-9]{4}[A-Z]$/;
const GSTIN_RE = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/;
const UPI_RE = /^[A-Za-z0-9.\-_]{2,256}@[A-Za-z]{2,64}$/;

export const CERTIFICATE_MAX_BYTES = 5 * 1024 * 1024;
export const CERTIFICATE_ACCEPT = ["image/jpeg", "image/png", "image/webp", "application/pdf"];

function normalizeCode(s: string): string {
  return s.replace(/[\s-]/g, "").toUpperCase();
}

export const normalizeIfsc = normalizeCode;
export const normalizePan = normalizeCode;
export const normalizeGstin = normalizeCode;

export function isValidIfsc(s: string): boolean {
  return IFSC_RE.test(s);
}

export function isValidPan(s: string): boolean {
  return PAN_RE.test(s);
}

export function isValidGstin(s: string): boolean {
  return GSTIN_RE.test(s);
}

export function isValidUpi(s: string): boolean {
  return UPI_RE.test(s.trim());
}

/** 9-18 digits, nothing else (the screen strips spaces as the number is typed). */
export function isValidAccountNumber(s: string): boolean {
  return /^[0-9]{9,18}$/.test(s);
}

/** A positive whole number of rupees — no decimals, zero or negatives. */
export function isValidRupees(s: string): boolean {
  return /^[1-9][0-9]{0,8}$/.test(s.trim());
}

export function rupeesToMinor(s: string): number {
  return Number(s.trim()) * 100;
}

/** "HH:MM" strings; an equal or reversed pair is not a slot. */
export function isValidSlot(start: string, end: string): boolean {
  return Boolean(start) && Boolean(end) && end > start;
}

const DAY_SHORT = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

/**
 * The first repeated or overlapping weekly slot on the same day, as a message naming both slots — or null when there is none.
 * Slots that only touch (ends 12:00, next starts 12:00) are fine. A slot whose end is not after its start is ignored here: that is
 * `isValidSlot`'s job, and it would otherwise be reported twice.
 */
export function findAvailabilityConflict(windows: { dayOfWeek: number; startTime: string; endTime: string }[]): string | null {
  const slots = windows
    .map((w) => ({ day: w.dayOfWeek, start: w.startTime.slice(0, 5), end: w.endTime.slice(0, 5) }))
    .filter((w) => isValidSlot(w.start, w.end))
    .sort((a, b) => a.day - b.day || a.start.localeCompare(b.start) || a.end.localeCompare(b.end));
  const label = (w: { day: number; start: string; end: string }) => `${DAY_SHORT[w.day] ?? "Day"} ${w.start}–${w.end}`;
  for (let i = 1; i < slots.length; i++) {
    const prev = slots[i - 1]!;
    const cur = slots[i]!;
    if (prev.day !== cur.day) continue;
    if (prev.start === cur.start && prev.end === cur.end) return `${label(cur)} is added twice. Remove one of them.`;
    if (cur.start < prev.end) return `${label(prev)} overlaps ${label(cur)}. Change one so they don't overlap.`;
  }
  return null;
}

/** The error copy for a certificate upload, or null when the file is acceptable. */
export function validateCertificateFile(f: { type: string; size: number }): string | null {
  if (!CERTIFICATE_ACCEPT.includes(f.type)) return "Please choose a JPG, PNG, WEBP or PDF file.";
  if (f.size > CERTIFICATE_MAX_BYTES) return "That file is larger than 5MB.";
  return null;
}
