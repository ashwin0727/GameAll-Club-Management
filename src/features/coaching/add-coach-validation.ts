/**
 * Validation for the Add Coach wizard's "+ New person" fields — pure functions so they're
 * testable without mounting the form, and shared between the live inline-error display and the
 * `canSubmit` gate (one set of rules, not two that can drift apart).
 */

export const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** Phone is optional overall, but an entered value must be exactly 10 digits — the field itself
 *  only ever accepts digits (see `sanitizePhoneDigits`), so this only rejects "started typing,
 *  not done yet". */
export function isValidPhoneDigits(digits: string): boolean {
  return digits.length === 0 || digits.length === 10;
}

/** Strips everything but digits and caps at 10 — used in the field's onChange so a pasted
 *  "+91 98765-43210" or a stray letter never lands in state at all, rather than being validated
 *  after the fact. */
export function sanitizePhoneDigits(raw: string): string {
  return raw.replace(/\D/g, "").slice(0, 10);
}

export function isValidEmail(email: string): boolean {
  return EMAIL_REGEX.test(email.trim());
}

const MAX_AGE_YEARS = 100;
const MIN_AGE_YEARS = 18;

/** Date of birth is optional; an entered one must be a real date, not in the future, and within
 *  a plausible employment-age range (18–100 years old) — a coach hire in this system, not a
 *  member of any age. */
export function isValidDateOfBirth(iso: string, today: Date = new Date()): boolean {
  if (!iso) return true;
  const date = new Date(`${iso}T00:00:00`);
  if (Number.isNaN(date.getTime())) return false;
  const start = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  if (date > start) return false;
  const oldest = new Date(start);
  oldest.setFullYear(start.getFullYear() - MAX_AGE_YEARS);
  if (date < oldest) return false;
  const youngest = new Date(start);
  youngest.setFullYear(start.getFullYear() - MIN_AGE_YEARS);
  if (date > youngest) return false;
  return true;
}

/** "2026-09-26" from the date's own local year/month/day — not `toISOString()`, which converts
 *  to UTC first and would shift the date by a day in any positive-offset timezone (IST included). */
function isoOfLocalDate(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

/** The date input's own `min`/`max` — restricts what the native picker offers, so most invalid
 *  dates can't be selected in the first place (typed input can still miss the window, which is
 *  what `isValidDateOfBirth` catches). */
export function dateOfBirthBounds(today: Date = new Date()): { min: string; max: string } {
  const oldest = new Date(today.getFullYear() - MAX_AGE_YEARS, today.getMonth(), today.getDate());
  const youngest = new Date(today.getFullYear() - MIN_AGE_YEARS, today.getMonth(), today.getDate());
  return { min: isoOfLocalDate(oldest), max: isoOfLocalDate(youngest) };
}
