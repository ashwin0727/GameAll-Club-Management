"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { ServiceError } from "@/services/shared/service-error";
import { getCoachingService } from "@/services/coaching";
import { getStaffService } from "@/services/staff";
import { isValidDateOfBirth, isValidEmail, sanitizePhoneDigits } from "@/features/coaching/add-coach-validation";
import {
  isValidAccountNumber,
  isValidGstin,
  isValidIfsc,
  isValidPan,
  isValidRupees,
  isValidUpi,
  normalizeGstin,
  normalizeIfsc,
  normalizePan,
  rupeesToMinor,
  validateCertificateFile,
} from "@/features/coaching/coach-onboarding-validation";
import type {
  CoachCandidate,
  CoachCertificate,
  CoachLegalAgreements,
  CoachOnboarding,
  CoachPayoutFrequency,
  CoachPayoutMethod,
  CoachSessionFormat,
} from "@/features/coaching/types";
import type { RoleRow } from "@/features/staff/types";

export const AVATAR_MAX_BYTES = 2 * 1024 * 1024;
export const AVATAR_ACCEPT = ["image/jpeg", "image/png", "image/webp"];

export type OnboardingStep = 1 | 2 | 3 | 4 | 5;

export interface PayoutDraft {
  entityType: "INDIVIDUAL" | "BUSINESS";
  legalName: string;
  businessAddress: string;
  taxId: string;
  payoutMethod: CoachPayoutMethod;
  accountHolderName: string;
  accountNumber: string;
  confirmAccountNumber: string;
  ifsc: string;
  upiId: string;
  payoutFrequency: CoachPayoutFrequency;
  cancellationPolicy: string;
}

/** Everything the five steps edit, as plain strings/arrays so inputs stay controlled. */
export interface OnboardingDraft {
  // 1
  mode: "pick" | "new";
  userId: string;
  newPerson: { firstName: string; lastName: string; phone: string; email: string; roleId: string };
  displayName: string;
  location: string;
  timezone: string;
  languages: string[];
  shortBio: string;
  dateOfBirth: string;
  // 2
  niche: string;
  subSpecialties: string[];
  experience: string;
  targetAudience: string[];
  methodology: string;
  certificates: CoachCertificate[];
  sportIds: string[];
  expertiseLevels: string[];
  // 3
  sessionFormats: CoachSessionFormat[];
  sessionDurations: number[];
  defaultDuration: string;
  /** Whole rupees, as typed. Stored in paise; display now, transaction inputs later. */
  perSessionRate: string;
  weeklyRate: string;
  monthlyRate: string;
  // 4
  payout: PayoutDraft;
  // 5
  agreements: CoachLegalAgreements;
}

export function emptyDraft(): OnboardingDraft {
  return {
    mode: "pick",
    userId: "",
    newPerson: { firstName: "", lastName: "", phone: "", email: "", roleId: "" },
    displayName: "",
    location: "",
    timezone: "Asia/Kolkata",
    languages: [],
    shortBio: "",
    dateOfBirth: "",
    niche: "",
    subSpecialties: [],
    experience: "",
    targetAudience: [],
    methodology: "",
    certificates: [],
    sportIds: [],
    expertiseLevels: [],
    sessionFormats: [],
    sessionDurations: [],
    defaultDuration: "",
    perSessionRate: "",
    weeklyRate: "",
    monthlyRate: "",
    payout: {
      entityType: "INDIVIDUAL",
      legalName: "",
      businessAddress: "",
      taxId: "",
      payoutMethod: "BANK_TRANSFER",
      accountHolderName: "",
      accountNumber: "",
      confirmAccountNumber: "",
      ifsc: "",
      upiId: "",
      payoutFrequency: "MONTHLY",
      cancellationPolicy: "",
    },
    agreements: { terms: false, ethics: false, privacy: false, commission: false },
  };
}

export interface StepContext {
  /** A payout is already saved on the server (its secrets are masked, so blank inputs mean "keep"). */
  hasSavedPayout: boolean;
}

/** A blank amount is fine (optional); a filled one must be a whole number of rupees above zero. */
function optionalRupees(s: string): boolean {
  return s.trim() === "" || isValidRupees(s);
}

/** Paise for the server, or null when the amount was left blank. */
function optionalMinor(s: string): number | null {
  return s.trim() === "" ? null : rupeesToMinor(s);
}

function nonNegative(s: string): boolean {
  return s.trim() === "" || (/^\d+(\.\d+)?$/.test(s.trim()) && Number(s) >= 0);
}

