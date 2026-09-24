"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  AlertCircle,
  ArrowLeft,
  ArrowRight,
  Calendar,
  CalendarClock,
  CalendarDays,
  Check,
  ChevronRight,
  Clock,
  CreditCard,
  Crown,
  Eye,
  FileSearch,
  IndianRupee,
  Infinity as InfinityIcon,
  Info,
  Pencil,
  ShieldCheck,
  Ticket,
  Trophy,
} from "lucide-react";
import { Card } from "@/components/ui/card";
import { SelectField } from "@/components/shared/select-field";
import { ToggleSwitch } from "@/features/bookings/components/toggle-switch";
import { PlanWizardStepper } from "@/features/memberships/components/plan-wizard-stepper";
import { CourtAccessStep } from "@/features/memberships/components/court-access-step";
import { formatClock12 } from "@/features/memberships/components/member-schedule-grid";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { useActiveFacilitySportId } from "@/features/facility/hooks/use-active-facility-sport";
import {
  billingIntervalLabel,
  durationLabel,
} from "@/features/memberships/plan-insights";
import { useFacilitySportNames, usePlayingAreasList } from "@/features/memberships/hooks/use-member-schedule";
import { courtsForSport } from "@/features/memberships/sport-scope";
import { useCourtSchedules } from "@/features/bookings/hooks/use-booking-calendar-data";
import { getMembershipService } from "@/services/memberships";
import { getMembershipSessionService } from "@/services/membership-sessions";
import { ServiceError } from "@/services/shared/service-error";
import {
  composeFeatures,
  DURATION_PRESETS,
  fieldErrors,
  furthestReachableStep,
  isStepComplete,
  PLAN_CATEGORIES,
  PLAN_WIZARD_STEPS,
  validateStep,
  type PlanWizardDraft,
  type PlanWizardStep,
} from "@/features/memberships/create-plan-wizard";
import { cn } from "@/lib/utils";

const PANEL_TINT = "#EAF9F1";

function Field({
  label,
  required,
  error,
  hint,
  children,
}: {
  label: string;
  required?: boolean;
  error?: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <p className="mb-1.5 text-sm font-semibold text-foreground/80">
        {label}
        {required && <span className="text-destructive"> *</span>}
      </p>
      {children}
      {hint && !error && (
        <p className="mt-1 text-xs text-muted-foreground">{hint}</p>
      )}
      {error && <p className="mt-1 text-xs text-destructive">{error}</p>}
    </div>
  );
}

// The [&::-webkit-...] rules hide the native up/down spinner on a number input (Chrome/Safari);
// [appearance:textfield] does the same for Firefox. Harmless on a text input, so it's just part
// of the one shared class every field in this wizard already uses.
const inputClass =
  "h-10 w-full rounded-lg border border-input bg-card px-3 text-sm outline-none transition-colors hover:border-foreground/30 focus-visible:border-foreground/40 [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-inner-spin-button]:m-0 [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-outer-spin-button]:m-0";

/** The Plan Preview's own checklist — each item ticks once its step is behind you (or, for
 *  step 2 itself, once its own required fields are filled in). */
const WHATS_NEXT: { atStep: PlanWizardStep; label: string }[] = [
  { atStep: 2, label: "Configure pricing and billing interval" },
  { atStep: 3, label: "Set court access and time slots" },
  { atStep: 4, label: "Review and publish" },
];

const DAY_ABBR = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function inr(v: number): string {
  return `₹${v.toLocaleString("en-IN")}`;
}

function durationDaysToMonths(days: number): number {
  return Math.max(1, Math.round(days / 30));
}

/**
 * The 5-option preset grid (1/3/6/12 months + Custom) shared by Plan Configuration's Duration
 * field (TIME_BASED) and Billing Interval field (RECURRING) — both are the same `durationDays`
 * value under a different label, so they get the exact same picker rather than two builds of it.
 */
function DurationPresetPicker({
  value,
  onChange,
  onBlur,
  hasError,
  customOpen,
  setCustomOpen,
  customText,
  setCustomText,
}: {
  value: number;
  onChange: (days: number) => void;
  onBlur: () => void;
  hasError: boolean;
  customOpen: boolean;
  setCustomOpen: (open: boolean) => void;
  customText: string;
  setCustomText: (text: string) => void;
}) {
  const preset = DURATION_PRESETS.find((p) => p.days === value)?.label ?? "Custom";
  return (
    <div className="grid grid-cols-2 gap-2 sm:grid-cols-5">
      {DURATION_PRESETS.map((p) =>
        p.label === "Custom" ? (
          customOpen || preset === "Custom" ? (
            <div
              key="custom"
              className={cn(
                "flex h-10 items-center gap-1.5 rounded-lg border bg-card pl-2 pr-3 transition-colors focus-within:border-foreground/40",
                hasError ? "border-destructive" : "border-input",
              )}
            >
              <input
                type="number"
                onWheel={(e) => e.currentTarget.blur()}
                min={1}
                autoFocus={customOpen}
                value={customText}
                onChange={(e) => {
                  const raw = e.target.value;
                  setCustomText(raw);
                  const months = Math.round(Number(raw));
                  // Blank/zero/negative/non-numeric all mean "no valid value yet" — write 0
                  // rather than clamping to 1, so validation blocks Next.
                  onChange(raw.trim() !== "" && Number.isFinite(months) && months >= 1 ? months * 30 : 0);
                }}
                onBlur={onBlur}
                placeholder="Months"
                className="w-0 min-w-0 flex-1 bg-transparent text-sm font-medium text-foreground outline-none [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-inner-spin-button]:m-0 [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-outer-spin-button]:m-0"
              />
              <span className="shrink-0 text-xs text-muted-foreground">month{customText === "1" ? "" : "s"}</span>
            </div>
          ) : (
            <button
              key="custom"
              type="button"
              onClick={() => {
                setCustomOpen(true);
                // If the current value happens to exactly match a preset (e.g. arriving here
                // from "1 Month"), that preset button would still read as selected too — nudge
                // off it so only Custom is active.
                const days = DURATION_PRESETS.some((pp) => pp.days === value) ? value + 1 : value;
                onChange(days);
                setCustomText(String(durationDaysToMonths(days)));
              }}
              className="h-10 rounded-lg border border-input text-sm font-medium transition-colors hover:bg-accent/50"
            >
              Custom
            </button>
          )
        ) : (
          <button
            key={p.label}
            type="button"
            onClick={() => {
              setCustomOpen(false);
              onChange(p.days!);
            }}
            className={cn(
              "h-10 rounded-lg border text-sm font-medium transition-colors",
              value === p.days ? "border-success bg-success/10 text-success" : "border-input hover:bg-accent/50",
            )}
          >
            {p.label}
          </button>
        ),
      )}
    </div>
  );
}

