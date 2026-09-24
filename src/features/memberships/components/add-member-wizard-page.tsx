"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQueryClient } from "@tanstack/react-query";
import { ArrowLeft, ArrowRight, Camera, CalendarDays, Check, ChevronRight, Info, X } from "lucide-react";
import { addDays, format, parseISO } from "date-fns";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { SelectField } from "@/components/shared/select-field";
import { DatePicker } from "@/components/shared/date-picker";
import { PlayingSchedulePicker } from "@/features/memberships/components/playing-schedule-picker";
import { MembershipReviewStep } from "@/features/memberships/components/membership-review-step";
import { MemberContextPanel } from "@/features/memberships/components/member-context-panel";
import { PaymentStep, PAYMENT_TAB_COPY } from "@/features/memberships/components/payment-step";
import { WizardStepper } from "@/features/memberships/components/wizard-stepper";
import {
  charges as computeCharges,
  composeAddress,
  composeNotes,
  composePaymentNotes,
  fieldErrors,
  furthestReachableStep,
  validateStep,
  WIZARD_STEPS,
  type WizardDraft,
  type WizardStep,
} from "@/features/memberships/add-member-wizard";
import { durationLabel, monthlyEquivalentInr, planBadges, planFeatures, splitPlanName, type PlanBadge } from "@/features/memberships/plan-insights";
import { PLAN_CARD_THEMES } from "@/features/memberships/components/plan-card";
import { useAllMemberships } from "@/features/memberships/hooks/use-membership-dashboard";
import { findMatchingBatch, groupContiguousRanges } from "@/features/memberships/playing-schedule";
import { plansForSport } from "@/features/memberships/sport-scope";
import { useFacilityBatches } from "@/features/membership-sessions/hooks/use-facility-batches";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { useActiveFacilitySportId } from "@/features/facility/hooks/use-active-facility-sport";
import { getMembershipService } from "@/services/memberships";
import { getMembershipSessionService } from "@/services/membership-sessions";
import { ServiceError } from "@/services/shared/service-error";
import type { MembershipListRow, MembershipPlan } from "@/features/memberships/types";
import type { MembershipBatch } from "@/features/membership-sessions/types";
import { cn } from "@/lib/utils";

const GLASS =
  "border-0 bg-card/70 shadow-[0_6px_24px_rgba(16,40,34,0.07)] ring-1 ring-white/60 backdrop-blur-md dark:bg-card/50 dark:ring-white/10";
const PANEL_TINT = "#EAF9F1";

const GENDERS = [
  { value: "", label: "Select" },
  { value: "male", label: "Male" },
  { value: "female", label: "Female" },
  { value: "other", label: "Other" },
];

const COUNTRY_CODES = [
  { value: "+91", label: "+91" },
  { value: "+1", label: "+1" },
  { value: "+44", label: "+44" },
  { value: "+971", label: "+971" },
];

const MAX_PHOTO_BYTES = 2 * 1024 * 1024;
/** A stable empty array, so a `?? EMPTY_ROWS` fallback doesn't create a new reference every render. */
const EMPTY_ROWS: MembershipListRow[] = [];
const EMPTY_BATCHES: MembershipBatch[] = [];
/** Court/day/time slots aren't capacity-limited — this is just the (non-zero) value the
 *  database column still requires when a new batch is created. */
const UNLIMITED_BATCH_CAPACITY = 999;

/**
 * The design's "Upload Photo" box. There's nowhere for this photo to go yet — `members` has no
 * photo column and no storage bucket is wired up for it — so this only previews the chosen
 * image locally; it is NOT sent anywhere, and the preview is discarded, not the member's photo,
 * if the page is left. See the note in the PR/summary about what a real implementation needs.
 */
function PhotoUpload({ preview, onChange }: { preview: string | null; onChange: (url: string | null) => void }) {
  const [error, setError] = useState<string | null>(null);

  function pick(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;
    if (!["image/jpeg", "image/png"].includes(file.type)) return setError("JPG or PNG only.");
    if (file.size > MAX_PHOTO_BYTES) return setError("Max 2MB.");
    setError(null);
    onChange(URL.createObjectURL(file));
  }

  function remove() {
    if (preview) URL.revokeObjectURL(preview);
    onChange(null);
    setError(null);
  }

  return (
    // The outer wrapper is a plain div — the Remove button below is its own sibling, not a
    // descendant of the upload <label>, so clicking it can never also re-trigger the file
    // picker the way a nested button inside a <label> risks doing.
    <div className="relative">
      {/* The dashed border belongs to this outer card, not the circle — the circle just holds
          the photo (or a blank placeholder) with a plain edge, matching the reference design. */}
      <label className="flex cursor-pointer flex-col items-center gap-2 rounded-xl border-2 border-dashed border-input bg-muted/20 p-4 text-center transition-colors hover:border-blue-400 hover:bg-blue-500/5">
        {/* The camera badge sits on this wrapper, not inside the circle below — the circle
            needs overflow-hidden to mask the photo round, and that same clipping was cutting
            the badge off at the corner where the circle curves away. */}
        <span className="relative flex h-16 w-16 shrink-0">
          <span className="flex h-full w-full items-center justify-center overflow-hidden rounded-full bg-muted">
            {preview ? (
              // eslint-disable-next-line @next/next/no-img-element -- a local object URL, not a remote/optimizable image
              <img src={preview} alt="" className="h-full w-full object-cover" />
            ) : (
              <span className="text-2xl text-muted-foreground">🙂</span>
            )}
          </span>
          <span className="absolute bottom-0 right-0 z-10 flex h-6 w-6 items-center justify-center rounded-full bg-blue-600 text-white ring-2 ring-card">
            <Camera className="h-3 w-3" aria-hidden />
          </span>
        </span>
        <span className="text-xs font-semibold text-foreground">{preview ? "Change Photo" : "Upload Photo"}</span>
        <span className="text-[11px] text-muted-foreground">JPG, PNG (Max 2MB)</span>
        {error && <span className="text-[11px] text-destructive">{error}</span>}
        <input type="file" accept="image/png,image/jpeg" onChange={pick} className="sr-only" aria-label="Upload photo" />
      </label>

      {preview && (
        <button
          type="button"
          onClick={remove}
          aria-label="Remove photo"
          className="absolute -right-2 -top-2 flex h-6 w-6 items-center justify-center rounded-full bg-destructive text-white shadow-sm ring-2 ring-card transition-opacity hover:opacity-90"
        >
          <X className="h-3.5 w-3.5" aria-hidden />
        </button>
      )}
    </div>
  );
}