function step4Valid(p: PayoutDraft, ctx: StepContext): boolean {
  const tax = p.entityType === "BUSINESS" && isValidGstin(normalizeGstin(p.taxId)) ? true : isValidPan(normalizePan(p.taxId));
  const taxOk = tax || (ctx.hasSavedPayout && p.taxId.trim() === "");
  if (!taxOk) return false;
  if (p.entityType === "BUSINESS" && (!p.legalName.trim() || !p.businessAddress.trim())) return false;
  if (p.payoutMethod === "UPI") {
    return isValidUpi(p.upiId) || (ctx.hasSavedPayout && p.upiId.trim() === "");
  }
  if (!p.accountHolderName.trim()) return false;
  const keepAccount = ctx.hasSavedPayout && p.accountNumber === "" && p.confirmAccountNumber === "";
  const accountOk = keepAccount || (isValidAccountNumber(p.accountNumber) && p.accountNumber === p.confirmAccountNumber);
  const ifscOk = isValidIfsc(normalizeIfsc(p.ifsc)) || (ctx.hasSavedPayout && p.ifsc.trim() === "");
  return accountOk && ifscOk;
}

/** One rule-set for both the Next button and the inline errors — pure, so it is tested without mounting anything. */
export function isStepValid(step: OnboardingStep, d: OnboardingDraft, ctx: StepContext): boolean {
  switch (step) {
    case 1: {
      if (!d.displayName.trim() || !isValidDateOfBirth(d.dateOfBirth)) return false;
      if (d.mode === "pick") return Boolean(d.userId);
      const p = d.newPerson;
      return Boolean(p.firstName.trim() && p.lastName.trim() && p.roleId) && isValidEmail(p.email) && p.phone.length === 10; // the phone number is mandatory: all 10 digits
    }
    case 2:
      return Boolean(d.niche.trim()) && d.sportIds.length > 0 && d.expertiseLevels.length > 0 && nonNegative(d.experience) &&
        d.certificates.every((c) => c.name.trim() !== "");
    case 3:
      return (
        d.sessionFormats.length > 0 &&
        d.sessionDurations.length > 0 &&
        // The three amounts are optional; when one is filled in it has to be a valid whole-rupee amount.
        optionalRupees(d.perSessionRate) &&
        optionalRupees(d.weeklyRate) &&
        optionalRupees(d.monthlyRate)
      );
    case 4:
      return step4Valid(d.payout, ctx);
    case 5:
      return d.agreements.terms && d.agreements.ethics && d.agreements.privacy && d.agreements.commission;
  }
}

/** The body sent to `save_coach_onboarding_step` for steps 1-4. */
export function stepPayload(step: 1 | 2 | 3 | 4, d: OnboardingDraft): Record<string, unknown> {
  if (step === 1) {
    return {
      displayName: d.displayName.trim(),
      location: d.location.trim(),
      timezone: d.timezone,
      languages: d.languages,
      shortBio: d.shortBio.trim(),
      dateOfBirth: d.dateOfBirth || null,
    };
  }
  if (step === 2) {
    return {
      niche: d.niche.trim(),
      subSpecialties: d.subSpecialties,
      experienceYears: d.experience.trim() ? Number(d.experience) : null,
      targetAudience: d.targetAudience,
      methodology: d.methodology.trim(),
      certificates: d.certificates.map((c) => ({ name: c.name.trim(), issuer: c.issuer.trim(), year: c.year, path: c.path })),
      sportIds: d.sportIds,
      expertiseLevels: d.expertiseLevels,
    };
  }
  if (step === 3) {
    return {
      sessionFormats: d.sessionFormats,
      sessionDurations: d.sessionDurations,
      defaultSessionDurationMinutes: d.defaultDuration ? Number(d.defaultDuration) : d.sessionDurations[0] ?? null,
      perSessionRateMinor: optionalMinor(d.perSessionRate),
      weeklyRateMinor: optionalMinor(d.weeklyRate),
      monthlyRateMinor: optionalMinor(d.monthlyRate),
    };
  }
  const p = d.payout;
  return {
    entityType: p.entityType,
    legalName: p.legalName.trim(),
    businessAddress: p.businessAddress.trim(),
    taxId: p.entityType === "BUSINESS" && isValidGstin(normalizeGstin(p.taxId)) ? normalizeGstin(p.taxId) : normalizePan(p.taxId),
    payoutMethod: p.payoutMethod,
    accountHolderName: p.accountHolderName.trim(),
    accountNumber: p.accountNumber.replace(/\s/g, ""),
    ifsc: normalizeIfsc(p.ifsc),
    upiId: p.upiId.trim(),
    payoutFrequency: p.payoutFrequency,
    cancellationPolicy: p.cancellationPolicy.trim(),
  };
}

