import { validatePlayingSchedule, type PlayingScheduleDraft } from "@/features/memberships/playing-schedule";

export type WizardStep = 1 | 2 | 3 | 4 | 5;

export const WIZARD_STEPS: { step: WizardStep; title: string; hint: string }[] = [
  { step: 1, title: "Personal Information", hint: "Basic details" },
  { step: 2, title: "Select Plan", hint: "Choose membership plan" },
  { step: 3, title: "Playing Schedule", hint: "Select days & time" },
  { step: 4, title: "Review & Confirm", hint: "Verify details" },
  { step: 5, title: "Payment", hint: "Complete registration" },
];

export interface WizardDraft {
  fullName: string;
  /** Dialling code shown beside the phone box, e.g. "+91". */
  countryCode: string;
  phone: string;
  email: string;
  dateOfBirth: string;
  gender: string;
  address: string;
  city: string;
  pincode: string;
  emergencyName: string;
  emergencyCountryCode: string;
  emergencyPhone: string;
  /** Whether to greet the member once they're created. */
  sendWelcome: boolean;
  planId: string;
  planName: string;
  startDate: string;
  durationDays: number;
  membershipFeeInr: number;
  registrationFeeInr: number;
  gstPercent: number;
  schedule: PlayingScheduleDraft;
  /** Which of the three Payment step panels is open. */
  paymentTab: PaymentTab;
  /** Defaults to the plan's total but is editable via "Edit Amount". */
  paymentAmount: number;
  paymentDate: string;
  paymentMethod: PaymentMethod;
  paymentReference: string;
  receivedFrom: string;
  collectedBy: string;
  /** Only for the offline/mark-as-paid tabs — kept apart from the emergency-contact notes. */
  paymentNotes: string;
}

export type PaymentTab = "link" | "offline" | "paid";
export type PaymentMethod = "Cash" | "Bank Transfer" | "UPI" | "Other";

export interface Charges {
  subTotal: number;
  gstAmount: number;
  registration: number;
  total: number;
}

/** What the member owes: the plan's fee plus GST on it, plus any one-off registration fee. */
export function charges(draft: Pick<WizardDraft, "membershipFeeInr" | "gstPercent" | "registrationFeeInr">): Charges {
  const subTotal = Math.max(0, draft.membershipFeeInr);
  const gstAmount = Math.round((subTotal * Math.max(0, draft.gstPercent)) / 100);
  const registration = Math.max(0, draft.registrationFeeInr);
  return { subTotal, gstAmount, registration, total: subTotal + gstAmount + registration };
}