/** One icon + label row in the Plan Preview — Recurring/Time Based, payment, court access,
 *  playing days, time slots all share this same shape. */
function PreviewRow({
  icon: Icon,
  label,
}: {
  icon: React.ComponentType<{ className?: string }>;
  label: string;
}) {
  return (
    <div className="flex items-center gap-2.5 text-sm text-foreground/85">
      <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-md bg-success text-white">
        <Icon className="h-3.5 w-3.5" aria-hidden />
      </span>
      {label}
    </div>
  );
}

/** A read-only Review & Create card — a numbered section with its own Edit button that jumps
 *  straight back to the step that owns this data, so the owner never has to hunt for it. */
function ReviewSection({ n, title, onEdit, children }: { n: number; title: string; onEdit: () => void; children: React.ReactNode }) {
  const headingId = `review-section-${n}`;
  return (
    <section aria-labelledby={headingId} className="rounded-xl border border-border bg-card p-4">
      <div className="mb-3 flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-blue-500/15 text-xs font-bold text-blue-600 dark:text-blue-400">
            {n}
          </span>
          <h3 id={headingId} className="text-sm font-bold text-black dark:text-foreground">
            {title}
          </h3>
        </div>
        <button
          type="button"
          onClick={onEdit}
          aria-label={`Edit ${title}`}
          className="flex h-8 items-center gap-1.5 rounded-lg border border-input px-2.5 text-xs font-semibold text-foreground transition-colors hover:bg-accent"
        >
          <Pencil className="h-3.5 w-3.5" aria-hidden />
          Edit
        </button>
      </div>
      {children}
    </section>
  );
}

/** A plain key:value line, for the "Plan Type : Recurring" style rows next to Plan Details'
 *  name/badge cluster. */
function ReviewKeyRow({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex gap-2 text-sm">
      <span className="w-[88px] shrink-0 text-muted-foreground">{label}</span>
      <span className="min-w-0 flex-1 font-medium text-foreground">{value}</span>
    </div>
  );
}

/** A justified label/value row, for simpler review lists (Final Summary). */
function ReviewRow({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex justify-between gap-4 border-b border-border pb-2 last:border-0 last:pb-0">
      <span className="text-muted-foreground">{label}</span>
      <span className="max-w-[60%] text-right font-medium text-foreground">{value}</span>
    </div>
  );
}

/** One icon-badge + label chip in the Plan Configuration grid. */
function ReviewChip({ icon: Icon, iconClass, label }: { icon: React.ComponentType<{ className?: string }>; iconClass: string; label: React.ReactNode }) {
  return (
    <div className="flex items-center gap-2.5 rounded-lg bg-muted/40 px-3 py-2.5 text-sm">
      <span className={cn("flex h-7 w-7 shrink-0 items-center justify-center rounded-full", iconClass)}>
        <Icon className="h-3.5 w-3.5" aria-hidden />
      </span>
      <span className="min-w-0 truncate font-medium text-foreground">{label}</span>
    </div>
  );
}

/**
 * Create Membership Plan — a five-step wizard matching the Add Member wizard's own conventions
 * (vertical stepper here instead of horizontal, same hero, same Card-per-step shape). The Plan
 * Preview is purpose-built for this wizard (not the shared `PlanCard`, whose icon/tagline/CTA
 * layout doesn't match this design) — it reads straight off `draft`, so it can never drift from
 * what Review & Create is about to save.
 */
