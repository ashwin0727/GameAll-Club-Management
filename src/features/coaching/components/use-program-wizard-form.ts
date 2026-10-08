"use client";

import { useState } from "react";
import { ServiceError } from "@/services/shared/service-error";
import { getCoachingService } from "@/services/coaching";
import type { CreateProgramInput, DraftProgramBatch, ProgramFeeType, ProgramPaymentMode, ProgramType } from "@/features/coaching/types";

export const PROGRAM_STEPS = ["Basic Information", "Program Details", "Schedule & Batches", "Pricing & Settings", "Review & Create"] as const;
export type ProgramStep = (typeof PROGRAM_STEPS)[number];

export const AGE_GROUPS = ["4-6", "7-10", "11-14", "15-18", "Adults", "All Ages"];
export const SKILL_LEVELS = ["Beginner", "Intermediate", "Advanced", "All Levels"];

/** Program Structure options, per sport — what a Badminton program covers ("Smash", "Net Play")
 *  makes no sense for Cricket, so each sport gets its own vocabulary. Matched against the
 *  facility's own sport name (case-insensitively, by substring so "Box Cricket" still matches
 *  "cricket"); anything not listed falls back to GENERIC_PROGRAM_STRUCTURE. */
const PROGRAM_STRUCTURE_BY_SPORT: Record<string, string[]> = {
  badminton: ["Basic Techniques", "Footwork", "Smash", "Net Play", "Drop Shot", "Game Strategy", "Fitness & Agility", "Match Practice"],
  tennis: ["Forehand", "Backhand", "Serve Technique", "Footwork", "Volley", "Game Strategy", "Fitness & Agility", "Match Practice"],
  cricket: ["Batting Technique", "Bowling Technique", "Fielding Drills", "Wicket-Keeping", "Net Practice", "Game Strategy", "Fitness & Agility", "Match Practice"],
  football: ["Ball Control", "Passing & Dribbling", "Shooting Technique", "Defensive Drills", "Set Pieces", "Game Strategy", "Fitness & Agility", "Match Practice"],
  soccer: ["Ball Control", "Passing & Dribbling", "Shooting Technique", "Defensive Drills", "Set Pieces", "Game Strategy", "Fitness & Agility", "Match Practice"],
  basketball: ["Dribbling", "Shooting Technique", "Passing", "Defense Drills", "Rebounding", "Game Strategy", "Fitness & Agility", "Match Practice"],
  pickleball: ["Dinking", "Serve & Return", "Footwork", "Net Play", "Third Shot Drop", "Game Strategy", "Fitness & Agility", "Match Practice"],
  "table tennis": ["Basic Strokes", "Footwork", "Spin & Serve", "Topspin & Backspin", "Game Strategy", "Fitness & Agility", "Match Practice"],
  squash: ["Basic Strokes", "Footwork", "Serve Technique", "Court Positioning", "Game Strategy", "Fitness & Agility", "Match Practice"],
  swimming: ["Stroke Technique", "Breathing Drills", "Starts & Turns", "Endurance Building", "Fitness & Agility", "Race Practice"],
};
const GENERIC_PROGRAM_STRUCTURE = ["Basic Techniques", "Footwork", "Game Strategy", "Fitness & Agility", "Match Practice"];

/** Resolves the Program Structure chip list for a sport name (e.g. from `useFacilitySportOptions`) —
 *  a generic list until a sport is chosen, so step 2 never shows an empty picker. */
export function programStructurePresetsForSport(sportName: string | undefined | null): string[] {
  if (!sportName) return GENERIC_PROGRAM_STRUCTURE;
  const key = Object.keys(PROGRAM_STRUCTURE_BY_SPORT).find((k) => sportName.toLowerCase().includes(k));
  return key ? PROGRAM_STRUCTURE_BY_SPORT[key]! : GENERIC_PROGRAM_STRUCTURE;
}

export const SESSION_DURATIONS = [
  { value: "30", label: "30 minutes" },
  { value: "60", label: "1 Hour" },
  { value: "120", label: "2 Hours" },
  { value: "custom", label: "Custom" },
];
export const SESSIONS_PER_WEEK = [1, 2, 3, 4, 5];
/** value = weeks. "Custom" lets the owner pick an end date directly instead. */
export const PROGRAM_DURATIONS = [
  { value: "4", label: "1 Month (4 Weeks)" },
  { value: "8", label: "2 Months (8 Weeks)" },
  { value: "12", label: "3 Months (12 Weeks)" },
  { value: "24", label: "6 Months (24 Weeks)" },
  { value: "48", label: "12 Months (48 Weeks)" },
  { value: "custom", label: "Custom" },
];
export const DAY_LABELS_SHORT = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