export function resumeStep(o: CoachOnboarding): OnboardingStep {
  return Math.min(5, Math.max(1, Math.round(o.currentStep || 1))) as OnboardingStep;
}

/** A saved draft back into the form. Secrets are never part of it (they come back masked and stay blank = keep). */
export function draftFromOnboarding(o: CoachOnboarding): OnboardingDraft {
  const e = emptyDraft();
  const d = o.data;
  return {
    ...e,
    mode: "pick",
    userId: o.userId,
    displayName: d.displayName,
    location: d.location,
    timezone: d.timezone,
    languages: d.languages,
    shortBio: d.shortBio,
    dateOfBirth: d.dateOfBirth ?? "",
    niche: d.niche,
    subSpecialties: d.subSpecialties,
    experience: d.experienceYears === null ? "" : String(d.experienceYears),
    targetAudience: d.targetAudience,
    methodology: d.methodology,
    certificates: d.certificates,
    sportIds: d.sportIds,
    expertiseLevels: d.expertiseLevels,
    sessionFormats: d.sessionFormats,
    sessionDurations: d.sessionDurations,
    defaultDuration: d.defaultSessionDurationMinutes ? String(d.defaultSessionDurationMinutes) : "",
    perSessionRate: d.perSessionRateMinor ? String(Math.round(d.perSessionRateMinor / 100)) : "",
    weeklyRate: d.weeklyRateMinor ? String(Math.round(d.weeklyRateMinor / 100)) : "",
    monthlyRate: d.monthlyRateMinor ? String(Math.round(d.monthlyRateMinor / 100)) : "",
    payout: o.payout
      ? {
          ...e.payout,
          entityType: o.payout.entityType,
          legalName: o.payout.legalName ?? "",
          businessAddress: o.payout.businessAddress ?? "",
          payoutMethod: o.payout.payoutMethod,
          accountHolderName: o.payout.accountHolderName ?? "",
          ifsc: "",
          upiId: "",
          payoutFrequency: o.payout.payoutFrequency,
          cancellationPolicy: o.payout.cancellationPolicy ?? "",
        }
      : e.payout,
  };
}

function messageOf(e: unknown, fallback: string): string {
  return e instanceof ServiceError ? e.message : fallback;
}

/**
 * All state and server calls for the 5-step Add Coach wizard, independent of layout. Step 1 creates the (INACTIVE) coach
 * as a draft; steps 2-4 save as the owner goes; step 5 records the agreements and activates the coach. Opening with a
 * `resumeCoachId` restores the saved values and the step the owner stopped at.
 */