export function CreatePlanWizardPage() {
  const router = useRouter();
  const { data: facility } = useFacility();
  const facilityId = facility?.id ?? null;

  const [step, setStep] = useState<PlanWizardStep>(1);
  const [draft, setDraft] = useState<PlanWizardDraft>({
    name: "",
    description: "",
    planType: "TIME_BASED",
    category: PLAN_CATEGORIES[0]!,
    priceInr: 0,
    durationDays: 30,
    joiningFeeInr: 0,
    securityDepositInr: 0,
    showBadge: true,
    badgeText: "Popular",
    courtIds: [],
    // Mon-Fri, matching the same default the Add Member wizard's own Playing Schedule step seeds.
    playingDays: [1, 2, 3, 4, 5],
    timeWindows: [],
    allowAdvanceBooking: true,
    limitConsecutiveSlots: false,
    features: [],
    isActive: true,
  });
  // "Custom" has no days value of its own (durationPreset below only derives "Custom" from a
  // durationDays that doesn't match a fixed preset) — so clicking it while a preset is already
  // selected did nothing at all. This tracks the click explicitly, so it also opens the custom
  // input immediately, before any value has been typed.
  const [customDurationOpen, setCustomDurationOpen] = useState(false);
  // The Custom-duration input's own typed text — kept separate from `draft.durationDays` so the
  // field can sit empty while the owner is mid-edit (deleting down to nothing) instead of
  // snapping back to "1". An empty/invalid value writes durationDays to 0, which fieldErrors
  // already flags as invalid, so "Next" stays blocked until a real month count is entered.
  const [customMonthsInput, setCustomMonthsInput] = useState("");
  const [touchedFields, setTouchedFields] = useState<Set<string>>(new Set());
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const activeSportId = useActiveFacilitySportId(facilityId);
  const areasQuery = usePlayingAreasList(facilityId);
  // Scoped to the top bar's active sport — a plan is always created for one sport at a time;
  // switching sport up there is how an owner builds a plan for their other sport.
  const courts = courtsForSport((areasQuery.data ?? []).filter((a) => a.status === "ACTIVE"), activeSportId);
  const courtSchedulesQuery = useCourtSchedules(facilityId, courts);
  const sportNamesQuery = useFacilitySportNames(facilityId);

  const set = <K extends keyof PlanWizardDraft>(
    key: K,
    value: PlanWizardDraft[K],
  ) => setDraft((d) => ({ ...d, [key]: value }));

  const errors = fieldErrors(step, draft);
  const stepError = validateStep(step, draft);
  const furthest = furthestReachableStep(draft);
  const show = (field: string) =>
    touchedFields.has(field) ? errors[field] : undefined;

  function next() {
    if (stepError) {
      setTouchedFields(new Set(Object.keys(errors)));
      return;
    }
    setStep((s) => Math.min(4, s + 1) as PlanWizardStep);
  }

  function back() {
    if (step === 1) {
      router.push("/memberships/v1/plans");
      return;
    }
    setStep((s) => Math.max(1, s - 1) as PlanWizardStep);
  }

  async function submit() {
    // `saving` already disables the button, but a fast double-click can land both events before
    // the first re-render — this closes that gap so a second call never fires createPlan twice.
    if (saving || !facilityId || stepError) {
      setTouchedFields(new Set(Object.keys(errors)));
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const plan = await getMembershipService().createPlan({
        facilityId,
        name: draft.name.trim(),
        description: draft.description.trim() || undefined,
        category: draft.category || undefined,
        planType: draft.planType,
        priceInr: draft.priceInr,
        durationDays: draft.durationDays,
        joiningFeeInr: draft.joiningFeeInr || undefined,
        securityDepositInr: draft.securityDepositInr || undefined,
        badgeText: draft.showBadge ? draft.badgeText.trim() || "Popular" : null,
        features: composeFeatures(draft),
      });

      // Court Access's time windows become real recurring slots now that the plan they belong to
      // actually exists — the same createBatch the Add Member wizard's own Playing Schedule step
      // already writes to, so a member who joins this plan is offered these exact slots.
      for (const w of draft.timeWindows) {
        const court = courts.find((c) => c.id === w.courtId);
        if (!court) continue;
        await getMembershipSessionService().createBatch({
          facilityId,
          planId: plan.id,
          facilitySportId: court.facilitySportId,
          courtId: w.courtId,
          name: `${plan.name} — ${w.startTime}`,
          daysOfWeek: w.daysOfWeek,
          startTime: w.startTime,
          endTime: w.endTime,
          capacity: w.capacity,
        });
      }

      router.push("/memberships/v1/plans");
    } catch (err) {
      setError(
        err instanceof ServiceError
          ? err.message
          : "Unable to create this plan.",
      );
      setSaving(false);
    }
  }

  return (
    <div className="space-y-4">
      {/* Same proven hero structure used by the Add Member and Member Schedule pages. */}
      <div className="flex flex-col overflow-hidden rounded-2xl bg-card lg:h-[120px] lg:flex-row lg:items-stretch">
        <div className="flex min-w-0 flex-col justify-center gap-0.5 px-6 py-3 lg:w-[34%]">
          <nav
            aria-label="Breadcrumb"
            className="flex items-center gap-1 text-xs text-muted-foreground"
          >
            <Link href="/memberships/v1" className="hover:text-foreground">
              Membership
            </Link>
            <ChevronRight className="h-3.5 w-3.5" aria-hidden />
            <Link
              href="/memberships/v1/plans"
              className="hover:text-foreground"
            >
              Membership Plans
            </Link>
            <ChevronRight className="h-3.5 w-3.5" aria-hidden />
            <span className="font-medium text-foreground">Create New Plan</span>
          </nav>
          <h1 className="mt-1 truncate text-2xl font-bold text-black dark:text-foreground">
            Create New Membership Plan
          </h1>
          <p className="line-clamp-2 text-sm text-muted-foreground">
            Set up a new membership plan with pricing, duration, benefits and
            court access.
          </p>
        </div>

        {/* Hidden on mobile/tablet — the decorative artwork + tagline don't earn their space
         *  below the title on a phone screen; desktop (lg+, where this sits beside the title
         *  instead of under it) is unaffected. */}
        <div
          className="relative hidden flex-1 items-center gap-4 px-6 lg:flex"
          style={{
            backgroundImage: `url(/assets/Membership_Dashboard.png), linear-gradient(to right, hsl(var(--card)) 0%, ${PANEL_TINT} 22%, ${PANEL_TINT} 100%)`,
            backgroundSize: "74%, 100% 100%",
            backgroundPosition: "right 12px center, left center",
            backgroundRepeat: "no-repeat, no-repeat",
          }}
        >
          <div
            aria-hidden
            className="pointer-events-none absolute inset-y-0 left-0 w-[62%]"
            style={{
              backgroundImage: `linear-gradient(to right, transparent 0%, ${PANEL_TINT} 14%, ${PANEL_TINT} 40%, transparent 100%)`,
            }}
          />
          <div
            className="relative z-10 min-w-0 max-w-[46%]"
            style={{ marginLeft: "20%" }}
          >
            <p className="text-[15px] font-bold leading-snug text-black">
              More Members. More Play. A Stronger Community.
            </p>
            <p className="mt-1 text-xs text-black/70">
              Flexible membership plans for every player.
            </p>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[220px_1fr_320px]">
        <Card className="h-fit rounded-xl p-3">
          <PlanWizardStepper
            current={step}
            furthest={furthest}
            isDone={(s) => isStepComplete(s, draft, step)}
            onSelect={(s) => {
              setTouchedFields(new Set());
              setStep(s);
            }}
          />
        </Card>

        <Card className="space-y-5 rounded-xl p-5">
          {step === 1 && (
            <>
              <div>
                <p className="text-lg font-bold text-black dark:text-foreground">
                  Plan Details
                </p>
                <p className="text-sm text-muted-foreground">
                  Enter the basic information for this membership plan.
                </p>
              </div>

              <Field
                label="Plan Name"
                required
                error={show("name")}
                hint="e.g. Monthly Membership, 3 Months Plan, Weekend Plan, etc."
              >
                <input
                  value={draft.name}
                  onChange={(e) => set("name", e.target.value)}
                  onBlur={() => setTouchedFields((s) => new Set(s).add("name"))}
                  className={cn(
                    inputClass,
                    show("name") && "border-destructive",
                  )}
                  placeholder="Monthly Membership"
                />
              </Field>

              <Field label="Description" error={show("description")}>
                <textarea
                  value={draft.description}
                  onChange={(e) =>
                    set("description", e.target.value.slice(0, 220))
                  }
                  rows={3}
                  className="w-full rounded-lg border border-input bg-card px-3 py-2 text-sm outline-none transition-colors placeholder:text-muted-foreground/60 focus-visible:border-foreground/40"
                  placeholder="Perfect for regular players who want consistent court access."
                />
                <p className="mt-1 text-right text-xs text-muted-foreground">
                  {draft.description.length}/200
                </p>
              </Field>

              <Field
                label="Plan Category"
                hint="Choose a category to group this plan."
              >
                <SelectField
                  value={draft.category}
                  onValueChange={(v) => set("category", v)}
                  options={PLAN_CATEGORIES.map((c) => ({ value: c, label: c }))}
                  ariaLabel="Plan category"
                  className={inputClass}
                />
              </Field>

              <Field label="Plan Badge" hint="Shown as a small tag on this plan's card, e.g. in the plan list and Add Member wizard.">
                <div className="flex items-center justify-between gap-3 rounded-lg border border-input bg-card px-3 py-2.5">
                  <span className="text-sm text-foreground/80">Show a badge on this plan</span>
                  <ToggleSwitch
                    checked={draft.showBadge}
                    onChange={(v) => set("showBadge", v)}
                    label="Show a badge on this plan"
                    onClass="bg-[#0B9B63]"
                  />
                </div>
                {draft.showBadge && (
                  <input
                    value={draft.badgeText}
                    onChange={(e) => set("badgeText", e.target.value.slice(0, 24))}
                    className={cn(inputClass, "mt-2")}
                    placeholder="Popular"
                  />
                )}
              </Field>
            </>
          )}

          {step === 2 && (
            <>
              <div>
                <p className="text-lg font-bold text-black dark:text-foreground">
                  Plan Configuration
                </p>
                <p className="text-sm text-muted-foreground">
                  Set the duration, pricing and billing options for this plan.
                </p>
              </div>

              <Field label="Plan Type" required>
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <button
                    type="button"
                    onClick={() => set("planType", "TIME_BASED")}
                    className={cn(
                      "flex items-start gap-3 rounded-xl border p-3 text-left transition-colors",
                      draft.planType === "TIME_BASED"
                        ? "border-success bg-success/10"
                        : "border-input hover:bg-accent/50",
                    )}
                  >
                    <span
                      className={cn(
                        "flex h-9 w-9 shrink-0 items-center justify-center rounded-lg",
                        draft.planType === "TIME_BASED"
                          ? "bg-success text-white"
                          : "border border-input text-muted-foreground",
                      )}
                    >
                      <Calendar className="h-4.5 w-4.5" aria-hidden />
                    </span>
                    <span>
                      <span className="block text-sm font-semibold text-foreground">
                        Time Based
                      </span>
                      <span className="block text-xs text-muted-foreground">
                        Fixed duration (e.g. 1 month, 3 months)
                      </span>
                    </span>
                  </button>
                  <button
                    type="button"
                    onClick={() => set("planType", "RECURRING")}
                    className={cn(
                      "flex items-start gap-3 rounded-xl border p-3 text-left transition-colors",
                      draft.planType === "RECURRING"
                        ? "border-success bg-success/10"
                        : "border-input hover:bg-accent/50",
                    )}
                  >
                    <span
                      className={cn(
                        "flex h-9 w-9 shrink-0 items-center justify-center rounded-lg",
                        draft.planType === "RECURRING"
                          ? "bg-success text-white"
                          : "border border-input text-muted-foreground",
                      )}
                    >
                      <InfinityIcon className="h-4.5 w-4.5" aria-hidden />
                    </span>
                    <span>
                      <span className="block text-sm font-semibold text-foreground">
                        Recurring
                      </span>
                      <span className="block text-xs text-muted-foreground">
                        Auto-renewal (Ongoing)
                      </span>
                    </span>
                  </button>
                </div>
              </Field>

              {draft.planType === "RECURRING" ? (
                <>
                  <Field
                    label="Billing Interval"
                    required
                    error={show("durationDays")}
                    hint="Choose how often the membership will be renewed automatically."
                  >
                    <DurationPresetPicker
                      value={draft.durationDays}
                      onChange={(days) => set("durationDays", days)}
                      onBlur={() => setTouchedFields((s) => new Set(s).add("durationDays"))}
                      hasError={Boolean(show("durationDays"))}
                      customOpen={customDurationOpen}
                      setCustomOpen={setCustomDurationOpen}
                      customText={customMonthsInput}
                      setCustomText={setCustomMonthsInput}
                    />
                  </Field>

                  <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                    <Field
                      label="Price per billing cycle (₹)"
                      required
                      error={show("priceInr")}
                    >
                      <input
                        type="number"
                        onWheel={(e) => e.currentTarget.blur()}
                        min={0}
                        value={draft.priceInr || ""}
                        onChange={(e) =>
                          set(
                            "priceInr",
                            Math.max(0, Number(e.target.value) || 0),
                          )
                        }
                        onBlur={() =>
                          setTouchedFields((s) => new Set(s).add("priceInr"))
                        }
                        className={cn(
                          inputClass,
                          show("priceInr") && "border-destructive",
                        )}
                        placeholder="2500"
                      />
                    </Field>
                    <Field label="Billing Frequency">
                      <select
                        disabled
                        className={cn(
                          inputClass,
                          "cursor-not-allowed text-muted-foreground/60",
                        )}
                      >
                        <option>Auto-renewal</option>
                      </select>
                    </Field>
                  </div>

                  <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                    <div className="flex items-start gap-3 rounded-xl border border-input p-3">
                      <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-success/15 text-success">
                        <InfinityIcon className="h-4.5 w-4.5" aria-hidden />
                      </span>
                      <span>
                        <span className="block text-sm font-semibold text-foreground">
                          Recurring Payment
                        </span>
                        <span className="block text-xs text-muted-foreground">
                          The membership will be automatically renewed at the
                          selected interval.
                        </span>
                      </span>
                    </div>
                    <div className="flex items-start gap-3 rounded-xl border border-input p-3">
                      <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-blue-500/15 text-blue-600 dark:text-blue-400">
                        <CreditCard className="h-4.5 w-4.5" aria-hidden />
                      </span>
                      <span>
                        <span className="block text-sm font-semibold text-foreground">
                          Auto-Renewal
                        </span>
                        <span className="block text-xs text-muted-foreground">
                          Payment will be charged automatically using the saved
                          payment method.
                        </span>
                      </span>
                    </div>
                  </div>
                </>
              ) : (
                <>
                  <Field label="Duration" required error={show("durationDays")}>
                    <DurationPresetPicker
                      value={draft.durationDays}
                      onChange={(days) => set("durationDays", days)}
                      onBlur={() => setTouchedFields((s) => new Set(s).add("durationDays"))}
                      hasError={Boolean(show("durationDays"))}
                      customOpen={customDurationOpen}
                      setCustomOpen={setCustomDurationOpen}
                      customText={customMonthsInput}
                      setCustomText={setCustomMonthsInput}
                    />
                  </Field>

                  <Field label="Price (₹)" required error={show("priceInr")}>
                    <input
                      type="number"
                      onWheel={(e) => e.currentTarget.blur()}
                      min={0}
                      value={draft.priceInr || ""}
                      onChange={(e) =>
                        set(
                          "priceInr",
                          Math.max(0, Number(e.target.value) || 0),
                        )
                      }
                      onBlur={() =>
                        setTouchedFields((s) => new Set(s).add("priceInr"))
                      }
                      className={cn(
                        inputClass,
                        show("priceInr") && "border-destructive",
                      )}
                      placeholder="2500"
                    />
                  </Field>

                  <div className="flex items-start gap-3 rounded-xl border border-input p-3">
                    <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-success/15 text-success">
                      <CreditCard className="h-4.5 w-4.5" aria-hidden />
                    </span>
                    <span>
                      <span className="block text-sm font-semibold text-foreground">
                        One-time Payment
                      </span>
                      <span className="block text-xs text-muted-foreground">
                        Members pay the full membership amount once. The
                        membership remains active until its expiry date.
                      </span>
                    </span>
                  </div>
                </>
              )}

              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <Field
                  label="Joining Fee (Optional)"
                  error={show("joiningFeeInr")}
                  hint="One-time fee charged during registration (e.g. ₹500)."
                >
                  <div className="flex items-center gap-2 rounded-lg border border-input bg-card px-3">
                    <span className="text-sm text-muted-foreground">₹</span>
                    <input
                      type="number"
                      onWheel={(e) => e.currentTarget.blur()}
                      min={0}
                      value={draft.joiningFeeInr || ""}
                      onChange={(e) =>
                        set(
                          "joiningFeeInr",
                          Math.max(0, Number(e.target.value) || 0),
                        )
                      }
                      onBlur={() =>
                        setTouchedFields((s) => new Set(s).add("joiningFeeInr"))
                      }
                      className="h-10 w-full bg-transparent text-sm outline-none [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-inner-spin-button]:m-0 [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-outer-spin-button]:m-0"
                      placeholder="Enter joining fee"
                    />
                  </div>
                </Field>
                <Field
                  label="Security Deposit (Optional)"
                  error={show("securityDepositInr")}
                  hint="Refundable amount (e.g. ₹1,000)."
                >
                  <div className="flex items-center gap-2 rounded-lg border border-input bg-card px-3">
                    <span className="text-sm text-muted-foreground">₹</span>
                    <input
                      type="number"
                      onWheel={(e) => e.currentTarget.blur()}
                      min={0}
                      value={draft.securityDepositInr || ""}
                      onChange={(e) =>
                        set(
                          "securityDepositInr",
                          Math.max(0, Number(e.target.value) || 0),
                        )
                      }
                      onBlur={() =>
                        setTouchedFields((s) =>
                          new Set(s).add("securityDepositInr"),
                        )
                      }
                      className="h-10 w-full bg-transparent text-sm outline-none [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-inner-spin-button]:m-0 [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-outer-spin-button]:m-0"
                      placeholder="Enter security deposit"
                    />
                  </div>
                </Field>
              </div>

              <div className="flex items-start gap-2 rounded-lg bg-blue-500/10 p-3 text-xs text-foreground/80">
                <Info
                  className="mt-0.5 h-3.5 w-3.5 shrink-0 text-blue-600 dark:text-blue-400"
                  aria-hidden
                />
                <p>
                  {draft.planType === "RECURRING" ? (
                    <>
                      This membership will automatically renew{" "}
                      <span className="font-semibold">
                        {billingIntervalLabel(draft.durationDays)}
                      </span>
                      . Members can cancel at any time from their account or by
                      contacting the club.
                    </>
                  ) : (
                    "This membership has a fixed duration and will expire automatically at the end of the selected period."
                  )}
                </p>
              </div>
            </>
          )}

          {step === 3 && (
            <CourtAccessStep
              draft={draft}
              set={set}
              show={show}
              courts={courts}
              courtSchedules={courtSchedulesQuery.data}
              loading={areasQuery.isLoading}
            />
          )}


          {step === 4 && (
            <>
              <div className="flex items-start gap-3">
                <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-blue-500/15 text-blue-600 dark:text-blue-400">
                  <FileSearch className="h-5 w-5" aria-hidden />
                </span>
                <div>
                  <p className="text-lg font-bold text-black dark:text-foreground">Review &amp; Create</p>
                  <p className="text-sm text-muted-foreground">
                    Please review all the plan details below. You can go back and make changes if needed.
                  </p>
                </div>
              </div>

              <ReviewSection n={1} title="Plan Details" onEdit={() => setStep(1)}>
                <div className="grid grid-cols-1 gap-4 rounded-lg bg-muted/40 p-3 sm:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
                  <div className="flex items-start gap-3">
                    <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-amber-500/15 text-amber-600">
                      <Crown className="h-5 w-5" aria-hidden />
                    </span>
                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-2">
                        <p className="truncate text-base font-bold text-black dark:text-foreground">{draft.name.trim() || "New Plan"}</p>
                        {draft.showBadge && (
                          <span className="shrink-0 rounded-full bg-success/15 px-2 py-0.5 text-[11px] font-semibold text-success">
                            {draft.badgeText.trim() || "Popular"}
                          </span>
                        )}
                      </div>
                      <p className="mt-0.5 text-xs text-muted-foreground">{draft.category || "Membership plan"}</p>
                    </div>
                  </div>
                  <div className="space-y-1.5 sm:border-l sm:border-border sm:pl-4">
                    <ReviewKeyRow label="Plan Type" value={draft.planType === "RECURRING" ? "Recurring" : "Time Based"} />
                    <ReviewKeyRow label="Description" value={draft.description.trim() || "—"} />
                    <ReviewKeyRow
                      label="Status"
                      value={
                        <span className="inline-flex items-center gap-1.5">
                          <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-success" aria-hidden />
                          Active (after creation)
                        </span>
                      }
                    />
                  </div>
                </div>
              </ReviewSection>

              <ReviewSection n={2} title="Plan Configuration" onEdit={() => setStep(2)}>
                <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                  <ReviewChip
                    icon={draft.planType === "RECURRING" ? InfinityIcon : Calendar}
                    iconClass="bg-success/15 text-success"
                    label={draft.planType === "RECURRING" ? "Recurring" : "Time Based"}
                  />
                  <ReviewChip
                    icon={IndianRupee}
                    iconClass="bg-blue-500/15 text-blue-600 dark:text-blue-400"
                    label={draft.joiningFeeInr > 0 ? `Joining Fee: ${inr(draft.joiningFeeInr)}` : "No Joining Fee"}
                  />
                  <ReviewChip
                    icon={CalendarClock}
                    iconClass="bg-purple-500/15 text-purple-600 dark:text-purple-400"
                    label={draft.planType === "RECURRING" ? billingIntervalLabel(draft.durationDays) : durationLabel(draft.durationDays)}
                  />
                  <ReviewChip
                    icon={ShieldCheck}
                    iconClass="bg-amber-500/15 text-amber-600"
                    label={draft.securityDepositInr > 0 ? `${inr(draft.securityDepositInr)} (Refundable)` : "No Security Deposit"}
                  />
                  <ReviewChip
                    icon={IndianRupee}
                    iconClass="bg-success/15 text-success"
                    label={
                      draft.planType === "RECURRING"
                        ? `${inr(draft.priceInr)} / ${durationDaysToMonths(draft.durationDays) === 1 ? "month" : durationLabel(draft.durationDays).toLowerCase()}`
                        : inr(draft.priceInr)
                    }
                  />
                  <ReviewChip
                    icon={CreditCard}
                    iconClass="bg-blue-500/15 text-blue-600 dark:text-blue-400"
                    label={draft.planType === "RECURRING" ? "Recurring Payment" : "One-time Payment"}
                  />
                </div>
              </ReviewSection>

              <ReviewSection n={3} title="Court Access" onEdit={() => setStep(3)}>
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
                  <div className="rounded-lg bg-muted/40 p-3">
                    <p className="mb-2 text-xs font-semibold text-muted-foreground">Sport</p>
                    <div className="flex items-center gap-2.5">
                      <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-success/15 text-success">
                        <Trophy className="h-4.5 w-4.5" aria-hidden />
                      </span>
                      <p className="min-w-0 truncate text-sm font-bold text-foreground">
                        {[
                          ...new Set(
                            draft.courtIds
                              .map((id) => courts.find((c) => c.id === id)?.facilitySportId)
                              .filter((id): id is string => Boolean(id))
                              .map((id) => sportNamesQuery.data?.get(id)),
                          ),
                        ]
                          .filter(Boolean)
                          .join(", ") || "—"}
                      </p>
                    </div>
                  </div>

                  <div className="rounded-lg bg-muted/40 p-3">
                    <p className="mb-2 text-xs font-semibold text-muted-foreground">Selected Courts</p>
                    {draft.courtIds.length > 0 ? (
                      <div className="space-y-2">
                        {draft.courtIds.map((id) => {
                          const court = courts.find((c) => c.id === id);
                          return (
                            <div key={id} className="flex items-center gap-2">
                              <span
                                aria-hidden
                                className="h-9 w-12 shrink-0 rounded-md bg-gradient-to-br from-slate-700 to-slate-900"
                              />
                              <div className="min-w-0">
                                <p className="truncate text-sm font-semibold text-foreground">{court?.name ?? id}</p>
                                <p className="text-[11px] text-muted-foreground">{court?.type === "OUTDOOR" ? "Outdoor" : "Indoor"}</p>
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    ) : (
                      <p className="text-sm text-muted-foreground">—</p>
                    )}
                  </div>

                  <div className="rounded-lg bg-muted/40 p-3">
                    <p className="mb-2 text-xs font-semibold text-muted-foreground">Playing Schedule</p>
                    <div className="space-y-1.5 text-sm">
                      <p className="flex items-center gap-1.5 font-medium text-foreground">
                        <CalendarDays className="h-3.5 w-3.5 shrink-0 text-success" aria-hidden />
                        {draft.playingDays.length > 0 ? DAY_ABBR.filter((_, i) => draft.playingDays.includes(i)).join(", ") : "—"}
                      </p>
                      {draft.timeWindows.length > 0 ? (
                        draft.timeWindows.map((w) => (
                          <p key={w.id} className="flex items-center gap-1.5 text-foreground/80">
                            <Clock className="h-3.5 w-3.5 shrink-0 text-success" aria-hidden />
                            {formatClock12(w.startTime)} – {formatClock12(w.endTime)}
                          </p>
                        ))
                      ) : (
                        <p className="text-muted-foreground">—</p>
                      )}
                    </div>
                  </div>
                </div>
              </ReviewSection>

              <div className="flex items-start gap-2.5 rounded-xl border border-input bg-muted/40 p-3">
                <Info className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
                <div className="text-xs leading-relaxed text-foreground/80">
                  <p className="text-sm font-semibold text-foreground">Membership Access</p>
                  <p className="mt-0.5">
                    Members assigned to this plan will receive access to the selected courts and recurring time windows during their
                    active membership period.{" "}
                    {draft.planType === "RECURRING"
                      ? "Access continues while the recurring membership remains active."
                      : "Access ends when the membership expires."}
                  </p>
                </div>
              </div>

              <div className="flex items-start gap-2.5 rounded-xl border border-input bg-muted/40 p-3">
                <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
                <div className="text-xs leading-relaxed text-foreground/80">
                  <p className="text-sm font-semibold text-foreground">Reserved Membership Capacity</p>
                  <p className="mt-0.5">
                    Selected court capacity will be reserved for members. Guest bookings cannot use this reserved capacity unless the
                    owner explicitly releases it through the Guest Booking workflow.
                  </p>
                </div>
              </div>

              <ReviewSection n={4} title="Final Summary" onEdit={() => setStep(1)}>
                <div className="space-y-2 rounded-lg bg-muted/40 p-3 text-sm">
                  <ReviewRow label="Membership Plan" value={draft.name.trim() || "—"} />
                  <ReviewRow
                    label="Price"
                    value={
                      draft.planType === "RECURRING"
                        ? `${inr(draft.priceInr)} / ${durationDaysToMonths(draft.durationDays) === 1 ? "month" : durationLabel(draft.durationDays).toLowerCase()}`
                        : inr(draft.priceInr)
                    }
                  />
                  <ReviewRow
                    label={draft.planType === "RECURRING" ? "Billing Interval" : "Membership Duration"}
                    value={draft.planType === "RECURRING" ? billingIntervalLabel(draft.durationDays) : durationLabel(draft.durationDays)}
                  />
                  <ReviewRow
                    label="Court Access"
                    value={draft.courtIds.map((id) => courts.find((c) => c.id === id)?.name).filter(Boolean).join(", ") || "—"}
                  />
                  <ReviewRow
                    label="Playing Schedule"
                    value={
                      draft.playingDays.length === 0 || draft.timeWindows.length === 0
                        ? "—"
                        : `${DAY_ABBR.filter((_, i) => draft.playingDays.includes(i)).join(", ")}, ${draft.timeWindows
                            .map((w) => `${formatClock12(w.startTime)} – ${formatClock12(w.endTime)}`)
                            .join("; ")}`
                    }
                  />
                  {(draft.joiningFeeInr > 0 || draft.securityDepositInr > 0) && (
                    <div className="flex justify-between gap-4">
                      <span className="text-muted-foreground">One-time Charges</span>
                      <div className="max-w-[60%] space-y-0.5 text-right font-medium text-foreground">
                        {draft.joiningFeeInr > 0 && <p>Joining Fee: {inr(draft.joiningFeeInr)}</p>}
                        {draft.securityDepositInr > 0 && <p>Security Deposit: {inr(draft.securityDepositInr)}</p>}
                      </div>
                    </div>
                  )}
                </div>
              </ReviewSection>

              {error && (
                <div className="flex items-start gap-2.5 rounded-xl border border-destructive/30 bg-destructive/5 p-3">
                  <AlertCircle className="mt-0.5 h-4 w-4 shrink-0 text-destructive" aria-hidden />
                  <div className="min-w-0 flex-1 text-sm">
                    <p className="font-semibold text-destructive">Unable to create membership plan.</p>
                    <p className="mt-0.5 text-foreground/80">{error}</p>
                    <div className="mt-2 flex gap-2">
                      <button
                        type="button"
                        onClick={submit}
                        className="flex h-8 items-center rounded-lg border border-input bg-card px-3 text-xs font-semibold text-foreground transition-colors hover:bg-accent"
                      >
                        Try Again
                      </button>
                      <button
                        type="button"
                        onClick={() => setStep(1)}
                        className="flex h-8 items-center rounded-lg border border-input bg-card px-3 text-xs font-semibold text-foreground transition-colors hover:bg-accent"
                      >
                        Go Back &amp; Edit
                      </button>
                    </div>
                  </div>
                </div>
              )}
            </>
          )}
        </Card>

        <Card className="space-y-3 rounded-xl p-3">
          <div className="flex items-center justify-between px-1">
            <p className="text-sm font-bold text-black dark:text-foreground">
              Plan Preview
            </p>
            <span className="flex items-center gap-1 rounded-full bg-success/15 px-2 py-0.5 text-[11px] font-semibold text-success">
              <Eye className="h-3 w-3" aria-hidden />
              Live Preview
            </span>
          </div>

          <div className="space-y-3 rounded-xl bg-success/5 p-4">
            <div className="flex items-start justify-between gap-2">
              <p className="text-base font-bold text-black dark:text-foreground">
                {draft.name.trim() || "New Plan"}
              </p>
              {draft.showBadge && (
                <span className="shrink-0 rounded-full bg-success/15 px-2 py-0.5 text-[11px] font-semibold text-success">
                  {draft.badgeText.trim() || "Popular"}
                </span>
              )}
            </div>

            <p className="flex items-baseline gap-1">
              <span className="text-3xl font-bold tabular-nums text-black dark:text-foreground">
                {inr(draft.priceInr)}
              </span>
              <span className="text-sm text-muted-foreground">
                {durationDaysToMonths(draft.durationDays) === 1
                  ? "/ month"
                  : `/ ${durationLabel(draft.durationDays).toLowerCase()}`}
              </span>
            </p>

            <div className="space-y-2.5">
              <PreviewRow
                icon={draft.planType === "RECURRING" ? InfinityIcon : Calendar}
                label={
                  draft.planType === "RECURRING"
                    ? "Recurring Membership"
                    : "Time Based Membership"
                }
              />
              <PreviewRow
                icon={CreditCard}
                label={
                  draft.planType === "RECURRING"
                    ? `Auto-renews ${billingIntervalLabel(draft.durationDays)}`
                    : "One-time payment"
                }
              />
              <PreviewRow
                icon={Calendar}
                label={
                  draft.planType === "RECURRING"
                    ? `Billing Interval: ${durationLabel(draft.durationDays)}`
                    : `Duration: ${durationLabel(draft.durationDays)}`
                }
              />
              {draft.courtIds.length > 0 && (
                <PreviewRow
                  icon={Ticket}
                  label={`Court Access: ${draft.courtIds
                    .map((id) => courts.find((c) => c.id === id)?.name)
                    .filter(Boolean)
                    .join(", ")}`}
                />
              )}
              {draft.playingDays.length > 0 && (
                <PreviewRow
                  icon={CalendarDays}
                  label={`Playing Days: ${DAY_ABBR.filter((_, i) => draft.playingDays.includes(i)).join(", ")}`}
                />
              )}
              {draft.timeWindows.length > 0 && (
                <div>
                  <PreviewRow icon={CalendarClock} label="Time Slots:" />
                  <div className="ml-8 mt-1.5 space-y-1">
                    {draft.timeWindows.map((w) => (
                      <p
                        key={w.id}
                        className="flex items-center gap-1.5 text-xs text-foreground/80"
                      >
                        <Clock
                          className="h-3.5 w-3.5 shrink-0 text-success"
                          aria-hidden
                        />
                        {formatClock12(w.startTime)} -{" "}
                        {formatClock12(w.endTime)}
                      </p>
                    ))}
                  </div>
                </div>
              )}
            </div>

            <div className="space-y-2 border-t border-success/15 pt-3">
              <p className="text-sm font-bold text-black dark:text-foreground">
                What&apos;s Next?
              </p>
              <ul className="space-y-2">
                {WHATS_NEXT.map(({ atStep, label }) => {
                  const done =
                    step > atStep ||
                    (step === atStep && validateStep(atStep, draft) === null);
                  return (
                    <li
                      key={atStep}
                      className="flex items-center gap-2 text-xs"
                    >
                      <span
                        className={cn(
                          "flex h-4 w-4 shrink-0 items-center justify-center rounded-full",
                          done
                            ? "bg-success text-white"
                            : "border border-input",
                        )}
                      >
                        {done && (
                          <Check
                            className="h-2.5 w-2.5"
                            strokeWidth={4}
                            aria-hidden
                          />
                        )}
                      </span>
                      <span
                        className={
                          done ? "text-foreground" : "text-muted-foreground"
                        }
                      >
                        {label}
                      </span>
                    </li>
                  );
                })}
              </ul>
            </div>
          </div>
        </Card>
      </div>

      <Card className="flex flex-wrap items-center justify-between gap-3 rounded-xl p-4">
        <button
          type="button"
          onClick={back}
          className="flex h-10 items-center gap-2 rounded-lg border border-input bg-card px-5 text-sm font-semibold text-foreground transition-colors hover:bg-accent"
        >
          <ArrowLeft className="h-4 w-4" aria-hidden />
          {step === 1 ? "Cancel" : "Back"}
        </button>

        {step < 4 ? (
          <button
            type="button"
            onClick={next}
            className="flex h-10 items-center gap-2 rounded-lg bg-[#0B7A55] px-5 text-sm font-semibold text-white transition-opacity hover:opacity-90"
          >
            {/* The full "Next: <step title>" reads fine once there's room for it; on a phone-width
             *  screen it's just "Next" so this row never forces horizontal scroll next to Back. */}
            <span className="hidden sm:inline">{`Next: ${PLAN_WIZARD_STEPS[step]!.title}`}</span>
            <span className="sm:hidden">Next</span>
            <ArrowRight className="h-4 w-4" aria-hidden />
          </button>
        ) : (
          <button
            type="button"
            disabled={saving}
            onClick={submit}
            className="flex h-10 items-center gap-2 rounded-lg bg-[#0B7A55] px-5 text-sm font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-60"
          >
            {saving ? "Creating…" : "Create Plan"}
          </button>
        )}
      </Card>
    </div>
  );
}
