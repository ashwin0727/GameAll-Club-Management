"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  ArrowLeft,
  ArrowRight,
  Bell,
  BookOpen,
  Calendar,
  CalendarClock,
  Check,
  ChevronRight,
  Clock,
  Eye,
  GraduationCap,
  ImagePlus,
  IndianRupee,
  MapPin,
  Pencil,
  Percent,
  Repeat,
  Tag,
  Trash2,
  Users as UsersIcon,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { ToggleSwitch } from "@/features/bookings/components/toggle-switch";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import { PermissionDenied } from "@/features/staff/components/permission-denied";
import { useFacilitySportOptions } from "@/features/facility/hooks/use-facility-sport-options";
import { usePlayingAreasList } from "@/features/memberships/hooks/use-member-schedule";
import { courtsForSport } from "@/features/memberships/sport-scope";
import { getCoachingService } from "@/services/coaching";
import type { CoachOption } from "@/features/coaching/types";
import { Chip, blurOnWheel, money, NO_SPINNER_INPUT, PageHeader } from "@/features/coaching/components/shared";
import { ProgramPreviewPanel } from "@/features/coaching/components/program-preview-panel";
import { TimeField } from "@/features/memberships/components/time-field";
import {
  AGE_GROUPS,
  DAY_LABELS_SHORT,
  PROGRAM_DURATIONS,
  PROGRAM_STEPS,
  SESSION_DURATIONS,
  SESSIONS_PER_WEEK,
  SKILL_LEVELS,
  programStructurePresetsForSport,
  useProgramWizardForm,
} from "@/features/coaching/components/use-program-wizard-form";
import { cn } from "@/lib/utils";

const PROGRAM_TYPES = [
  { value: "GROUP" as const, label: "Group Program", hint: "Multiple students, shared batches" },
  { value: "ONE_ON_ONE" as const, label: "One-on-One", hint: "Personal, individual coaching" },
  { value: "TRIAL" as const, label: "Trial Program", hint: "A short trial before enrolling" },
];
const PROGRAM_TYPE_LABEL: Record<string, string> = { GROUP: "Group Program", ONE_ON_ONE: "One-on-One", TRIAL: "Trial Program" };

function fmtReviewDate(iso: string): string {
  if (!iso) return "—";
  const [y, m, d] = iso.split("-");
  return `${d} ${["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][Number(m) - 1]} ${y}`;
}

/** A numbered review card with its own Edit button that jumps back to the step owning this data —
 *  same shape the Membership Create Plan wizard's own Review & Create step uses. */
function ReviewSection({ n, title, onEdit, children }: { n: number; title: string; onEdit: () => void; children: React.ReactNode }) {
  return (
    <Card className="p-4">
      <div className="mb-3 flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-primary/15 text-xs font-bold text-primary">{n}</span>
          <h3 className="text-sm font-bold">{title}</h3>
        </div>
        <button type="button" onClick={onEdit} className="flex h-8 items-center gap-1.5 rounded-lg border border-input px-2.5 text-xs font-semibold transition-colors hover:bg-accent">
          <Pencil className="h-3.5 w-3.5" aria-hidden />
          Edit
        </button>
      </div>
      {children}
    </Card>
  );
}

function ReviewRow({ icon: Icon, label, value }: { icon: typeof UsersIcon; label: string; value: string }) {
  return (
    <div className="flex items-start gap-2 text-sm">
      <Icon className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
      <span className="w-36 shrink-0 text-muted-foreground">{label}</span>
      <span className="min-w-0 flex-1 font-medium">{value}</span>
    </div>
  );
}