export const IMAGE_MAX_BYTES = 5 * 1024 * 1024;
export const IMAGE_ACCEPT = ["image/jpeg", "image/png", "image/webp"];

export interface WeeklyScheduleDraft {
  daysOfWeek: number[];
  startTime: string;
  endTime: string;
  courtId: string;
  coachId: string;
}

function todayIso(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

/** Adds `weeks` weeks to an ISO date, returning an ISO date — pure, no Date-object leakage. */
export function addWeeksIso(iso: string, weeks: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  const date = new Date(y!, (m ?? 1) - 1, d ?? 1);
  date.setDate(date.getDate() + weeks * 7);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

/**
 * All Create Coaching Program wizard state and submit logic — one hook, so the single wizard
 * component just renders fields off it rather than each step owning its own state (this program
 * is a single atomic create, unlike Add Coach's page-vs-sheet reuse need).
 */
export function useProgramWizardForm(facilityId: string | null) {
  const [step, setStep] = useState<ProgramStep>("Basic Information");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Step 1 — Basic Information
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [facilitySportId, setFacilitySportId] = useState("");
  const [programType, setProgramType] = useState<ProgramType>("GROUP");
  const [ageGroup, setAgeGroup] = useState("11-14");
  const [level, setLevel] = useState("Beginner");
  const [highlights, setHighlights] = useState<string[]>([]);
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [imageError, setImageError] = useState<string | null>(null);
  const [uploadingImage, setUploadingImage] = useState(false);

  // Step 2 — Program Details
  const [sessionDuration, setSessionDuration] = useState("60");
  const [sessionDurationCustomMinutes, setSessionDurationCustomMinutes] = useState("");
  const [sessionsPerWeek, setSessionsPerWeek] = useState(3);
  const [durationWeeks, setDurationWeeks] = useState("12");
  const [startDate, setStartDate] = useState(todayIso());
  const [customEndDate, setCustomEndDate] = useState("");
  const [maxCapacity, setMaxCapacity] = useState("20");
  const [minCapacity, setMinCapacity] = useState("");
  const [sessionFormat, setSessionFormat] = useState("");

  // Step 3 — Schedule & Batches
  const [weeklySchedule, setWeeklySchedule] = useState<WeeklyScheduleDraft>({
    daysOfWeek: [1, 3, 5],
    startTime: "16:00",
    endTime: "17:00",
    courtId: "",
    coachId: "",
  });
  const [batches, setBatches] = useState<DraftProgramBatch[]>([]);

  // Step 4 — Pricing & Settings
  const [feeStructure, setFeeStructure] = useState<"SINGLE" | "PER_SESSION">("SINGLE");
  const [programFee, setProgramFee] = useState("");
  const [paymentMode, setPaymentMode] = useState<ProgramPaymentMode>("BOTH");
  const [feeType, setFeeTypeState] = useState<ProgramFeeType>("ONE_TIME");
  // A monthly fee is one flat amount per month, so "Per Session Fee" does not apply to it.
  function setFeeType(next: ProgramFeeType) {
    setFeeTypeState(next);
    if (next === "MONTHLY") setFeeStructure("SINGLE");
  }
  const [earlyBirdDiscount, setEarlyBirdDiscount] = useState("");
  const [discountValidTill, setDiscountValidTill] = useState("");
  const [taxApplicable, setTaxApplicable] = useState(false);
  const [taxPercent, setTaxPercent] = useState("18");
  const [paymentNotes, setPaymentNotes] = useState("");
  const [allowWaitlist, setAllowWaitlist] = useState(true);
  const [allowTrialSession, setAllowTrialSession] = useState(true);
  const [autoEnrollNextBatch, setAutoEnrollNextBatch] = useState(false);
  const [sendNotifications, setSendNotifications] = useState(true);
  const [visibleInBooking, setVisibleInBooking] = useState(false);
  const [enrollmentDeadlineEnabled, setEnrollmentDeadlineEnabled] = useState(false);
  const [enrollmentDeadline, setEnrollmentDeadline] = useState("");

  const endDate = durationWeeks === "custom" ? customEndDate : addWeeksIso(startDate, Number(durationWeeks));

  function toggleHighlight(list: string[], setList: (v: string[]) => void, value: string) {
    setList(list.includes(value) ? list.filter((v) => v !== value) : [...list, value]);
  }

  function pickImage(file: File | undefined) {
    if (!file) return;
    setImageError(null);
    if (!IMAGE_ACCEPT.includes(file.type)) {
      setImageError("Please choose a JPG, PNG or WEBP image.");
      return;
    }
    if (file.size > IMAGE_MAX_BYTES) {
      setImageError("That image is larger than 5MB.");
      return;
    }
    setImageFile(file);
    setImagePreview((prev) => {
      if (prev) URL.revokeObjectURL(prev);
      return URL.createObjectURL(file);
    });
  }

  function addBatch(batch: DraftProgramBatch) {
    setBatches((b) => [...b, batch]);
  }
  function removeBatch(index: number) {
    setBatches((b) => b.filter((_, i) => i !== index));
  }

  const priceInr = programFee.trim() ? Number(programFee) : 0;
  const discountInr = earlyBirdDiscount.trim() ? Number(earlyBirdDiscount) : 0;
  const effectiveSessionDuration = sessionDuration === "custom" ? Number(sessionDurationCustomMinutes) || 0 : Number(sessionDuration);

  // How many weeks the program actually runs — from the chosen preset, or from the custom
  // start/end dates when "Custom" duration is picked (0 until both dates make sense).
  const weeksInProgram =
    durationWeeks === "custom"
      ? startDate && customEndDate && customEndDate >= startDate
        ? Math.max(1, Math.round((new Date(customEndDate).getTime() - new Date(startDate).getTime()) / (7 * 86_400_000)))
        : 0
      : Number(durationWeeks) || 0;
  const totalSessionsInProgram = sessionsPerWeek * weeksInProgram;
  // A "Per Session Fee" is charged per session actually held over the program's run, so a
  // student's real total is that rate times every session — not the raw number typed in.
  const perStudentBaseFeeInr = feeStructure === "PER_SESSION" ? priceInr * totalSessionsInProgram : priceInr;
  const taxInr = taxApplicable ? Math.round(((perStudentBaseFeeInr - discountInr) * Number(taxPercent || 0)) / 100) : 0;
  const totalFeeInr = Math.max(0, perStudentBaseFeeInr - discountInr) + taxInr;

  const step1Valid = Boolean(name.trim() && description.trim() && facilitySportId && ageGroup && level);
  const step2Valid =
    effectiveSessionDuration > 0 &&
    Number(maxCapacity) > 0 &&
    (!minCapacity.trim() || Number(minCapacity) <= Number(maxCapacity)) &&
    Boolean(startDate) &&
    (durationWeeks !== "custom" || Boolean(customEndDate)) &&
    (durationWeeks === "custom" ? customEndDate >= startDate : true);
  // Exactly one batch — a program's schedule is a single day/time/court/coach combination, not a
  // list of alternatives.
  const step3Valid = batches.length === 1;
  const step4Valid =
    priceInr >= 0 &&
    (feeType === "ONE_TIME" || priceInr > 0) &&
    discountInr <= perStudentBaseFeeInr &&
    (!enrollmentDeadlineEnabled || Boolean(enrollmentDeadline));
  const canSubmit = step1Valid && step2Valid && step3Valid && step4Valid;

  function goTo(target: ProgramStep) {
    setStep(target);
  }
  function next() {
    const i = PROGRAM_STEPS.indexOf(step);
    if (i < PROGRAM_STEPS.length - 1) setStep(PROGRAM_STEPS[i + 1]!);
  }
  function back() {
    const i = PROGRAM_STEPS.indexOf(step);
    if (i > 0) setStep(PROGRAM_STEPS[i - 1]!);
  }

  function buildInput(status: "DRAFT" | "ACTIVE"): CreateProgramInput {
    if (!facilityId) throw new Error("No facility");
    return {
      facilityId,
      name: name.trim(),
      description: description.trim(),
      facilitySportId,
      programType,
      ageGroup,
      level,
      programStructure: highlights,
      imageUrl: null, // filled in after upload, see submit()
      defaultDurationMinutes: effectiveSessionDuration,
      sessionsPerWeek,
      defaultCapacity: Number(maxCapacity),
      minCapacity: minCapacity.trim() ? Number(minCapacity) : null,
      startDate,
      endDate,
      sessionFormat: sessionFormat.trim() || null,
      // Stored as the base per-student fee (before discount/tax) regardless of how it was entered
      // — a Per Session Fee is already multiplied out to the program's real total sessions here.
      defaultPriceMinor: perStudentBaseFeeInr > 0 ? Math.round(perStudentBaseFeeInr * 100) : null,
      paymentMode,
      feeType,
      earlyBirdDiscountMinor: discountInr > 0 ? Math.round(discountInr * 100) : null,
      discountValidTill: discountValidTill.trim() || null,
      taxPercent: taxApplicable ? Number(taxPercent) : null,
      paymentNotes: paymentNotes.trim() || null,
      allowWaitlist,
      allowTrialSession,
      autoEnrollNextBatch,
      sendNotifications,
      visibleInBooking,
      enrollmentDeadline: enrollmentDeadlineEnabled && enrollmentDeadline.trim() ? enrollmentDeadline : null,
      status,
      batches,
    };
  }

  async function submit(status: "DRAFT" | "ACTIVE" = "ACTIVE"): Promise<string> {
    if (status === "ACTIVE" && !canSubmit) throw new Error("Form is incomplete");
    setBusy(true);
    setError(null);
    try {
      let imageUrl: string | null = null;
      if (imageFile) {
        setUploadingImage(true);
        try {
          imageUrl = await getCoachingService().uploadProgramImage(imageFile);
        } finally {
          setUploadingImage(false);
        }
      }
      const programId = await getCoachingService().createProgramFull({ ...buildInput(status), imageUrl });
      return programId;
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not create the program.");
      throw e;
    } finally {
      setBusy(false);
    }
  }

  return {
    step,
    setStep: goTo,
    next,
    back,
    busy,
    uploadingImage,
    error,
    name,
    setName,
    description,
    setDescription,
    facilitySportId,
    setFacilitySportId,
    programType,
    setProgramType,
    ageGroup,
    setAgeGroup,
    level,
    setLevel,
    highlights,
    setHighlights,
    toggleHighlight,
    imagePreview,
    imageError,
    pickImage,
    sessionDuration,
    setSessionDuration,
    sessionDurationCustomMinutes,
    setSessionDurationCustomMinutes,
    effectiveSessionDuration,
    sessionsPerWeek,
    setSessionsPerWeek,
    durationWeeks,
    setDurationWeeks,
    startDate,
    setStartDate,
    customEndDate,
    setCustomEndDate,
    endDate,
    maxCapacity,
    setMaxCapacity,
    minCapacity,
    setMinCapacity,
    sessionFormat,
    setSessionFormat,
    weeklySchedule,
    setWeeklySchedule,
    batches,
    addBatch,
    removeBatch,
    feeStructure,
    setFeeStructure,
    programFee,
    setProgramFee,
    paymentMode,
    setPaymentMode,
    feeType,
    setFeeType,
    earlyBirdDiscount,
    setEarlyBirdDiscount,
    discountValidTill,
    setDiscountValidTill,
    taxApplicable,
    setTaxApplicable,
    taxPercent,
    setTaxPercent,
    paymentNotes,
    setPaymentNotes,
    allowWaitlist,
    setAllowWaitlist,
    allowTrialSession,
    setAllowTrialSession,
    autoEnrollNextBatch,
    setAutoEnrollNextBatch,
    sendNotifications,
    setSendNotifications,
    visibleInBooking,
    setVisibleInBooking,
    enrollmentDeadlineEnabled,
    setEnrollmentDeadlineEnabled,
    enrollmentDeadline,
    setEnrollmentDeadline,
    priceInr,
    discountInr,
    taxInr,
    totalFeeInr,
    weeksInProgram,
    totalSessionsInProgram,
    perStudentBaseFeeInr,
    step1Valid,
    step2Valid,
    step3Valid,
    step4Valid,
    canSubmit,
    submit,
  };
}

export type ProgramWizardFormState = ReturnType<typeof useProgramWizardForm>;