export function useCoachOnboarding(facilityId: string | null, resumeCoachId: string | null, requestedStep: OnboardingStep | null = null) {
  // Whether this page was opened on a draft is decided ONCE. After Step 1 saves, the page rewrites the address bar to
  // `?coach=<id>`; if that were read again as "open this draft", the server copy would be loaded over whatever is on screen
  // (wiping un-saved edits and secrets, and jumping steps). So only the first values are ever used for resuming.
  const [openedWith] = useState(resumeCoachId);
  const [openedStep] = useState(requestedStep);
  const [step, setStepState] = useState<OnboardingStep>(1);
  const [coachId, setCoachId] = useState<string | null>(resumeCoachId);
  const [draft, setDraft] = useState<OnboardingDraft>(emptyDraft);
  const [loading, setLoading] = useState(Boolean(resumeCoachId));
  const [busy, setBusy] = useState(false);
  const [stage, setStage] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [canManagePayouts, setCanManagePayouts] = useState(true);
  const [payoutStatus, setPayoutStatus] = useState<"PENDING" | "COMPLETE">("PENDING");
  const [savedPayout, setSavedPayout] = useState<CoachOnboarding["payout"]>(null);
  const [completed, setCompleted] = useState<{ coachId: string; name: string } | null>(null);
  const [credentials, setCredentials] = useState<{ loginEmail: string; password: string } | null>(null);

  const [candidates, setCandidates] = useState<CoachCandidate[]>([]);
  const [roles, setRoles] = useState<RoleRow[]>([]);
  const [rolesError, setRolesError] = useState<string | null>(null);
  const [avatarFile, setAvatarFile] = useState<File | null>(null);
  const [avatarPreview, setAvatarPreview] = useState<string | null>(null);
  const [avatarError, setAvatarError] = useState<string | null>(null);

  const busyRef = useRef(false);
  const ctx: StepContext = { hasSavedPayout: savedPayout !== null };

  useEffect(() => {
    return () => {
      if (avatarPreview) URL.revokeObjectURL(avatarPreview);
    };
  }, [avatarPreview]);

  // Staff pickable as a coach + the roles for "+ New person" (only needed on a fresh start).
  useEffect(() => {
    if (!facilityId || openedWith) return;
    getCoachingService().listCoachCandidates(facilityId).then(setCandidates).catch(() => setCandidates([]));
    setRolesError(null);
    getStaffService()
      .listRoles(facilityId)
      .then((rows) => {
        setRoles(rows);
        const coachRole = rows.find((r) => /coach/i.test(r.name));
        if (coachRole) setDraft((d) => (d.newPerson.roleId ? d : { ...d, newPerson: { ...d.newPerson, roleId: coachRole.id } }));
      })
      .catch((e) => {
        setRoles([]);
        setRolesError(messageOf(e, "Could not load roles for the new-person form."));
      });
  }, [facilityId, openedWith]);

  // Resume: restore the saved values and open at the saved step — once, when the page opens with a draft.
  useEffect(() => {
    if (!openedWith) return;
    let cancelled = false;
    setLoading(true);
    getCoachingService()
      .getCoachOnboarding(openedWith)
      .then((o) => {
        if (cancelled) return;
        setDraft(draftFromOnboarding(o));
        setStepState(openedStep ?? resumeStep(o));
        setCanManagePayouts(o.canManagePayouts);
        setPayoutStatus(o.payoutStatus);
        setSavedPayout(o.payout);
        setCoachId(o.coachId);
      })
      .catch((e) => !cancelled && setError(messageOf(e, "Could not open this draft.")))
      .finally(() => !cancelled && setLoading(false));
    return () => {
      cancelled = true;
    };
  }, [openedWith, openedStep]);

  const patch = useCallback((partial: Partial<OnboardingDraft>) => setDraft((d) => ({ ...d, ...partial })), []);
  const patchPayout = useCallback((partial: Partial<PayoutDraft>) => setDraft((d) => ({ ...d, payout: { ...d.payout, ...partial } })), []);
  const patchNewPerson = useCallback(
    (partial: Partial<OnboardingDraft["newPerson"]>) => setDraft((d) => ({ ...d, newPerson: { ...d.newPerson, ...partial } })),
    [],
  );
  const setPhone = (raw: string) => patchNewPerson({ phone: sanitizePhoneDigits(raw) });

  function toggle<T>(list: T[], value: T): T[] {
    return list.includes(value) ? list.filter((v) => v !== value) : [...list, value];
  }

  function pickAvatar(file: File | undefined) {
    if (!file) return;
    setAvatarError(null);
    if (!AVATAR_ACCEPT.includes(file.type)) return setAvatarError("Please choose a JPG, PNG or WEBP image.");
    if (file.size > AVATAR_MAX_BYTES) return setAvatarError("That photo is larger than 2MB.");
    setAvatarFile(file);
    setAvatarPreview((prev) => {
      if (prev) URL.revokeObjectURL(prev);
      return URL.createObjectURL(file);
    });
  }

  /** Picking an existing staff member pre-fills their display name so Step 1 can continue straight away. */
  function pickStaff(userId: string) {
    const c = candidates.find((x) => x.userId === userId);
    setDraft((d) => ({ ...d, userId, displayName: d.displayName || c?.fullName || "" }));
  }

  function setStep(next: OnboardingStep) {
    setError(null);
    setStepState(next);
  }

  async function run(label: string, work: () => Promise<void>): Promise<boolean> {
    if (busyRef.current) return false;
    busyRef.current = true;
    setBusy(true);
    setStage(label);
    setError(null);
    try {
      await work();
      return true;
    } catch (e) {
      setError(messageOf(e, "Could not save. Please try again."));
      return false;
    } finally {
      busyRef.current = false;
      setBusy(false);
      setStage("");
    }
  }

  async function saveIdentity() {
    if (!facilityId) throw new Error("No facility");
    if (coachId) {
      await getCoachingService().saveCoachOnboardingStep(coachId, 1, stepPayload(1, draft));
      return;
    }
    let staffUserId = draft.userId;
    if (draft.mode === "new") {
      let avatarUrl: string | null = null;
      if (avatarFile) {
        setStage("Uploading photo…");
        avatarUrl = await getStaffService().uploadAvatar(avatarFile);
      }
      setStage("Creating staff account…");
      const p = draft.newPerson;
      const result = await getStaffService().createStaff({
        facilityId,
        firstName: p.firstName.trim(),
        lastName: p.lastName.trim(),
        email: p.email.trim(),
        phone: p.phone.trim() || null,
        roleId: p.roleId,
        avatarUrl,
      });
      staffUserId = result.userId;
      if (result.temporaryPassword) setCredentials({ loginEmail: result.loginEmail, password: result.temporaryPassword });
      setDraft((d) => ({ ...d, mode: "pick", userId: result.userId }));
    }
    setStage("Saving draft…");
    const id = await getCoachingService().startCoachOnboarding(facilityId, staffUserId, {
      displayName: draft.displayName.trim(),
      location: draft.location.trim(),
      timezone: draft.timezone,
      languages: draft.languages,
      shortBio: draft.shortBio.trim(),
      dateOfBirth: draft.dateOfBirth || null,
    });
    setCoachId(id);
  }

  async function saveCurrentStep(): Promise<void> {
    if (step === 1) return saveIdentity();
    if (!coachId) throw new Error("Finish step 1 first.");
    if (step === 4) {
      await getCoachingService().saveCoachOnboardingStep(coachId, 4, stepPayload(4, draft));
      setPayoutStatus("COMPLETE");
      setSavedPayout((s) => s ?? ({ entityType: draft.payout.entityType, payoutMethod: draft.payout.payoutMethod } as NonNullable<CoachOnboarding["payout"]>));
      return;
    }
    if (step === 2 || step === 3) await getCoachingService().saveCoachOnboardingStep(coachId, step, stepPayload(step, draft));
  }

  /** Save the current step and move to the next. The busy lock makes a double-tap a no-op, so step 1 can never create twice. */
  async function saveAndContinue(): Promise<boolean> {
    if (step === 5 || !isStepValid(step, draft, ctx)) return false;
    const ok = await run("Saving…", saveCurrentStep);
    if (ok) setStep((step + 1) as OnboardingStep);
    return ok;
  }

  /** Save what is valid on the current step and let the caller leave; nothing invalid is ever written. */
  async function saveDraft(): Promise<boolean> {
    if (step === 5) return true;
    if (!isStepValid(step, draft, ctx)) {
      // Nothing valid to save on the very first step: say why instead of doing nothing.
      if (step === 1 && !coachId) {
        setError("Fill in the required fields to save a draft.");
        return false;
      }
      return true;
    }
    return run("Saving draft…", saveCurrentStep);
  }

  /** Step 4 can be finished later — skip straight to review. */
  function skipPayout() {
    setStep(5);
  }

  async function complete(): Promise<boolean> {
    if (!coachId || !isStepValid(5, draft, ctx)) return false;
    return run("Submitting…", async () => {
      await getCoachingService().completeCoachOnboarding(coachId, draft.agreements);
      setCompleted({ coachId, name: draft.displayName.trim() });
    });
  }

  async function uploadCertificate(index: number, file: File | undefined) {
    if (!file || !facilityId || !coachId) return;
    const problem = validateCertificateFile(file);
    if (problem) return setError(problem);
    await run("Uploading certificate…", async () => {
      const path = await getCoachingService().uploadCoachCertificate(facilityId, coachId, file);
      setDraft((d) => ({ ...d, certificates: d.certificates.map((c, i) => (i === index ? { ...c, path } : c)) }));
    });
  }

  return {
    step,
    setStep,
    coachId,
    draft,
    patch,
    patchPayout,
    patchNewPerson,
    setPhone,
    toggle,
    pickStaff,
    pickAvatar,
    avatarPreview,
    avatarError,
    candidates,
    roles,
    rolesError,
    loading,
    busy,
    stage,
    error,
    canManagePayouts,
    payoutStatus,
    savedPayout,
    completed,
    credentials,
    stepValid: (s: OnboardingStep) => isStepValid(s, draft, ctx),
    saveAndContinue,
    saveDraft,
    skipPayout,
    complete,
    uploadCertificate,
  };
}

export type CoachOnboardingState = ReturnType<typeof useCoachOnboarding>;