const INDIAN_MOBILE_RE = /^[6-9]\d{9}$/;
const NAME_RE = /^[A-Za-z][A-Za-z .'-]{1,59}$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
/** An Indian PIN code: six digits, the first never 0. */
const PINCODE_RE = /^[1-9]\d{5}$/;

/**
 * The number typed into the phone box, with the selected dialling code peeled back off the
 * front if it's there too — someone pasting "+91 98765 43210" whole into the field shouldn't
 * be told their 10-digit number is the wrong length.
 */
function localDigits(countryCode: string, phone: string): string {
  const digits = phone.replace(/\D/g, "");
  const code = countryCode.replace(/\D/g, "");
  return code && digits.startsWith(code) && digits.length > code.length ? digits.slice(code.length) : digits;
}

/** "Full name is required." / "Full name is invalid." — every field's message follows this shape. */
function requiredMsg(label: string): string {
  return `${label} is required.`;
}
function invalidMsg(label: string): string {
  return `${label} is invalid.`;
}

/**
 * For +91, a real Indian mobile number: exactly 10 digits, starting with 6, 7, 8 or 9 (numbers
 * starting 0-5 aren't issued to mobiles). Other codes just get a sanity length check, since
 * that rule is India-specific. The message itself stays short — the field is right there next
 * to it, so it doesn't need to restate the whole rule.
 */
function phoneError(countryCode: string, phone: string, label: string): string | null {
  if (!phone.trim()) return requiredMsg(label);
  const digits = localDigits(countryCode, phone);
  if (countryCode === "+91") {
    return INDIAN_MOBILE_RE.test(digits) ? null : invalidMsg(label);
  }
  return digits.length >= 7 && digits.length <= 14 ? null : invalidMsg(label);
}

function nameError(name: string, label: string): string | null {
  if (!name.trim()) return requiredMsg(label);
  return NAME_RE.test(name.trim()) ? null : invalidMsg(label);
}

function dobError(dob: string, now: Date): string | null {
  const d = new Date(`${dob}T00:00:00`);
  if (Number.isNaN(d.getTime())) return invalidMsg("Date of birth");
  if (d > now) return invalidMsg("Date of birth");
  const ageYears = (now.getTime() - d.getTime()) / (365.25 * 24 * 60 * 60 * 1000);
  return ageYears <= 120 ? null : invalidMsg("Date of birth");
}

export interface FieldErrors {
  [field: string]: string | undefined;
}

/**
 * Every field's own error, keyed by field name, for showing under each input rather than one
 * message for the whole step. `validateStep` below is just the first of these, for the
 * step-level gate (Next/tracker) that doesn't care which field is wrong.
 */
export function fieldErrors(step: WizardStep, draft: WizardDraft, now: Date = new Date()): FieldErrors {
  const errors: FieldErrors = {};

  if (step === 1) {
    const name = nameError(draft.fullName, "Full name");
    if (name) errors.fullName = name;

    const phone = phoneError(draft.countryCode, draft.phone, "Phone number");
    if (phone) errors.phone = phone;

    if (draft.email.trim() && !EMAIL_RE.test(draft.email.trim())) errors.email = invalidMsg("Email address");

    if (draft.dateOfBirth) {
      const dob = dobError(draft.dateOfBirth, now);
      if (dob) errors.dateOfBirth = dob;
    }

    if (draft.city.trim() && !/^[A-Za-z][A-Za-z .'-]{1,49}$/.test(draft.city.trim())) {
      errors.city = invalidMsg("City");
    }

    if (draft.pincode.trim() && !PINCODE_RE.test(draft.pincode.trim())) {
      errors.pincode = invalidMsg("Pincode");
    }

    if (draft.emergencyName.trim()) {
      const name2 = nameError(draft.emergencyName, "Emergency contact name");
      if (name2) errors.emergencyName = name2;
    }
    if (draft.emergencyPhone.trim()) {
      const phone2 = phoneError(draft.emergencyCountryCode, draft.emergencyPhone, "Emergency contact number");
      if (phone2) errors.emergencyPhone = phone2;
    }
  }

  if (step === 2) {
    if (!draft.planId) errors.planId = requiredMsg("Membership plan");
    else if (!draft.durationDays) errors.planId = invalidMsg("Membership plan");

    if (!draft.startDate) errors.startDate = requiredMsg("Start date");

    if (draft.registrationFeeInr < 0) errors.registrationFeeInr = invalidMsg("Registration fee");
    // GST in India tops out at 28% (the highest standard slab); anything above that is a typo.
    if (draft.gstPercent < 0 || draft.gstPercent > 28) errors.gstPercent = invalidMsg("GST");
  }

  if (step === 3) {
    const scheduleErr = validatePlayingSchedule(draft.schedule);
    if (scheduleErr) errors.slot = scheduleErr;
  }

  if (step === 5) {
    // "Generate Payment Link" only needs the amount to be something real — everything else
    // (method, who received it) doesn't apply until the member actually pays through the link.
    if (draft.paymentAmount <= 0) errors.paymentAmount = requiredMsg("Payment amount");

    if (draft.paymentTab !== "link") {
      if (!draft.paymentDate) errors.paymentDate = requiredMsg("Payment date");
      if (!draft.receivedFrom.trim()) errors.receivedFrom = requiredMsg("Received from");
      if (!draft.collectedBy.trim()) errors.collectedBy = requiredMsg("Collected by");
      // Cash needs no paper trail, but UPI/Bank Transfer should always be traceable to a
      // reference number.
      if ((draft.paymentMethod === "UPI" || draft.paymentMethod === "Bank Transfer") && !draft.paymentReference.trim()) {
        errors.paymentReference = requiredMsg("Reference / Transaction ID");
      }
    }
  }

  return errors;
}

/**
 * The member's address as one line. `members.address` is a single column, so the city and
 * pincode collected separately are folded in here rather than dropped.
 */
export function composeAddress(draft: Pick<WizardDraft, "address" | "city" | "pincode">): string | undefined {
  const parts = [draft.address.trim(), draft.city.trim()].filter(Boolean);
  const line = parts.join(", ");
  const pin = draft.pincode.trim();
  const full = [line, pin].filter(Boolean).join(" - ");
  return full || undefined;
}

/**
 * The emergency contact, recorded in the member's notes — there's no column of its own for it,
 * and losing it entirely would be worse than keeping it somewhere findable.
 */
export function composeNotes(
  draft: Pick<WizardDraft, "emergencyName" | "emergencyCountryCode" | "emergencyPhone">,
): string | undefined {
  const name = draft.emergencyName.trim();
  const phone = draft.emergencyPhone.trim();
  if (!name && !phone) return undefined;
  const number = phone ? `${draft.emergencyCountryCode} ${phone}`.trim() : "";
  return `Emergency contact: ${[name, number].filter(Boolean).join(" — ")}`;
}

/**
 * The offline-payment details `record_membership_payment` has no column for (amount, date,
 * reference, who collected/received it) — only the payment method itself is actually stored.
 * Folded into the membership's notes so the information isn't silently discarded, even though
 * it isn't structured/queryable data this way.
 */
export function composePaymentNotes(
  draft: Pick<
    WizardDraft,
    "paymentTab" | "paymentAmount" | "paymentDate" | "paymentMethod" | "paymentReference" | "receivedFrom" | "collectedBy" | "paymentNotes"
  >,
): string | undefined {
  if (draft.paymentTab === "link") return undefined;
  const who = [
    draft.receivedFrom.trim() && `received from ${draft.receivedFrom.trim()}`,
    draft.collectedBy.trim() && `collected by ${draft.collectedBy.trim()}`,
  ]
    .filter(Boolean)
    .join(", ");
  const parts = [
    `Payment: ₹${draft.paymentAmount.toLocaleString("en-IN")} on ${draft.paymentDate} via ${draft.paymentMethod}.`,
    draft.paymentReference.trim() && `Ref: ${draft.paymentReference.trim()}.`,
    who && `${who[0]!.toUpperCase()}${who.slice(1)}.`,
    draft.paymentNotes.trim(),
  ].filter(Boolean);
  return parts.join(" ");
}

/**
 * What still has to be filled in before a step can be left — the first of that step's field
 * errors, for gating Next and marking the step done in the tracker. `fieldErrors` above is
 * what the form itself shows, under each input.
 */
export function validateStep(step: WizardStep, draft: WizardDraft, now: Date = new Date()): string | null {
  const errors = fieldErrors(step, draft, now);
  return Object.values(errors).find((e): e is string => Boolean(e)) ?? null;
}

/** The furthest step reachable — a step only opens once everything before it is valid. */
export function furthestReachableStep(draft: WizardDraft, now: Date = new Date()): WizardStep {
  for (const { step } of WIZARD_STEPS) {
    if (validateStep(step, draft, now) !== null) return step;
  }
  return 5;
}

export function isStepComplete(step: WizardStep, draft: WizardDraft, current: WizardStep, now: Date = new Date()): boolean {
  return step < current && validateStep(step, draft, now) === null;
}