/**
 * One plan in Step 2's picker — the same colour theme, badge and feature-checklist styling as
 * the Membership Plans page's `PlanCard`, plus a radio indicator for being the chosen one. The
 * design shows these stacked vertically; here they sit in a grid that runs them horizontally
 * once there's room (desktop) and folds back to one column as the viewport narrows.
 */
function SelectablePlanCard({
  plan,
  badge,
  index,
  chosen,
  onChoose,
}: {
  plan: MembershipPlan;
  badge?: PlanBadge | string;
  index: number;
  chosen: boolean;
  onChoose: () => void;
}) {
  const theme = PLAN_CARD_THEMES[index % PLAN_CARD_THEMES.length]!;
  const name = splitPlanName(plan.name);
  const perMonth = monthlyEquivalentInr(plan.priceInr, plan.durationDays);
  const months = Math.max(1, Math.round(plan.durationDays / 30));

  return (
    <button
      type="button"
      onClick={onChoose}
      aria-pressed={chosen}
      className={cn(
        "relative flex h-full flex-col rounded-2xl p-4 text-left transition-colors",
        theme.surface,
        chosen ? "ring-2 ring-[#0B9B63]" : "border border-border/60 hover:brightness-[0.98]",
      )}
    >
      {badge && (
        <span className={cn("absolute right-11 top-3 rounded-full px-2.5 py-1 text-[11px] font-semibold", theme.badge)}>
          {badge}
        </span>
      )}
      <span
        className={cn(
          "absolute right-3 top-3 flex h-6 w-6 shrink-0 items-center justify-center rounded-full border-2",
          chosen ? "border-[#0B9B63] bg-[#0B9B63]" : "border-input bg-card",
        )}
        aria-hidden
      >
        {chosen && <Check className="h-3.5 w-3.5 text-white" strokeWidth={3} />}
      </span>

      <span className={cn("flex h-11 w-11 items-center justify-center rounded-xl", theme.chip)}>
        <CalendarDays className="h-5 w-5" aria-hidden />
      </span>

      <p className="mt-3 break-words pr-8 text-[15px] font-bold leading-snug text-black dark:text-foreground">{name.main}</p>
      {name.detail && <p className="text-xs text-muted-foreground">{name.detail}</p>}
      <p className="mt-0.5 text-xs text-muted-foreground">Valid for {durationLabel(plan.durationDays)}</p>

      <p className="mt-3 flex items-baseline gap-1.5 whitespace-nowrap">
        <span className="text-xl font-bold tabular-nums text-black dark:text-foreground">{inr(plan.priceInr)}</span>
        <span className="text-xs text-muted-foreground">{months === 1 ? "/ month" : `/ ${durationLabel(plan.durationDays)}`}</span>
      </p>
      {months > 1 && <p className="text-xs text-muted-foreground">({inr(perMonth)} / month)</p>}

      <ul className="mt-3 flex-1 space-y-2">
        {planFeatures(plan).map((f) => (
          <li key={f} className="flex items-start gap-2 text-xs text-foreground/85">
            <span className={cn("mt-0.5 flex h-3.5 w-3.5 shrink-0 items-center justify-center rounded-full", theme.tick)}>
              <Check className="h-2 w-2 text-white" strokeWidth={4} aria-hidden />
            </span>
            <span>{f}</span>
          </li>
        ))}
      </ul>
    </button>
  );
}

