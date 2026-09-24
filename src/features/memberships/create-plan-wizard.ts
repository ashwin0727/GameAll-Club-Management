export type PlanWizardStep = 1 | 2 | 3 | 4;

export const PLAN_WIZARD_STEPS: { step: PlanWizardStep; title: string; hint: string }[] = [
  { step: 1, title: "Plan Details", hint: "Basic information" },
  { step: 2, title: "Plan Configuration", hint: "Duration & pricing" },
  { step: 3, title: "Court Access", hint: "Set court timings" },
  { step: 4, title: "Review & Create", hint: "Confirm and publish" },
];

/** Fixed duration presets, in days — "Custom" lets the owner type any other length. Reused for
 *  both a TIME_BASED plan's Duration and a RECURRING plan's Billing Interval, since `durationDays`
 *  is the same field either way (see PlanWizardDraft's own note on it). */
export const DURATION_PRESETS: { label: string; days: number | null }[] = [
  { label: "1 Month", days: 30 },
  { label: "3 Months", days: 90 },
  { label: "6 Months", days: 180 },
  { label: "1 Year", days: 365 },
  { label: "Custom", days: null },
];

export const PLAN_CATEGORIES = ["Regular Membership", "Premium Membership", "Student Membership", "Corporate Membership", "Other"];

/**
 * One recurring slot this plan reserves — becomes a real `membership_batches` row (via the
 * existing `createBatch`) once the plan itself exists, exactly the mechanism the Add Member
 * wizard's own Playing Schedule step already writes to. `id` is a local draft key only, so
 * added/removed windows can be tracked before any of them are real rows.
 */
export interface PlanTimeWindow {
  id: string;
  courtId: string;
  daysOfWeek: number[];
  startTime: string; // "HH:MM"
  endTime: string;
  capacity: number;
}

export interface PlanWizardDraft {
  name: string;
  description: string;
  planType: "TIME_BASED" | "RECURRING";
  category: string;
  priceInr: number;
  durationDays: number;
  /** 0 means "not set" — folded to `undefined` on save, same as an empty field. */
  joiningFeeInr: number;
  securityDepositInr: number;
  /** The Plan Details step's badge toggle — `badgeText` is kept even while `showBadge` is off,
   *  so switching it back on restores whatever was typed before. */
  showBadge: boolean;
  badgeText: string;
  /** Which courts this plan can reserve time on. A time window's own courtId must be one of these. */
  courtIds: string[];
  /** The day set new time windows default to when added — each window still carries its own
   *  daysOfWeek afterward, same as a real membership_batches row does. */
  playingDays: number[];
  timeWindows: PlanTimeWindow[];
  /** Booking-flow preferences — captured for the owner's reference and folded into the plan's
   *  features, since neither has a real enforcement mechanism in the booking engine yet. */
  allowAdvanceBooking: boolean;
  limitConsecutiveSlots: boolean;
  features: string[];
  isActive: boolean;
}

/** Court/day/time slots aren't capacity-limited anywhere in the booking engine (see
 *  0089_membership_batches_unlimited_slots.sql) — Court Access doesn't expose a capacity field
 *  for that reason, and every window a plan creates gets this generously high placeholder
 *  instead of an artificial 1-member cap. */
export const UNLIMITED_WINDOW_CAPACITY = 999;

/** "Full name is required." / "Full name is invalid." — every field's message follows this shape. */
function requiredMsg(label: string): string {
  return `${label} is required.`;
}

export interface FieldErrors {
  [field: string]: string | undefined;
}

/**
 * Every field's own error, keyed by field name — mirrors the Add Member wizard's
 * `fieldErrors`/`validateStep` split: this is what the form shows under each input,
 * `validateStep` below is just the first of these, for the step tracker.
 */
export function fieldErrors(step: PlanWizardStep, draft: PlanWizardDraft): FieldErrors {
  const errors: FieldErrors = {};

  if (step === 1) {
    if (!draft.name.trim()) errors.name = requiredMsg("Plan name");
    if (draft.description.length > 200) errors.description = "Description can't be more than 200 characters.";
  }

  if (step === 2) {
    if (!(draft.priceInr > 0)) errors.priceInr = "Price must be greater than 0.";
    if (!Number.isInteger(draft.durationDays) || draft.durationDays <= 0) errors.durationDays = "Duration must be at least 1 day.";
    if (draft.joiningFeeInr < 0) errors.joiningFeeInr = "Joining fee can't be negative.";
    if (draft.securityDepositInr < 0) errors.securityDepositInr = "Security deposit can't be negative.";
  }

  if (step === 3) {
    if (draft.courtIds.length === 0) errors.courtIds = "Select at least one court.";
    if (draft.playingDays.length === 0) errors.playingDays = "Select at least one playing day.";
    if (draft.timeWindows.length === 0) errors.timeWindows = "Add at least one time window.";
    const invalidWindow = draft.timeWindows.find((w) => w.startTime >= w.endTime || w.capacity <= 0);
    if (invalidWindow) errors.timeWindows = "Every time window needs an end time after its start time and a capacity of at least 1.";
  }

  return errors;
}

/** True when two windows would double-book the same court — same court, at least one shared
 *  weekday, and overlapping clock times. Informational only: the booking engine itself already
 *  allows a court's capacity to be shared across batches (see 0089_membership_batches_unlimited_
 *  slots.sql), so this doesn't block saving — it's surfaced as a heads-up, not an error. */
export function windowsOverlap(a: PlanTimeWindow, b: PlanTimeWindow): boolean {
  if (a.courtId !== b.courtId) return false;
  if (!a.daysOfWeek.some((d) => b.daysOfWeek.includes(d))) return false;
  return a.startTime < b.endTime && b.startTime < a.endTime;
}

/** The first *other* window this one overlaps with, if any. */
export function findOverlap(windows: PlanTimeWindow[], target: PlanTimeWindow): PlanTimeWindow | undefined {
  return windows.find((w) => w.id !== target.id && windowsOverlap(w, target));
}

export function validateStep(step: PlanWizardStep, draft: PlanWizardDraft): string | null {
  const errors = fieldErrors(step, draft);
  return Object.values(errors).find((e): e is string => Boolean(e)) ?? null;
}

/** The furthest step reachable — a step only opens once everything before it is valid. Step 4
 *  (Review & Create) has nothing of its own to require, so it's reachable as soon as 1-3 are
 *  filled in. */
export function furthestReachableStep(draft: PlanWizardDraft): PlanWizardStep {
  for (const { step } of PLAN_WIZARD_STEPS) {
    if (step <= 3 && validateStep(step, draft) !== null) return step;
  }
  return 4;
}

export function isStepComplete(step: PlanWizardStep, draft: PlanWizardDraft, current: PlanWizardStep): boolean {
  if (step >= current) return false;
  return step > 3 || validateStep(step, draft) === null;
}

/** The feature list actually saved: the ones typed in Benefits & Rules, trimmed and de-blanked. */
export function composeFeatures(draft: Pick<PlanWizardDraft, "features">): string[] {
  return draft.features.map((f) => f.trim()).filter(Boolean);
}