function Field({ label, hint, required, children }: { label: string; hint?: string; required?: boolean; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label>
        {label}
        {required && <span className="text-destructive"> *</span>}
      </Label>
      {children}
      {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
    </div>
  );
}

/**
 * Create Coaching Program — a 5-step wizard mirroring the Membership module's Create Plan wizard
 * (`create-plan-wizard-page.tsx`): stepper | fields | live preview grid, all state in
 * `useProgramWizardForm`, submitted atomically via `createProgramFull`.
 */
export function ProgramWizardPage() {
  const perms = usePermissionContext();
  const router = useRouter();
  const facilityId = perms?.facilityId ?? null;
  const form = useProgramWizardForm(facilityId);

  const sportsQuery = useFacilitySportOptions(facilityId ?? undefined);
  const areasQuery = usePlayingAreasList(facilityId);
  const courts = courtsForSport((areasQuery.data ?? []).filter((a) => a.status === "ACTIVE"), form.facilitySportId || null);
  const [coaches, setCoaches] = useState<CoachOption[]>([]);
  const [highlightInput, setHighlightInput] = useState("");
  const [batchName, setBatchName] = useState("");

  useEffect(() => {
    if (!facilityId) return;
    getCoachingService()
      .listCoachOptions(facilityId)
      .then(setCoaches)
      .catch(() => setCoaches([]));
  }, [facilityId]);

  if (!perms?.can("COACHING_MANAGE_PROGRAMS")) {
    return <PermissionDenied message="You don't have permission to manage coaching programs." />;
  }

  const sportName = sportsQuery.data?.find((s) => s.facilitySportId === form.facilitySportId)?.name;
  const structurePresets = programStructurePresetsForSport(sportName);
  const stepIndex = PROGRAM_STEPS.indexOf(form.step);
  const stepValid =
    form.step === "Basic Information"
      ? form.step1Valid
      : form.step === "Program Details"
        ? form.step2Valid
        : form.step === "Schedule & Batches"
          ? form.step3Valid
          : form.step === "Pricing & Settings"
            ? form.step4Valid
            : true;

  function addHighlight() {
    const v = highlightInput.trim();
    if (!v || form.highlights.includes(v)) return;
    form.setHighlights([...form.highlights, v]);
    setHighlightInput("");
  }

  /** A batch is a duplicate when it repeats a name already used, or repeats the exact same
   *  court + time + at least one overlapping day as an existing batch — both are the same slot
   *  being added twice, not two genuinely different batches. */
  function findDuplicateBatch(name: string, w: typeof form.weeklySchedule): string | null {
    const trimmed = name.trim().toLowerCase();
    for (const b of form.batches) {
      if (b.name.trim().toLowerCase() === trimmed) return `A batch named "${b.name}" already exists.`;
      const sameSlot = b.courtId === w.courtId && b.startTime === w.startTime && b.endTime === w.endTime;
      const overlappingDay = b.daysOfWeek.some((d) => w.daysOfWeek.includes(d));
      if (sameSlot && overlappingDay) return `"${b.name}" already uses this court, time and day.`;
    }
    return null;
  }

  const batchDuplicateError = batchName.trim() ? findDuplicateBatch(batchName, form.weeklySchedule) : null;

  function addBatchFromSchedule() {
    const w = form.weeklySchedule;
    if (!batchName.trim() || w.daysOfWeek.length === 0 || !w.courtId) return;
    if (findDuplicateBatch(batchName, w)) return;
    form.addBatch({
      name: batchName.trim(),
      daysOfWeek: w.daysOfWeek,
      startTime: w.startTime,
      endTime: w.endTime,
      capacity: Number(form.maxCapacity) || 1,
      courtId: w.courtId,
      coachId: w.coachId || null,
    });
    setBatchName("");
  }

  async function handleSubmit(status: "DRAFT" | "ACTIVE") {
    try {
      const id = await form.submit(status);
      router.push(`/coaching/programs/${id}`);
    } catch {
      // form.error already holds the message; stay on Review & Create.
    }
  }

  return (
    <div className="space-y-4">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
        <Link href="/coaching" className="hover:text-foreground">
          Coaching
        </Link>
        <ChevronRight className="h-3.5 w-3.5" aria-hidden />
        <Link href="/coaching/programs" className="hover:text-foreground">
          Coaching Programs
        </Link>
        <ChevronRight className="h-3.5 w-3.5" aria-hidden />
        <span className="font-medium text-foreground">Create Program</span>
      </nav>

      <PageHeader title="Create Coaching Program" subtitle="Set up a new coaching program with schedule, pricing and settings." />

      <ol className="flex flex-wrap gap-2 text-xs">
        {PROGRAM_STEPS.map((s, i) => (
          <li key={s}>
            <button
              type="button"
              onClick={() => i <= stepIndex && form.setStep(s)}
              disabled={i > stepIndex}
              className={cn(
                "flex items-center gap-1.5 rounded-full border px-3 py-1.5 font-medium transition-colors",
                i === stepIndex
                  ? "border-primary bg-primary/10 text-primary"
                  : i < stepIndex
                    ? "border-success/40 bg-success/10 text-success"
                    : "border-border text-muted-foreground",
              )}
            >
              {i < stepIndex ? <Check className="h-3.5 w-3.5" aria-hidden /> : <span>{i + 1}.</span>}
              {s}
            </button>
          </li>
        ))}
      </ol>

      <div className={cn("grid grid-cols-1 gap-4", form.step !== "Review & Create" && "lg:grid-cols-[1fr_340px]")}>
        <Card className="space-y-5 p-5">
          {form.step === "Basic Information" && (
            <>
              <Field label="Program Name" required>
                <Input value={form.name} onChange={(e) => form.setName(e.target.value)} placeholder="e.g. Junior Badminton Academy" />
              </Field>
              <Field label="Sport" required>
                <Select value={form.facilitySportId} onValueChange={form.setFacilitySportId}>
                  <SelectTrigger>
                    <SelectValue placeholder="Select a sport" />
                  </SelectTrigger>
                  <SelectContent>
                    {(sportsQuery.data ?? []).map((s) => (
                      <SelectItem key={s.facilitySportId} value={s.facilitySportId}>
                        {s.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </Field>
              <Field label="Description" required>
                <Textarea rows={3} value={form.description} onChange={(e) => form.setDescription(e.target.value)} maxLength={500} placeholder="Describe the program, what students will learn…" />
              </Field>
              <Field label="Program Image" hint="JPG, PNG or WEBP, up to 5MB.">
                <label className="flex h-28 cursor-pointer flex-col items-center justify-center gap-1.5 rounded-lg border border-dashed border-input text-muted-foreground transition-colors hover:border-foreground/30">
                  {form.imagePreview ? (
                    // eslint-disable-next-line @next/next/no-img-element -- a local object URL preview, not a served asset
                    <img src={form.imagePreview} alt="" className="h-full w-full rounded-lg object-cover" />
                  ) : (
                    <>
                      <ImagePlus className="h-5 w-5" aria-hidden />
                      <span className="text-xs">Click to upload an image</span>
                    </>
                  )}
                  <input type="file" accept="image/jpeg,image/png,image/webp" className="hidden" onChange={(e) => form.pickImage(e.target.files?.[0])} />
                </label>
                {form.imageError && <p className="text-xs text-destructive">{form.imageError}</p>}
              </Field>
              <Field label="Program Type" required>
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
                  {PROGRAM_TYPES.map((t) => (
                    <button
                      key={t.value}
                      type="button"
                      onClick={() => form.setProgramType(t.value)}
                      className={cn(
                        "rounded-xl border p-3 text-left transition-colors",
                        form.programType === t.value ? "border-success bg-success/10" : "border-input hover:bg-accent/50",
                      )}
                    >
                      <p className="text-sm font-semibold">{t.label}</p>
                      <p className="text-xs text-muted-foreground">{t.hint}</p>
                    </button>
                  ))}
                </div>
              </Field>
              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <Field label="Target Audience — Age Group" required>
                  <div className="flex flex-wrap gap-2">
                    {AGE_GROUPS.map((a) => (
                      <Chip key={a} label={a} selected={form.ageGroup === a} onToggle={() => form.setAgeGroup(a)} />
                    ))}
                  </div>
                </Field>
                <Field label="Target Audience — Skill Level" required>
                  <div className="flex flex-wrap gap-2">
                    {SKILL_LEVELS.map((l) => (
                      <Chip key={l} label={l} selected={form.level === l} onToggle={() => form.setLevel(l)} />
                    ))}
                  </div>
                </Field>
              </div>
              <Field label="Key Highlights" hint="Add short highlights shown on the program's card.">
                <div className="flex gap-2">
                  <Input
                    value={highlightInput}
                    onChange={(e) => setHighlightInput(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        e.preventDefault();
                        addHighlight();
                      }
                    }}
                    placeholder="e.g. Certified coaches"
                  />
                  <button type="button" onClick={addHighlight} className="shrink-0 rounded-lg border border-input px-3 text-sm font-medium hover:bg-accent">
                    Add
                  </button>
                </div>
                {form.highlights.length > 0 && (
                  <div className="mt-2 flex flex-wrap gap-2">
                    {form.highlights.map((h) => (
                      <Chip key={h} label={h} selected onToggle={() => form.setHighlights(form.highlights.filter((x) => x !== h))} />
                    ))}
                  </div>
                )}
              </Field>
            </>
          )}

          {form.step === "Program Details" && (
            <>
              <Field label="Session Duration" required>
                <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                  {SESSION_DURATIONS.map((d) => (
                    <button
                      key={d.value}
                      type="button"
                      onClick={() => form.setSessionDuration(d.value)}
                      className={cn(
                        "h-10 rounded-lg border text-sm font-medium transition-colors",
                        form.sessionDuration === d.value ? "border-success bg-success/10 text-success" : "border-input hover:bg-accent/50",
                      )}
                    >
                      {d.label}
                    </button>
                  ))}
                </div>
                {form.sessionDuration === "custom" && (
                  <Input
                    type="number"
                    min="1"
                    step="1"
                    onWheel={blurOnWheel}
                    className={cn("mt-2", NO_SPINNER_INPUT)}
                    placeholder="Minutes"
                    value={form.sessionDurationCustomMinutes}
                    onChange={(e) => form.setSessionDurationCustomMinutes(e.target.value)}
                  />
                )}
              </Field>
              <Field label="Sessions Per Week" required>
                <div className="flex flex-wrap gap-2">
                  {SESSIONS_PER_WEEK.map((n) => (
                    <button
                      key={n}
                      type="button"
                      onClick={() => form.setSessionsPerWeek(n)}
                      className={cn(
                        "h-10 w-10 rounded-lg border text-sm font-medium transition-colors",
                        form.sessionsPerWeek === n ? "border-success bg-success/10 text-success" : "border-input hover:bg-accent/50",
                      )}
                    >
                      {n}
                    </button>
                  ))}
                </div>
              </Field>
              <Field label="Program Duration" required>
                <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
                  {PROGRAM_DURATIONS.map((d) => (
                    <button
                      key={d.value}
                      type="button"
                      onClick={() => form.setDurationWeeks(d.value)}
                      className={cn(
                        "h-10 rounded-lg border text-sm font-medium transition-colors",
                        form.durationWeeks === d.value ? "border-success bg-success/10 text-success" : "border-input hover:bg-accent/50",
                      )}
                    >
                      {d.label}
                    </button>
                  ))}
                </div>
              </Field>
              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <Field label="Start Date" required>
                  <Input type="date" value={form.startDate} onChange={(e) => form.setStartDate(e.target.value)} />
                </Field>
                {form.durationWeeks === "custom" ? (
                  <Field label="End Date">
                    <Input type="date" min={form.startDate} value={form.customEndDate} onChange={(e) => form.setCustomEndDate(e.target.value)} />
                  </Field>
                ) : (
                  <Field label="End Date (computed)">
                    <Input type="date" value={form.endDate} disabled />
                  </Field>
                )}
              </div>
              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <Field label="Max Capacity" required>
                  <Input type="number" min="1" step="1" onWheel={blurOnWheel} className={NO_SPINNER_INPUT} value={form.maxCapacity} onChange={(e) => form.setMaxCapacity(e.target.value)} />
                </Field>
                <Field label="Minimum Students (optional)">
                  <Input type="number" min="0" step="1" onWheel={blurOnWheel} className={NO_SPINNER_INPUT} value={form.minCapacity} onChange={(e) => form.setMinCapacity(e.target.value)} />
                </Field>
              </div>
              <Field label="Program Structure" hint={sportName ? `What this ${sportName} program covers, shown to students.` : "What this program covers, shown to students."}>
                <div className="flex flex-wrap gap-2">
                  {structurePresets.map((p) => (
                    <Chip key={p} label={p} selected={form.highlights.includes(p)} onToggle={() => form.toggleHighlight(form.highlights, form.setHighlights, p)} />
                  ))}
                </div>
              </Field>
              <Field label="Session Format (optional)">
                <Input value={form.sessionFormat} onChange={(e) => form.setSessionFormat(e.target.value)} placeholder="e.g. On-court group drills" />
              </Field>
            </>
          )}

          {form.step === "Schedule & Batches" && (
            <>
              {form.batches.length === 0 && (
                <Field label="Weekly Schedule" required hint="A program has exactly one batch — its day/time/court/coach schedule.">
                  <div className="space-y-3 rounded-xl border border-border p-3">
                    <div className="flex flex-wrap gap-2">
                      {DAY_LABELS_SHORT.map((d, i) => (
                        <Chip
                          key={d}
                          label={d}
                          selected={form.weeklySchedule.daysOfWeek.includes(i)}
                          onToggle={() =>
                            form.setWeeklySchedule((s) => ({
                              ...s,
                              daysOfWeek: s.daysOfWeek.includes(i) ? s.daysOfWeek.filter((x) => x !== i) : [...s.daysOfWeek, i].sort(),
                            }))
                          }
                        />
                      ))}
                    </div>
                    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                      <Field label="Start Time" required>
                        <TimeField
                          ariaLabel="Start time"
                          value={form.weeklySchedule.startTime}
                          onChange={(v) => form.setWeeklySchedule((s) => ({ ...s, startTime: v }))}
                        />
                      </Field>
                      <Field label="End Time" required>
                        <TimeField
                          ariaLabel="End time"
                          value={form.weeklySchedule.endTime}
                          onChange={(v) => form.setWeeklySchedule((s) => ({ ...s, endTime: v }))}
                        />
                      </Field>
                      <Field label="Court" required>
                        <Select value={form.weeklySchedule.courtId} onValueChange={(v) => form.setWeeklySchedule((s) => ({ ...s, courtId: v }))}>
                          <SelectTrigger>
                            <SelectValue placeholder="Select a court" />
                          </SelectTrigger>
                          <SelectContent>
                            {courts.map((c) => (
                              <SelectItem key={c.id} value={c.id}>
                                {c.name}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </Field>
                      <Field label="Coach">
                        <Select value={form.weeklySchedule.coachId} onValueChange={(v) => form.setWeeklySchedule((s) => ({ ...s, coachId: v }))}>
                          <SelectTrigger>
                            <SelectValue placeholder="Select a coach" />
                          </SelectTrigger>
                          <SelectContent>
                            {coaches.map((c) => (
                              <SelectItem key={c.id} value={c.id}>
                                {c.name}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </Field>
                    </div>
                    <div className="flex gap-2">
                      <Input value={batchName} onChange={(e) => setBatchName(e.target.value)} placeholder="Batch name, e.g. Morning Batch" />
                      <button
                        type="button"
                        onClick={addBatchFromSchedule}
                        disabled={!batchName.trim() || form.weeklySchedule.daysOfWeek.length === 0 || !form.weeklySchedule.courtId || Boolean(batchDuplicateError)}
                        className="shrink-0 rounded-lg border border-input px-3 text-sm font-medium hover:bg-accent disabled:opacity-50"
                      >
                        Add Batch
                      </button>
                    </div>
                    {batchDuplicateError && <p className="text-xs text-destructive">{batchDuplicateError}</p>}
                  </div>
                </Field>
              )}

              <Field label="Batches" required>
                {form.batches.length === 0 ? (
                  <p className="text-sm text-muted-foreground">No batch added yet — a batch is required before you can continue.</p>
                ) : (
                  <ul className="space-y-2">
                    {form.batches.map((b, i) => {
                      const court = courts.find((c) => c.id === b.courtId);
                      const coach = coaches.find((c) => c.id === b.coachId);
                      return (
                        <li key={i} className="flex items-center justify-between gap-3 rounded-lg border border-border p-3 text-sm">
                          <div className="min-w-0">
                            <p className="font-medium">{b.name}</p>
                            <p className="truncate text-xs text-muted-foreground">
                              {b.daysOfWeek.map((d) => DAY_LABELS_SHORT[d]).join(", ")} · {b.startTime}–{b.endTime} · {court?.name ?? "—"}
                              {coach ? ` · ${coach.name}` : ""} · Capacity {b.capacity}
                            </p>
                          </div>
                          <button type="button" onClick={() => form.removeBatch(i)} className="shrink-0 rounded-md p-1.5 text-muted-foreground hover:bg-destructive/10 hover:text-destructive">
                            <Trash2 className="h-4 w-4" aria-hidden />
                          </button>
                        </li>
                      );
                    })}
                  </ul>
                )}
              </Field>
            </>
          )}

          {form.step === "Pricing & Settings" && (
            <>
              <Field label="Fee Structure">
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                  {(["SINGLE", "PER_SESSION"] as const).map((f) => (
                    <button
                      key={f}
                      type="button"
                      onClick={() => form.setFeeStructure(f)}
                      className={cn(
                        "rounded-xl border p-3 text-left text-sm font-medium transition-colors",
                        form.feeStructure === f ? "border-success bg-success/10 text-success" : "border-input hover:bg-accent/50",
                      )}
                    >
                      {f === "SINGLE" ? "Single Program Fee" : "Per Session Fee"}
                    </button>
                  ))}
                </div>
              </Field>
              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <Field label="Total Program Fee (₹)">
                  <Input type="number" min="0" onWheel={blurOnWheel} className={NO_SPINNER_INPUT} value={form.programFee} onChange={(e) => form.setProgramFee(e.target.value)} />
                </Field>
                <Field label="Payment Mode">
                  <Select value={form.paymentMode} onValueChange={(v) => form.setPaymentMode(v as typeof form.paymentMode)}>
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="OFFLINE">Offline</SelectItem>
                      <SelectItem value="ONLINE">Online</SelectItem>
                      <SelectItem value="BOTH">Offline &amp; Online</SelectItem>
                    </SelectContent>
                  </Select>
                </Field>
              </div>
              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <Field label="Early Bird Discount (₹, optional)">
                  <Input type="number" min="0" onWheel={blurOnWheel} className={NO_SPINNER_INPUT} value={form.earlyBirdDiscount} onChange={(e) => form.setEarlyBirdDiscount(e.target.value)} />
                </Field>
                <Field label="Discount Valid Till (optional)">
                  <Input type="date" value={form.discountValidTill} onChange={(e) => form.setDiscountValidTill(e.target.value)} />
                </Field>
              </div>
              <div className="flex items-center justify-between gap-3 rounded-lg border border-input px-3 py-2.5">
                <span className="text-sm">Apply Tax (GST)</span>
                <ToggleSwitch checked={form.taxApplicable} onChange={form.setTaxApplicable} label="Apply Tax" />
              </div>
              {form.taxApplicable && (
                <Field label="Tax Percent">
                  <Input type="number" min="0" max="100" onWheel={blurOnWheel} className={NO_SPINNER_INPUT} value={form.taxPercent} onChange={(e) => form.setTaxPercent(e.target.value)} />
                </Field>
              )}
              <Field label="Payment Notes (optional)">
                <Textarea rows={2} value={form.paymentNotes} onChange={(e) => form.setPaymentNotes(e.target.value)} />
              </Field>

              <div className="space-y-2 border-t border-border pt-4">
                <p className="text-sm font-semibold">Additional Settings</p>
                {[
                  { label: "Allow Waitlist", checked: form.allowWaitlist, onChange: form.setAllowWaitlist },
                  { label: "Allow Trial Session", checked: form.allowTrialSession, onChange: form.setAllowTrialSession },
                  { label: "Auto Enroll to Next Batch", checked: form.autoEnrollNextBatch, onChange: form.setAutoEnrollNextBatch },
                  { label: "Send Notifications", checked: form.sendNotifications, onChange: form.setSendNotifications },
                  { label: "Visible in Online Booking", checked: form.visibleInBooking, onChange: form.setVisibleInBooking },
                ].map((s) => (
                  <div key={s.label} className="flex items-center justify-between gap-3 rounded-lg border border-input px-3 py-2.5">
                    <span className="text-sm">{s.label}</span>
                    <ToggleSwitch checked={s.checked} onChange={s.onChange} label={s.label} />
                  </div>
                ))}
                <div className="flex items-center justify-between gap-3 rounded-lg border border-input px-3 py-2.5">
                  <span className="text-sm">Enrollment Deadline</span>
                  <ToggleSwitch checked={form.enrollmentDeadlineEnabled} onChange={form.setEnrollmentDeadlineEnabled} label="Enrollment Deadline" />
                </div>
                {form.enrollmentDeadlineEnabled && (
                  <Input type="date" max={form.startDate} value={form.enrollmentDeadline} onChange={(e) => form.setEnrollmentDeadline(e.target.value)} />
                )}
              </div>
            </>
          )}

          {form.step === "Review & Create" && (
            <div className="space-y-4">
              <Card className="overflow-hidden p-0">
                <div className="border-b border-border p-4">
                  <h2 className="text-sm font-bold">Program Summary</h2>
                </div>
                <div className="flex flex-col gap-3 p-4 sm:flex-row">
                  {form.imagePreview ? (
                    // eslint-disable-next-line @next/next/no-img-element -- a local object URL preview, not a served asset
                    <img src={form.imagePreview} alt="" className="h-24 w-32 shrink-0 rounded-lg object-cover" />
                  ) : (
                    <div className="flex h-24 w-32 shrink-0 items-center justify-center rounded-lg bg-muted">
                      <BookOpen className="h-6 w-6 text-muted-foreground" aria-hidden />
                    </div>
                  )}
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <p className="font-semibold">{form.name.trim() || "Untitled Program"}</p>
                      <Badge variant="success">Active</Badge>
                    </div>
                    <p className="mt-1 text-sm text-muted-foreground">{form.description.trim() || "—"}</p>
                    <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground">
                      <span className="flex items-center gap-1">
                        <Tag className="h-3.5 w-3.5" aria-hidden /> {sportName ?? "—"}
                      </span>
                      <span className="flex items-center gap-1">
                        <GraduationCap className="h-3.5 w-3.5" aria-hidden /> {form.level}
                      </span>
                      <span className="flex items-center gap-1">
                        <UsersIcon className="h-3.5 w-3.5" aria-hidden /> Ages {form.ageGroup}
                      </span>
                      <span className="flex items-center gap-1">
                        <UsersIcon className="h-3.5 w-3.5" aria-hidden /> {form.maxCapacity} Students
                      </span>
                    </div>
                  </div>
                </div>
              </Card>

              <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                <ReviewSection n={1} title="Basic Information" onEdit={() => form.setStep("Basic Information")}>
                  <div className="space-y-2">
                    <ReviewRow icon={BookOpen} label="Program Name" value={form.name.trim() || "—"} />
                    <ReviewRow icon={Tag} label="Description" value={form.description.trim() || "—"} />
                    <ReviewRow icon={Tag} label="Sport" value={sportName ?? "—"} />
                    <ReviewRow icon={BookOpen} label="Program Type" value={PROGRAM_TYPE_LABEL[form.programType]!} />
                    {form.highlights.length > 0 && <ReviewRow icon={Tag} label="Key Highlights" value={form.highlights.join(", ")} />}
                  </div>
                </ReviewSection>

                <ReviewSection n={2} title="Program Details" onEdit={() => form.setStep("Program Details")}>
                  <div className="space-y-2">
                    <ReviewRow icon={UsersIcon} label="Age Group" value={form.ageGroup} />
                    <ReviewRow icon={GraduationCap} label="Skill Level" value={form.level} />
                    <ReviewRow icon={Clock} label="Session Duration" value={`${form.effectiveSessionDuration} minutes`} />
                    <ReviewRow icon={Repeat} label="Sessions per Week" value={String(form.sessionsPerWeek)} />
                    <ReviewRow icon={Calendar} label="Program Duration" value={form.weeksInProgram > 0 ? `${form.weeksInProgram} Weeks` : "—"} />
                    <ReviewRow icon={Calendar} label="Start Date" value={fmtReviewDate(form.startDate)} />
                    <ReviewRow icon={Calendar} label="End Date" value={fmtReviewDate(form.endDate)} />
                    <ReviewRow icon={UsersIcon} label="Max Capacity" value={`${form.maxCapacity} Students`} />
                    {form.minCapacity.trim() && <ReviewRow icon={UsersIcon} label="Minimum Students" value={`${form.minCapacity} Students`} />}
                  </div>
                </ReviewSection>
              </div>

              <ReviewSection n={3} title="Schedule & Batches" onEdit={() => form.setStep("Schedule & Batches")}>
                {form.batches.length === 0 ? (
                  <p className="text-sm text-muted-foreground">No batches added yet.</p>
                ) : (
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead>
                        <tr className="border-b border-border text-left text-xs text-muted-foreground">
                          <th className="py-2 pr-3 font-medium">Batch</th>
                          <th className="py-2 pr-3 font-medium">Day</th>
                          <th className="py-2 pr-3 font-medium">Time</th>
                          <th className="py-2 pr-3 font-medium">Court</th>
                          <th className="py-2 pr-3 font-medium">Coach</th>
                        </tr>
                      </thead>
                      <tbody>
                        {form.batches.flatMap((b, bi) =>
                          b.daysOfWeek.map((d) => {
                            const court = courts.find((c) => c.id === b.courtId);
                            const coach = coaches.find((c) => c.id === b.coachId);
                            return (
                              <tr key={`${bi}-${d}`} className="border-b border-border last:border-0">
                                <td className="py-2 pr-3 font-medium">{b.name}</td>
                                <td className="py-2 pr-3 text-muted-foreground">{DAY_LABELS_SHORT[d]}</td>
                                <td className="py-2 pr-3 text-muted-foreground">
                                  {b.startTime}–{b.endTime}
                                </td>
                                <td className="py-2 pr-3 text-muted-foreground">{court?.name ?? "—"}</td>
                                <td className="py-2 pr-3 text-muted-foreground">{coach?.name ?? "—"}</td>
                              </tr>
                            );
                          }),
                        )}
                      </tbody>
                    </table>
                  </div>
                )}
              </ReviewSection>

              <ReviewSection n={4} title="Pricing & Settings" onEdit={() => form.setStep("Pricing & Settings")}>
                <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                  <div className="space-y-2">
                    <ReviewRow icon={IndianRupee} label="Fee Structure" value={form.feeStructure === "SINGLE" ? "Single Program Fee" : "Per Session Fee"} />
                    {form.feeStructure === "PER_SESSION" ? (
                      <>
                        <ReviewRow icon={IndianRupee} label="Per Session Fee" value={money(form.priceInr * 100)} />
                        <ReviewRow icon={Repeat} label="Total Sessions" value={String(form.totalSessionsInProgram)} />
                      </>
                    ) : (
                      <ReviewRow icon={IndianRupee} label="Program Fee" value={money(form.priceInr * 100)} />
                    )}
                    {form.discountInr > 0 && (
                      <ReviewRow
                        icon={Percent}
                        label="Early Bird Discount"
                        value={`${money(form.discountInr * 100)}${form.discountValidTill ? ` (till ${fmtReviewDate(form.discountValidTill)})` : ""}`}
                      />
                    )}
                    <ReviewRow icon={Percent} label="Tax Applicable" value={form.taxApplicable ? `Yes (${form.taxPercent}% GST)` : "No"} />
                    <ReviewRow icon={IndianRupee} label="Payment Mode" value={{ OFFLINE: "Offline", ONLINE: "Online", BOTH: "Offline & Online" }[form.paymentMode]} />
                  </div>
                  <div className="space-y-2">
                    <ReviewRow icon={UsersIcon} label="Allow Waitlist" value={form.allowWaitlist ? "Yes" : "No"} />
                    <ReviewRow icon={UsersIcon} label="Allow Trial Session" value={form.allowTrialSession ? "Yes" : "No"} />
                    <ReviewRow icon={Repeat} label="Auto Enroll to Next Batch" value={form.autoEnrollNextBatch ? "Yes" : "No"} />
                    <ReviewRow icon={Bell} label="Send Notifications" value={form.sendNotifications ? "Yes" : "No"} />
                    <ReviewRow icon={Eye} label="Visible in Online Booking" value={form.visibleInBooking ? "Yes" : "No"} />
                    <ReviewRow
                      icon={CalendarClock}
                      label="Enrollment Deadline"
                      value={form.enrollmentDeadlineEnabled ? fmtReviewDate(form.enrollmentDeadline) : "None"}
                    />
                  </div>
                </div>

                <div className="mt-4 rounded-xl border border-primary/20 bg-primary/5 p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm font-semibold">Total Fee per Student</p>
                      <p className="text-xs text-muted-foreground">
                        {form.feeStructure === "PER_SESSION"
                          ? `${money(form.priceInr * 100)} × ${form.totalSessionsInProgram} sessions${form.discountInr > 0 ? " − discount" : ""}${form.taxApplicable ? " + tax" : ""}`
                          : `Program fee${form.discountInr > 0 ? " − discount" : ""}${form.taxApplicable ? " + tax" : ""}`}
                      </p>
                    </div>
                    <p className="text-2xl font-bold tabular-nums text-primary">{money(form.totalFeeInr * 100)}</p>
                  </div>
                  {form.batches.length > 0 && (
                    <p className="mt-2 flex items-center gap-1.5 text-xs text-muted-foreground">
                      <MapPin className="h-3.5 w-3.5" aria-hidden />
                      Estimated total across {form.maxCapacity} students: {money(form.totalFeeInr * Number(form.maxCapacity) * 100)}
                    </p>
                  )}
                </div>
              </ReviewSection>
            </div>
          )}

          {form.error && <p className="text-sm text-destructive">{form.error}</p>}

          <div className="flex items-center justify-between border-t border-border pt-4">
            {stepIndex === 0 ? (
              <Link href="/coaching/programs" className="flex h-10 items-center gap-2 rounded-lg border border-input px-4 text-sm font-medium hover:bg-accent">
                <ArrowLeft className="h-4 w-4" aria-hidden />
                Cancel
              </Link>
            ) : (
              <button type="button" onClick={form.back} disabled={form.busy} className="flex h-10 items-center gap-2 rounded-lg border border-input px-4 text-sm font-medium hover:bg-accent">
                <ArrowLeft className="h-4 w-4" aria-hidden />
                Back
              </button>
            )}
            <div className="flex items-center gap-2">
              {form.step === "Review & Create" && (
                <button type="button" onClick={() => void handleSubmit("DRAFT")} disabled={form.busy} className="h-10 rounded-lg border border-input px-4 text-sm font-medium hover:bg-accent">
                  Save as Draft
                </button>
              )}
              {stepIndex < PROGRAM_STEPS.length - 1 ? (
                <button
                  type="button"
                  onClick={form.next}
                  disabled={!stepValid}
                  className="flex h-10 items-center gap-2 rounded-lg bg-primary px-4 text-sm font-medium text-primary-foreground transition-opacity hover:opacity-90 disabled:opacity-50"
                >
                  Next
                  <ArrowRight className="h-4 w-4" aria-hidden />
                </button>
              ) : (
                <button
                  type="button"
                  onClick={() => void handleSubmit("ACTIVE")}
                  disabled={form.busy || !form.canSubmit}
                  className="flex h-10 items-center gap-2 rounded-lg bg-primary px-4 text-sm font-medium text-primary-foreground transition-opacity hover:opacity-90 disabled:opacity-50"
                >
                  {form.busy ? (form.uploadingImage ? "Uploading image…" : "Creating…") : "Create Program"}
                </button>
              )}
            </div>
          </div>
        </Card>

        {form.step !== "Review & Create" && (
          <div>
            <ProgramPreviewPanel form={form} sportName={sportName} />
          </div>
        )}
      </div>
    </div>
  );
}