function todayIso(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
function inr(v: number): string {
  return `₹${v.toLocaleString("en-IN")}`;
}

/**
 * Kept as plain digits for +91 (India), matching how every other phone number in the app is
 * stored — with the code prefixed only for a non-default country, so an international number
 * isn't silently stripped down to something that no longer dials.
 */
function composePhone(countryCode: string, phone: string): string {
  const digits = phone.replace(/\D/g, "");
  return countryCode === "+91" ? digits : `${countryCode} ${digits}`;
}

/**
 * Strips anything that isn't a digit as it's typed, and caps the result at `max` digits — so a
 * phone box simply can't hold an 11th digit rather than accepting it and only complaining once
 * you try to move on.
 */
function capDigits(value: string, max: number): string {
  return value.replace(/\D/g, "").slice(0, max);
}

function clampNumber(digits: string, min: number, max: number): number {
  if (!digits) return 0;
  return Math.min(max, Math.max(min, Number(digits)));
}

function Field({
  label,
  required,
  error,
  children,
}: {
  label: string;
  required?: boolean;
  /** Shown under the field in red once the step has been touched. */
  error?: string;
  children: React.ReactNode;
}) {
  // A plain <div>, not a <label> wrapping the control — a <label> counts its entire box
  // (including the blank space around a short caption) as clickable and activates whatever's
  // inside it, which is what was opening dropdowns and focusing inputs on a click nowhere near
  // them. Each control keeps its own accessible name (aria-label / visible text) instead.
  return (
    <div className="space-y-1.5">
      <p className="text-xs font-medium text-foreground/80">
        {label} {required && <span className="text-destructive">*</span>}
      </p>
      {children}
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  );
}

/**
 * Add New Member, as a five-step wizard: who they are, which plan, when they play, a review,
 * then payment. It submits through the same `createMembershipFull` call the single-page form
 * uses, so a member created here is identical to one created there.
 */
export function AddMemberWizardPage() {
  const router = useRouter();
  const queryClient = useQueryClient();
  const { data: facility, isLoading: facilityLoading } = useFacility();
  const facilityId = facility?.id ?? null;
  const activeSportId = useActiveFacilitySportId(facilityId);

  const [step, setStep] = useState<WizardStep>(1);
  const [allPlans, setAllPlans] = useState<MembershipPlan[]>([]);
  const batches = useFacilityBatches(facilityId).data ?? EMPTY_BATCHES;
  // Scoped to the top bar's active sport — a member can only join a plan for whichever sport is
  // currently selected up there; joining the other sport's plan means switching sport first, the
  // same rule Court Access already enforces when a plan is created.
  const plans = useMemo(() => plansForSport(allPlans, batches, activeSportId), [allPlans, batches, activeSportId]);
  // Only for working out the "Most Popular" / "Best Value" badges the same way the Membership
  // Plans page does — this wizard doesn't otherwise need the facility's existing memberships.
  const membershipRows = useAllMemberships(facilityId).data ?? EMPTY_ROWS;
  const planBadgeMap = useMemo(() => planBadges(plans, membershipRows), [plans, membershipRows]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // Set once "Generate Payment Link" succeeds — the member already exists at that point (see
  // the submit-flow note below), so the page then shows the link instead of the button. Every
  // detail is locked from here on: changing the plan/schedule/amount now would no longer match
  // what the link/mandate was generated for, so further edits happen on the Edit Membership page
  // instead, after payment.
  const [linkResult, setLinkResult] = useState<{ shortUrl: string | null; membershipId: string } | null>(null);
  const [generatingLink, setGeneratingLink] = useState(false);
  const [linkError, setLinkError] = useState<string | null>(null);
  // Which fields the member has left, so each one's error can show as soon as they move on
  // from it — not only once they've tried to click Next.
  const [touchedFields, setTouchedFields] = useState<Set<string>>(new Set());
  const touch = (field: string) => setTouchedFields((prev) => (prev.has(field) ? prev : new Set(prev).add(field)));
  // While a field is focused, its error is hidden even if it was left invalid before — so
  // fixing a mistake doesn't flash a red message back at you on every keystroke before you're
  // done typing. It reappears, if still wrong, once you leave the field again.
  const [focusedField, setFocusedField] = useState<string | null>(null);
  const focusProps = (field: string) => ({
    onFocus: () => setFocusedField(field),
    onBlur: () => {
      setFocusedField((f) => (f === field ? null : f));
      touch(field);
    },
  });
  const [photoPreview, setPhotoPreview] = useState<string | null>(null);

  const [draft, setDraft] = useState<WizardDraft>({
    fullName: "",
    countryCode: "+91",
    phone: "",
    email: "",
    dateOfBirth: "",
    gender: "",
    address: "",
    city: "",
    pincode: "",
    emergencyName: "",
    emergencyCountryCode: "+91",
    emergencyPhone: "",
    sendWelcome: true,
    planId: "",
    planName: "",
    startDate: todayIso(),
    durationDays: 0,
    membershipFeeInr: 0,
    registrationFeeInr: 0,
    gstPercent: 0,
    // Mon - Fri seeded once, right here in the wizard's own initial state — not by an effect
    // inside PlayingSchedulePicker, which unmounts every time the step is left and remounts
    // fresh on return. An effect-based seed can't tell "never touched" apart from "the member
    // clicked Custom to clear it and hasn't picked a day yet" — both look like an empty array
    // — so it kept quietly overwriting a Custom choice back to Mon-Fri on every revisit.
    schedule: { facilitySportId: "", courtId: "", daysOfWeek: [1, 2, 3, 4, 5], times: [] },
    paymentTab: "link",
    paymentAmount: 0,
    paymentDate: todayIso(),
    paymentMethod: "Cash",
    paymentReference: "",
    receivedFrom: "",
    collectedBy: "",
    paymentNotes: "",
  });

  const set = <K extends keyof WizardDraft>(key: K, value: WizardDraft[K]) =>
    setDraft((d) => ({ ...d, [key]: value }));

  useEffect(() => {
    if (!facilityId) return;
    let cancelled = false;
    getMembershipService()
      .getFacilityPlans(facilityId, { activeOnly: true })
      .then((p) => !cancelled && setAllPlans(p))
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [facilityId]);

  const charges = useMemo(() => computeCharges(draft), [draft]);
  // The plan's own length laid out from the chosen start date — shown, not edited, here.
  const planEndDate = useMemo(
    () => (draft.startDate && draft.durationDays ? addDays(parseISO(draft.startDate), draft.durationDays - 1) : null),
    [draft.startDate, draft.durationDays],
  );
  const scheduleRanges = useMemo(() => groupContiguousRanges(draft.schedule.times), [draft.schedule.times]);
  const errors = useMemo(() => fieldErrors(step, draft), [step, draft]);
  const stepError = validateStep(step, draft);
  const furthest = furthestReachableStep(draft);
  // Shown as soon as a field is left (blurred), or once Next/Create has been tried — not while
  // it's still being typed into for the first time.
  const show = (field: string): string | undefined =>
    touchedFields.has(field) && focusedField !== field ? errors[field] : undefined;
  const invalid = (field: string) => (show(field) ? "border-destructive focus-visible:ring-destructive" : "");

  function next() {
    if (stepError) {
      setTouchedFields(new Set(Object.keys(errors)));
      return;
    }
    setTouchedFields(new Set());
    setStep((s) => Math.min(5, s + 1) as WizardStep);
  }

  function choosePlan(plan: MembershipPlan) {
    setDraft((d) => ({
      ...d,
      planId: plan.id,
      planName: plan.name,
      durationDays: plan.durationDays,
      membershipFeeInr: plan.priceInr,
      // The plan's own default joining fee, carried over as this membership's starting
      // registration fee — still just a starting point, editable right below like always.
      registrationFeeInr: plan.joiningFeeInr ?? d.registrationFeeInr,
    }));
  }

  // "Amount to Collect" follows the plan's price (+ GST/registration) until the member edits
  // it by hand via "Edit Amount" — once it's been set to anything non-zero, plan/fee changes
  // stop overwriting it.
  useEffect(() => {
    setDraft((d) => {
      const total = computeCharges(d).total;
      return d.paymentAmount === 0 && total > 0 ? { ...d, paymentAmount: total } : d;
    });
  }, [draft.membershipFeeInr, draft.gstPercent, draft.registrationFeeInr]);

  // "Received From" defaults to the member's own name — they're almost always the one paying —
  // seeded once, the first time the member actually reaches the Payment step (so it's the final
  // name, not whatever was typed so far), and never overwritten again after that.
  const receivedFromSeededRef = useRef(false);
  useEffect(() => {
    if (step !== 5 || receivedFromSeededRef.current) return;
    receivedFromSeededRef.current = true;
    setDraft((d) => (d.receivedFrom ? d : { ...d, receivedFrom: d.fullName.trim() }));
  }, [step]);

  /**
   * Creates the membership itself — shared by all three Payment tabs, which only differ in
   * what `paymentMode`/`paymentMethods`/`recurring`/notes they pass in. Non-adjacent playing
   * hours (e.g. 6-7 AM and 2-4 PM) become separate ranges: the first rides along with the
   * membership itself, any further ones are their own batch, created and assigned once the
   * membership exists.
   *
   * A court/day/time slot isn't exclusive to one member — several members can share the same
   * recurring batch. So each range first looks for an existing active batch that's an exact
   * match (same court, clock range and days) and joins it; only when there's no match does it
   * create a new one. New batches get a generously high capacity since slots aren't capped.
   */
  async function createTheMember(opts: {
    paymentMode: "PAID" | "PENDING" | "FREE";
    paymentMethods: string[];
    recurring: boolean;
  }) {
    if (!facilityId) throw new Error("No facility");
    const ranges = groupContiguousRanges(draft.schedule.times);
    const [firstRange, ...extraRanges] = ranges;
    const notes = [composeNotes(draft), composePaymentNotes(draft)].filter(Boolean).join("\n") || undefined;

    const existingBatches = ranges.length > 0 ? await getMembershipService().listAssignableBatches(facilityId) : [];
    const matchFor = (range: { startTime: string; endTime: string }) =>
      findMatchingBatch(existingBatches, {
        courtId: draft.schedule.courtId,
        daysOfWeek: draft.schedule.daysOfWeek,
        startTime: range.startTime,
        endTime: range.endTime,
      });

    const firstMatch = firstRange ? matchFor(firstRange) : undefined;

    const membership = await getMembershipService().createMembershipFull({
      facilityId,
      fullName: draft.fullName.trim(),
      phone: composePhone(draft.countryCode, draft.phone),
      email: draft.email.trim() || undefined,
      dateOfBirth: draft.dateOfBirth || undefined,
      gender: draft.gender || undefined,
      address: composeAddress(draft),
      name: draft.planName || undefined,
      membershipType: "INDIVIDUAL",
      maxFamilyMembers: 1,
      startDate: draft.startDate,
      durationDays: draft.durationDays,
      batchId: firstMatch?.batchId,
      newBatch:
        firstRange && !firstMatch
          ? {
              courtId: draft.schedule.courtId,
              facilitySportId: draft.schedule.facilitySportId,
              daysOfWeek: draft.schedule.daysOfWeek,
              startTime: firstRange.startTime,
              endTime: firstRange.endTime,
              capacity: UNLIMITED_BATCH_CAPACITY,
            }
          : undefined,
      membershipFeeInr: draft.paymentAmount || charges.subTotal,
      registrationFeeInr: charges.registration,
      gstPercent: draft.gstPercent,
      paymentMode: opts.paymentMode,
      paymentMethods: opts.paymentMethods,
      paymentReference: draft.paymentReference.trim() || undefined,
      recurring: opts.recurring,
      notes,
    });

    for (const range of extraRanges) {
      const match = matchFor(range);
      const batchId =
        match?.batchId ??
        (
          await getMembershipSessionService().createBatch({
            facilityId,
            planId: draft.planId,
            facilitySportId: draft.schedule.facilitySportId,
            courtId: draft.schedule.courtId,
            name: `${draft.fullName.trim()} — ${range.startTime}`,
            daysOfWeek: draft.schedule.daysOfWeek,
            startTime: range.startTime,
            endTime: range.endTime,
            capacity: UNLIMITED_BATCH_CAPACITY,
          })
        ).id;
      await getMembershipService().assignMembershipToBatch(batchId, membership.memberId, membership.id);
    }

    queryClient.invalidateQueries({ queryKey: ["membership-list"] });
    queryClient.invalidateQueries({ queryKey: ["membership-summary"] });
    queryClient.invalidateQueries({ queryKey: ["membership-revenue"] });
    queryClient.invalidateQueries({ queryKey: ["membership-dashboard-rows"] });
    return membership;
  }

  /**
   * "Record Offline Payment" / "Mark as Paid" — payment is already collected, so the member is
   * created as fully paid and the wizard returns to the dashboard.
   *
   * Except when a payment link was already generated first (member picked "Mark as Paid" after
   * generating a Razorpay link and getting paid another way instead): the member and their
   * recurring subscription already exist in that case, so this instead marks the *existing*
   * membership paid and cancels the now-unwanted Razorpay mandate — it must never create a
   * second member, and the link must actually stop working rather than just being ignored.
   */
  async function submit() {
    if (!facilityId || stepError) {
      setTouchedFields(new Set(Object.keys(errors)));
      return;
    }
    setSaving(true);
    setError(null);
    try {
      if (linkResult) {
        if (!linkResult.membershipId) {
          // Guards against a stale dev-server Fast Refresh carrying over an older shape of this
          // state (before membershipId was added here) — a hard refresh and re-generating the
          // link clears it. Shouldn't be reachable outside that.
          throw new ServiceError("DATABASE_ERROR", "Something went wrong with this payment link — please regenerate it and try again.");
        }
        await getMembershipService().recordMembershipPayment(linkResult.membershipId, draft.paymentMethod);
        await getMembershipService().cancelMembershipSubscription(linkResult.membershipId);
      } else {
        await createTheMember({ paymentMode: "PAID", paymentMethods: [draft.paymentMethod], recurring: false });
      }
      router.push("/memberships/v1");
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to create this member.");
      setSaving(false);
    }
  }

  /**
   * "Generate Payment Link" — per the chosen flow, the member is created right away (Payment
   * Incomplete), the same moment as generating the Razorpay subscription mandate; the club
   * doesn't wait for the member to actually pay before they show up in the member list. The
   * subscription bills this amount now and the same amount again every month on this date,
   * automatically, until cancelled.
   */
  async function generateLink() {
    if (!facilityId || stepError) {
      setTouchedFields(new Set(Object.keys(errors)));
      return;
    }
    setGeneratingLink(true);
    setLinkError(null);
    try {
      const membership = await createTheMember({ paymentMode: "PENDING", paymentMethods: [], recurring: true });
      const sub = await getMembershipService().createMembershipSubscription(membership.id);
      setLinkResult({ shortUrl: sub.shortUrl, membershipId: membership.id });
    } catch (err) {
      setLinkError(err instanceof ServiceError ? err.message : "Unable to generate the payment link.");
    } finally {
      setGeneratingLink(false);
    }
  }

  if (facilityLoading) {
    return (
      <div className="space-y-5">
        <Skeleton className="h-24 w-full rounded-2xl" />
        <Skeleton className="h-20 w-full rounded-xl" />
        <Skeleton className="h-96 w-full rounded-xl" />
      </div>
    );
  }

  if (!facility || !facilityId) {
    return <p className="text-sm text-muted-foreground">Complete your facility setup before adding members.</p>;
  }

  const selectedPlan = plans.find((p) => p.id === draft.planId);

  // The hero's tagline: Review & Confirm has its own, Payment has one per tab, everything else
  // shares the wizard's default.
  const heroTagline =
    step === 4 ? "One More Step!" : step === 5 ? PAYMENT_TAB_COPY[draft.paymentTab].tagline : "More Players. A Stronger Community.";
  const heroSub =
    step === 4
      ? "Review the details and confirm to add a new member."
      : step === 5
        ? PAYMENT_TAB_COPY[draft.paymentTab].sub
        : "Give your members a dedicated time to play and be part of something bigger.";

  return (
    <div className="space-y-5">
      {/* This exact structure — single element, two background layers (image + gradient), a
          separate feather div for the join — is copied verbatim from the Membership Dashboard
          hero (membership-dashboard-hero.tsx), which is already live and confirmed correct.
          Every previous version of this panel was a new, unproven guess; this one isn't. */}
      <div className="flex flex-col overflow-hidden rounded-2xl bg-card lg:h-[120px] lg:flex-row lg:items-stretch">
        <div className="flex min-w-0 flex-col justify-center gap-0.5 px-6 py-3 lg:w-[34%]">
          <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
            <Link href="/memberships/v1" className="hover:text-foreground">
              Membership
            </Link>
            <ChevronRight className="h-3.5 w-3.5" aria-hidden />
            <span className="font-medium text-foreground">Add New Member</span>
          </nav>
          <h1 className="mt-1 truncate text-2xl font-bold text-black dark:text-foreground">Add New Member</h1>
          <p className="text-sm text-muted-foreground">Create a new member, assign a plan and set their playing schedule.</p>
        </div>

        {/* Hidden on mobile/tablet — decorative only; desktop (lg+) is unaffected. */}
        <div
          className="relative hidden flex-1 items-center gap-4 px-6 lg:flex"
          style={{
            backgroundImage: `url(/assets/${step === 4 || (step === 5 && draft.paymentTab === "link") ? "Membership_Review" : "Membership_Dashboard"}.png), linear-gradient(to right, hsl(var(--card)) 0%, ${PANEL_TINT} 22%, ${PANEL_TINT} 100%)`,
            backgroundSize: "74%, 100% 100%",
            backgroundPosition: "right 12px center, left center",
            backgroundRepeat: "no-repeat, no-repeat",
          }}
        >
          {/* Feathers the artwork's left edge into the tint. Transparent at the very left so it
              never repaints the join with the title block. */}
          <div
            aria-hidden
            className="pointer-events-none absolute inset-y-0 left-0 w-[62%]"
            style={{
              backgroundImage: `linear-gradient(to right, transparent 0%, ${PANEL_TINT} 14%, ${PANEL_TINT} 40%, transparent 100%)`,
            }}
          />

          {/* A percentage margin (not ml-auto, which would push all the way to the padding
              edge — right onto the shuttlecock, since that's roughly where the artwork's
              visible content starts too) shifts this proportionally, regardless of the
              container's actual pixel width, landing it in the gap rather than on the artwork. */}
          <div className="relative z-10 min-w-0 max-w-[46%]" style={{ marginLeft: "20%" }}>
            <p className="text-[15px] font-bold leading-snug text-black">{heroTagline}</p>
            <p className="mt-1 text-xs text-black/70">{heroSub}</p>
          </div>
        </div>
      </div>

      <Card className={cn("rounded-xl p-4", GLASS)}>
        <WizardStepper
          current={step}
          furthest={furthest}
          onSelect={(s) => {
            setTouchedFields(new Set());
            setStep(s);
          }}
        />
      </Card>

      <Card className={cn("space-y-5 rounded-xl p-5", GLASS)}>
        <div>
          <h2 className="text-base font-bold text-black dark:text-foreground">{WIZARD_STEPS[step - 1]!.title}</h2>
          <p className="text-xs text-muted-foreground">{WIZARD_STEPS[step - 1]!.hint}</p>
        </div>

        {step === 1 && (
          <div className="space-y-5">
            <div className="grid grid-cols-1 gap-5 sm:grid-cols-[1fr_180px]">
              <div className="grid grid-cols-1 gap-4">
                <Field label="Full Name" required error={show("fullName")}>
                  <Input
                    value={draft.fullName}
                    onChange={(e) => set("fullName", e.target.value)}
                    {...focusProps("fullName")}
                    placeholder="Member's name"
                    className={invalid("fullName")}
                  />
                </Field>
                <Field label="Phone Number" required error={show("phone")}>
                  <div className="flex gap-2">
                    <SelectField
                      wrapperClassName="w-[84px] shrink-0"
                      ariaLabel="Country code"
                      value={draft.countryCode}
                      onValueChange={(v) => set("countryCode", v)}
                      options={COUNTRY_CODES}
                      className="h-10 w-full rounded-lg border border-input bg-card px-2.5 text-sm outline-none transition-colors hover:border-foreground/30"
                    />
                    <Input
                      value={draft.phone}
                      onChange={(e) => set("phone", capDigits(e.target.value, draft.countryCode === "+91" ? 10 : 14))}
                      {...focusProps("phone")}
                      placeholder="98765 43210"
                      inputMode="tel"
                      className={cn("flex-1", invalid("phone"))}
                    />
                  </div>
                </Field>
              </div>

              <PhotoUpload preview={photoPreview} onChange={setPhotoPreview} />
            </div>

            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <Field label="Email" error={show("email")}>
                <Input
                  value={draft.email}
                  onChange={(e) => set("email", e.target.value)}
                  {...focusProps("email")}
                  placeholder="name@example.com"
                  type="email"
                  className={invalid("email")}
                />
              </Field>
              <Field label="Date of Birth" error={show("dateOfBirth")}>
                <DatePicker
                  value={draft.dateOfBirth}
                  onChange={(iso) => {
                    set("dateOfBirth", iso);
                    touch("dateOfBirth");
                  }}
                  max={todayIso()}
                  placeholder="Select date"
                  triggerClassName={cn(
                    "flex h-10 w-full items-center justify-between gap-2 rounded-lg border border-input bg-card px-3 text-left text-sm outline-none transition-colors hover:border-foreground/30",
                    !draft.dateOfBirth && "text-muted-foreground/60",
                    invalid("dateOfBirth"),
                  )}
                />
              </Field>
              <Field label="Gender">
                <SelectField
                  ariaLabel="Gender"
                  value={draft.gender}
                  onValueChange={(v) => set("gender", v)}
                  options={GENDERS}
                  className="h-10 w-full rounded-lg border border-input bg-card px-3 text-sm outline-none transition-colors hover:border-foreground/30"
                />
              </Field>
              <Field label="Address">
                <Input value={draft.address} onChange={(e) => set("address", e.target.value)} placeholder="Optional" />
              </Field>
              <Field label="City" error={show("city")}>
                <Input
                  value={draft.city}
                  onChange={(e) => set("city", e.target.value)}
                  {...focusProps("city")}
                  placeholder="Optional"
                  className={invalid("city")}
                />
              </Field>
              <Field label="Pincode" error={show("pincode")}>
                <Input
                  value={draft.pincode}
                  onChange={(e) => set("pincode", capDigits(e.target.value, 6))}
                  {...focusProps("pincode")}
                  placeholder="600040"
                  inputMode="numeric"
                  maxLength={6}
                  className={invalid("pincode")}
                />
              </Field>
            </div>

            <div className="space-y-4 border-t border-border pt-4">
              <p className="text-sm font-semibold text-foreground">
                Emergency Contact <span className="font-normal text-muted-foreground">(Optional)</span>
              </p>
              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <Field label="Name" error={show("emergencyName")}>
                  <Input
                    value={draft.emergencyName}
                    onChange={(e) => set("emergencyName", e.target.value)}
                    {...focusProps("emergencyName")}
                    placeholder="Contact's name"
                    className={invalid("emergencyName")}
                  />
                </Field>
                <Field label="Phone Number" error={show("emergencyPhone")}>
                  <div className="flex gap-2">
                    <SelectField
                      wrapperClassName="w-[84px] shrink-0"
                      ariaLabel="Emergency contact country code"
                      value={draft.emergencyCountryCode}
                      onValueChange={(v) => set("emergencyCountryCode", v)}
                      options={COUNTRY_CODES}
                      className="h-10 w-full rounded-lg border border-input bg-card px-2.5 text-sm outline-none transition-colors hover:border-foreground/30"
                    />
                    <Input
                      value={draft.emergencyPhone}
                      onChange={(e) =>
                        set("emergencyPhone", capDigits(e.target.value, draft.emergencyCountryCode === "+91" ? 10 : 14))
                      }
                      {...focusProps("emergencyPhone")}
                      placeholder="98765 12345"
                      inputMode="tel"
                      className={cn("flex-1", invalid("emergencyPhone"))}
                    />
                  </div>
                </Field>
              </div>
            </div>

            {/* A plain row, not a <label> wrapping the text — toggling only happens on the
                checkbox itself, per the click-target rule applied across this page. */}
            <div className="flex items-start gap-2.5 border-t border-border pt-4">
              <input
                type="checkbox"
                aria-label="Send welcome message to member"
                checked={draft.sendWelcome}
                onChange={(e) => set("sendWelcome", e.target.checked)}
                className="mt-0.5 h-4 w-4 shrink-0 cursor-pointer rounded border-input accent-[#0B7A55]"
              />
              <div>
                <p className="text-sm font-medium text-foreground">Send welcome message to member</p>
                <p className="text-xs text-muted-foreground">Member will receive an SMS/Email with membership details.</p>
              </div>
            </div>
          </div>
        )}

        {step === 2 && (
          <div className="space-y-5">
            {plans.length === 0 ? (
              <p className="py-8 text-center text-sm text-muted-foreground">
                No active plans yet.{" "}
                <Link href="/memberships/v1/plans" className="font-medium text-primary hover:underline">
                  Create one first
                </Link>
                .
              </p>
            ) : (
              // Stacked in the design; laid out side by side once there's room (desktop), and
              // back to one column as the viewport narrows — sm:2, xl:4 matches how many plans
              // a club typically offers (Monthly / 3 Months / 6 Months / 1 Year).
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
                {plans.map((p, i) => (
                  <SelectablePlanCard
                    key={p.id}
                    plan={p}
                    index={i}
                    badge={planBadgeMap.get(p.id)}
                    chosen={p.id === draft.planId}
                    onChoose={() => choosePlan(p)}
                  />
                ))}
              </div>
            )}

            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <Field label="Plan Start Date" required error={show("startDate")}>
                <DatePicker
                  value={draft.startDate}
                  onChange={(iso) => {
                    set("startDate", iso);
                    touch("startDate");
                  }}
                  placeholder="Select date"
                  triggerClassName={cn(
                    "flex h-10 w-full items-center justify-between gap-2 rounded-lg border border-input bg-card px-3 text-left text-sm outline-none transition-colors hover:border-foreground/30",
                    !draft.startDate && "text-muted-foreground/60",
                    invalid("startDate"),
                  )}
                />
              </Field>
              <Field label="Plan End Date">
                {/* Worked out from the plan's own length — not editable here; changing the
                    schedule is a separate action once the membership exists. */}
                <div className="flex h-10 w-full items-center gap-2 rounded-lg border border-input bg-muted/40 px-3 text-sm text-muted-foreground">
                  <CalendarDays className="h-4 w-4 shrink-0" aria-hidden />
                  {planEndDate ? format(planEndDate, "dd MMM yyyy") : "—"}
                </div>
              </Field>
            </div>

            <div className="flex items-start gap-2.5 rounded-lg bg-blue-500/10 p-3">
              <Info className="mt-0.5 h-4 w-4 shrink-0 text-blue-600 dark:text-blue-400" aria-hidden />
              <p className="text-xs leading-relaxed text-foreground/80">
                The membership will be active from the selected start date. You can manage or change the schedule later.
              </p>
            </div>

            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <Field label="Registration Fee (₹)" error={show("registrationFeeInr")}>
                <Input
                  value={draft.registrationFeeInr || ""}
                  onChange={(e) => set("registrationFeeInr", capDigits(e.target.value, 7) ? Number(capDigits(e.target.value, 7)) : 0)}
                  {...focusProps("registrationFeeInr")}
                  inputMode="numeric"
                  placeholder="0"
                  className={invalid("registrationFeeInr")}
                />
              </Field>
              <Field label="GST (%)" error={show("gstPercent")}>
                <Input
                  value={draft.gstPercent || ""}
                  onChange={(e) => set("gstPercent", clampNumber(capDigits(e.target.value, 2), 0, 28))}
                  {...focusProps("gstPercent")}
                  inputMode="numeric"
                  placeholder="0"
                  max={28}
                  className={invalid("gstPercent")}
                />
              </Field>
            </div>
          </div>
        )}

        {step === 3 && (
          <PlayingSchedulePicker
            facilityId={facilityId}
            value={draft.schedule}
            onChange={(s) => {
              set("schedule", s);
              touch("slot");
            }}
          />
        )}

        {step === 4 && (
          <MembershipReviewStep
            facilityId={facilityId}
            draft={draft}
            photoPreview={photoPreview}
            plans={plans}
            selectedPlan={selectedPlan}
            planEndDate={planEndDate}
            scheduleRanges={scheduleRanges}
            charges={charges}
            onEditStep={(s) => {
              setTouchedFields(new Set());
              setStep(s);
            }}
          />
        )}

        {step === 5 && (
          <div className="grid grid-cols-1 gap-5 xl:grid-cols-[1fr_300px]">
            <PaymentStep
              draft={draft}
              set={set}
              totalPayable={charges.total}
              show={show}
              invalid={invalid}
              focusProps={focusProps}
              linkResult={linkResult}
              onGenerateLink={generateLink}
              generatingLink={generatingLink}
              linkError={linkError}
              isRecurringPlan={selectedPlan?.planType === "RECURRING"}
            />
            <MemberContextPanel
              facilityId={facilityId}
              draft={draft}
              photoPreview={photoPreview}
              plans={plans}
              selectedPlan={selectedPlan}
              scheduleRanges={scheduleRanges}
              onEditStep={(s) => {
                setTouchedFields(new Set());
                setStep(s);
              }}
              locked={Boolean(linkResult)}
            />
          </div>
        )}

        {/* Steps 1, 2 and 5 show their errors under each field; this is only for step 3 (the
            slot picker has no field of its own to attach an error to). */}
        {show("slot") && <p className="text-sm text-destructive">{show("slot")}</p>}
        {error && <p className="text-sm text-destructive">{error}</p>}

        <div className="flex items-center justify-between gap-3 border-t border-border pt-4">
          <button
            type="button"
            onClick={() => (step === 1 ? router.push("/memberships/v1") : setStep((s) => (s - 1) as WizardStep))}
            className="flex h-10 items-center gap-2 rounded-lg border border-input bg-card px-4 text-sm font-medium transition-colors hover:bg-accent"
          >
            <ArrowLeft className="h-4 w-4" aria-hidden />
            {step === 1 ? "Cancel" : "Back"}
          </button>

          {step < 5 ? (
            <button
              type="button"
              onClick={next}
              className="flex h-10 items-center gap-2 rounded-lg bg-[#0B7A55] px-5 text-sm font-semibold text-white transition-opacity hover:opacity-90 dark:bg-primary dark:text-primary-foreground"
            >
              Next
              <ArrowRight className="h-4 w-4" aria-hidden />
            </button>
          ) : draft.paymentTab === "link" ? (
            // The "Generate Payment Link" button lives inside PaymentStep itself — that click
            // is what creates the member. This footer only offers a way out once it's done;
            // there's nothing to submit here beforehand.
            linkResult && (
              <button
                type="button"
                onClick={() => router.push("/memberships/v1")}
                className="flex h-10 items-center gap-2 rounded-lg bg-[#0B7A55] px-5 text-sm font-semibold text-white transition-opacity hover:opacity-90 dark:bg-primary dark:text-primary-foreground"
              >
                <Check className="h-4 w-4" aria-hidden />
                Done
              </button>
            )
          ) : (
            <button
              type="button"
              disabled={saving}
              onClick={submit}
              className="flex h-10 items-center gap-2 rounded-lg bg-[#0B7A55] px-5 text-sm font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-60 dark:bg-primary dark:text-primary-foreground"
            >
              <Check className="h-4 w-4" aria-hidden />
              {saving ? "Saving…" : linkResult ? "Mark as Paid & Cancel Link" : "Create Member"}
            </button>
          )}
        </div>
      </Card>
    </div>
  );
}
