"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import {
  Bell,
  BookOpen,
  CalendarClock,
  Eye,
  ImagePlus,
  IndianRupee,
  MapPin,
  Pencil,
  Percent,
  Repeat,
  Tag,
  Users,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { DisabledReason } from "@/components/ui/tooltip";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { ToggleSwitch } from "@/features/bookings/components/toggle-switch";
import { useFacilitySportOptions } from "@/features/facility/hooks/use-facility-sport-options";
import { ServiceError } from "@/services/shared/service-error";
import { getCoachingService } from "@/services/coaching";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import {
  AGE_GROUPS,
  PROGRAM_DURATIONS,
  SESSIONS_PER_WEEK,
  SESSION_DURATIONS,
  SKILL_LEVELS,
  addWeeksIso,
  programStructurePresetsForSport,
} from "@/features/coaching/components/use-program-wizard-form";
import type { ProgramDetail, ProgramFeeType, ProgramPaymentMode, ProgramType } from "@/features/coaching/types";
import {
  Chip,
  ErrorState,
  PageHeader,
  TableSkeleton,
  blurOnWheel,
  fmtDate,
  minorToRupees,
  money,
  NO_SPINNER_INPUT,
  rupeesToMinor,
} from "@/features/coaching/components/shared";

const PROGRAM_TYPES: { value: ProgramType; label: string }[] = [
  { value: "GROUP", label: "Group Program" },
  { value: "ONE_ON_ONE", label: "One-on-One" },
  { value: "TRIAL", label: "Trial Program" },
];
const PROGRAM_TYPE_LABEL: Record<ProgramType, string> = { GROUP: "Group Program", ONE_ON_ONE: "One-on-One", TRIAL: "Trial Program" };

export function ProgramDetailsPage({ programId }: { programId: string }) {
  const perms = usePermissionContext();
  const [program, setProgram] = useState<ProgramDetail | null>(null);
  const [state, setState] = useState<"loading" | "ready" | "error">("loading");
  const [error, setError] = useState<string | null>(null);
  const [editingSection, setEditingSection] = useState<"basic" | "details" | "pricing" | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setState("loading");
    setError(null);
    try {
      setProgram(await getCoachingService().getProgram(programId));
      setState("ready");
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to load this program.");
      setState("error");
    }
  }, [programId]);

  useEffect(() => {
    void load();
  }, [load]);

  const canManage = perms?.can("COACHING_MANAGE_PROGRAMS") ?? false;
  const canPrice = perms?.can("COACHING_MANAGE_PRICING") ?? false;

  async function toggleStatus() {
    if (!program) return;
    setBusy(true);
    try {
      await getCoachingService().updateProgram({
        programId: program.id,
        status: program.status === "ACTIVE" ? "INACTIVE" : "ACTIVE",
      });
      await load();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not update the program.");
    } finally {
      setBusy(false);
    }
  }

  if (state === "error") {
    return (
      <div className="space-y-4">
        <Back />
        <Card className="p-0">
          <ErrorState message={error ?? ""} onRetry={() => void load()} />
        </Card>
      </div>
    );
  }
  if (state === "loading" || !program) {
    return (
      <div className="space-y-4">
        <Back />
        <Card className="p-0">
          <TableSkeleton rows={5} />
        </Card>
      </div>
    );
  }

  const p = program;
  // Once students have joined, the program's terms are what they signed up for: editing it or
  // switching it off underneath them is blocked. (Reactivating an inactive program stays allowed.)
  const lockReason =
    p.stats.activeStudents > 0
      ? `${p.stats.activeStudents} ${p.stats.activeStudents === 1 ? "student is" : "students are"} enrolled in this program, so it can't be edited or deactivated.`
      : undefined;
  const onSaved = () => {
    setEditingSection(null);
    void load();
  };

  return (
    <div className="space-y-4">
      <Back />
      <PageHeader
        title={p.name}
        subtitle={`${p.level} · ${p.ageGroup} · ${p.category}`}
        action={
          canManage && (
            <DisabledReason reason={p.status === "ACTIVE" ? lockReason : undefined}>
              <Button
                size="sm"
                variant="outline"
                disabled={busy || (p.status === "ACTIVE" && Boolean(lockReason))}
                onClick={() => void toggleStatus()}
              >
                {p.status === "ACTIVE" ? "Deactivate" : "Reactivate"}
              </Button>
            </DisabledReason>
          )
        }
      />

      <div className="flex flex-wrap items-center gap-2">
        <Badge variant={p.status === "ACTIVE" ? "success" : "secondary"}>
          {p.status === "ACTIVE" ? "Active" : "Inactive"}
        </Badge>
        {p.isMembershipIncluded && <Badge variant="outline">Membership-included</Badge>}
      </div>
      {canManage && lockReason && <p className="text-xs text-muted-foreground">{lockReason}</p>}

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Stat label="Active Students" value={String(p.stats.activeStudents)} />
        <Stat label="Total Enrollments" value={String(p.stats.totalEnrollments)} />
        {/* Mirrors "Total Sessions" (sessions/week × program weeks) rather than the count of
         *  actual coaching_sessions rows — those are only created once someone schedules real
         *  sessions via Coach Scheduler, so this is the planned total, not a live count. */}
        <Stat label="Scheduled Sessions" value={totalSessions(p)} />
        <Stat label="Completed Sessions" value={String(p.stats.completedSessions)} />
      </div>

      <Card className="p-4">
        <SectionHeader title="Basic Information" onEdit={canManage ? () => setEditingSection("basic") : undefined} lockedReason={lockReason} />
        <div className="mt-3 flex flex-col gap-3 sm:flex-row">
          {p.imageUrl ? (
            // eslint-disable-next-line @next/next/no-img-element -- user-uploaded program image
            <img src={p.imageUrl} alt="" className="h-24 w-32 shrink-0 rounded-lg object-cover" />
          ) : (
            <div className="flex h-24 w-32 shrink-0 items-center justify-center rounded-lg bg-muted">
              <BookOpen className="h-6 w-6 text-muted-foreground" aria-hidden />
            </div>
          )}
          <div className="min-w-0 flex-1 text-sm">
            <Row label="Program Name" value={p.name} />
            <Row label="Program Type" value={PROGRAM_TYPE_LABEL[p.programType]} />
            <Row label="Age Group" value={p.ageGroup} />
            <Row label="Skill Level" value={p.level} />
            {p.description && <p className="mt-2 text-sm text-muted-foreground">{p.description}</p>}
          </div>
        </div>
      </Card>

      <Card className="p-4">
        <SectionHeader title="Program Details" onEdit={canManage ? () => setEditingSection("details") : undefined} lockedReason={lockReason} />
        {(() => {
          // Only fields that actually have a value — an unfilled optional (Minimum Students,
          // Session Format, …) is left off entirely rather than shown as a bare "—".
          const fields = [
            { label: "Session Duration", value: `${p.defaultDurationMinutes} min` },
            { label: "Sessions Per Week", value: p.sessionsPerWeek != null ? String(p.sessionsPerWeek) : null },
            { label: "Program Duration", value: p.startDate && p.endDate ? durationWeeksLabel(p) : null },
            { label: "Start Date", value: p.startDate ? fmtDate(p.startDate) : null },
            { label: "End Date", value: p.endDate ? fmtDate(p.endDate) : null },
            { label: "Max Capacity", value: String(p.defaultCapacity) },
            { label: "Minimum Students", value: p.minCapacity != null ? String(p.minCapacity) : null },
            { label: "Total Sessions", value: totalSessions(p) === "—" ? null : totalSessions(p) },
            { label: "Session Format", value: p.sessionFormat },
            { label: "Created", value: fmtDate(p.createdAt) },
          ].filter((f): f is { label: string; value: string } => Boolean(f.value));
          const half = Math.ceil(fields.length / 2);
          const columns = [fields.slice(0, half), fields.slice(half)];
          return (
            <div className="mt-3 grid grid-cols-1 gap-x-8 text-sm sm:grid-cols-2">
              {columns.map((col, i) => (
                <dl key={i}>
                  {col.map((f) => (
                    <Row key={f.label} label={f.label} value={f.value} />
                  ))}
                </dl>
              ))}
            </div>
          );
        })()}
        {p.programStructure.length > 0 && (
          <div className="mt-3">
            <p className="text-xs text-muted-foreground">Program Structure</p>
            <div className="mt-1.5 flex flex-wrap gap-1.5">
              {p.programStructure.map((s) => (
                <Badge key={s} variant="outline">
                  {s}
                </Badge>
              ))}
            </div>
          </div>
        )}
      </Card>

      <Card className="p-4">
        <SectionHeader title="Pricing & Settings" onEdit={canManage && canPrice ? () => setEditingSection("pricing") : undefined} lockedReason={lockReason} />
        {(() => {
          const baseFeeInr = p.defaultPriceMinor != null ? p.defaultPriceMinor / 100 : 0;
          const discountInr = p.earlyBirdDiscountMinor != null ? p.earlyBirdDiscountMinor / 100 : 0;
          const taxInr = p.taxPercent ? Math.round(((baseFeeInr - discountInr) * p.taxPercent) / 100) : 0;
          const totalInr = Math.max(0, baseFeeInr - discountInr) + taxInr;
          return (
            <>
              <div className="mt-3 grid grid-cols-1 gap-x-8 sm:grid-cols-2">
                <dl className="text-sm">
                  <IconRow icon={IndianRupee} label="Program Fee" value={p.isMembershipIncluded ? "Included" : p.defaultPriceMinor != null ? money(p.defaultPriceMinor) : "—"} />
                  {p.earlyBirdDiscountMinor != null && (
                    <IconRow
                      icon={Percent}
                      label="Early Bird Discount"
                      value={`${money(p.earlyBirdDiscountMinor)}${p.discountValidTill ? ` (till ${fmtDate(p.discountValidTill)})` : ""}`}
                    />
                  )}
                  <IconRow icon={Percent} label="Tax Applicable" value={p.taxPercent ? `Yes (${p.taxPercent}% GST)` : "No"} />
                  <IconRow icon={IndianRupee} label="Fee Type" value={p.feeType === "MONTHLY" ? "Monthly" : "One-time"} />
                  <IconRow icon={IndianRupee} label="Payment Mode" value={{ OFFLINE: "Offline", ONLINE: "Online", BOTH: "Offline & Online" }[p.paymentMode]} />
                  {p.paymentNotes && <IconRow icon={Tag} label="Payment Notes" value={p.paymentNotes} />}
                </dl>
                <dl className="text-sm">
                  <IconRow icon={Users} label="Allow Waitlist" value={p.allowWaitlist ? "Yes" : "No"} />
                  <IconRow icon={Users} label="Allow Trial Session" value={p.allowTrialSession ? "Yes" : "No"} />
                  <IconRow icon={Repeat} label="Auto Enroll to Next Batch" value={p.autoEnrollNextBatch ? "Yes" : "No"} />
                  <IconRow icon={Bell} label="Send Notifications" value={p.sendNotifications ? "Yes" : "No"} />
                  <IconRow icon={Eye} label="Visible in Online Booking" value={p.visibleInBooking ? "Yes" : "No"} />
                  <IconRow icon={CalendarClock} label="Enrollment Deadline" value={p.enrollmentDeadline ? fmtDate(p.enrollmentDeadline) : "None"} />
                </dl>
              </div>
              {!p.isMembershipIncluded && p.defaultPriceMinor != null && (
                <div className="mt-4 rounded-xl border border-primary/20 bg-primary/5 p-4">
                  <div className="flex items-center justify-between">
                    <p className="text-sm font-semibold">Total Fee per Student</p>
                    <p className="text-2xl font-bold tabular-nums text-primary">{money(Math.round(totalInr * 100))}</p>
                  </div>
                  <p className="mt-2 flex items-center gap-1.5 text-xs text-muted-foreground">
                    <MapPin className="h-3.5 w-3.5" aria-hidden />
                    Estimated total across {p.defaultCapacity} students: {money(Math.round(totalInr * p.defaultCapacity * 100))}
                  </p>
                </div>
              )}
            </>
          );
        })()}
      </Card>

      <Card className="p-4">
        <h2 className="text-sm font-semibold">Batches</h2>
        {p.batches.length === 0 ? (
          <p className="mt-2 text-sm text-muted-foreground">No batches set up for this program yet.</p>
        ) : (
          <ul className="mt-3 space-y-2">
            {p.batches.map((b) => (
              <li key={b.id} className="flex items-center justify-between gap-3 rounded-lg border border-border p-3 text-sm">
                <div className="min-w-0">
                  <p className="font-medium">{b.name}</p>
                  <p className="truncate text-xs text-muted-foreground">
                    {b.daysOfWeek.map((d) => DAY_ABBR[d]).join(", ")} · {b.startTime}–{b.endTime} · {b.courtName}
                    {b.coachName ? ` · ${b.coachName}` : ""}
                  </p>
                </div>
                <Badge variant={b.status === "ACTIVE" ? "success" : "secondary"}>{b.enrolledCount ?? 0} / {b.capacity}</Badge>
              </li>
            ))}
          </ul>
        )}
      </Card>

      {editingSection === "basic" && <EditBasicInfoDialog program={p} onClose={() => setEditingSection(null)} onSaved={onSaved} />}
      {editingSection === "details" && <EditProgramDetailsDialog program={p} onClose={() => setEditingSection(null)} onSaved={onSaved} />}
      {editingSection === "pricing" && <EditPricingDialog program={p} onClose={() => setEditingSection(null)} onSaved={onSaved} />}
    </div>
  );
}

function SectionHeader({ title, onEdit, lockedReason }: { title: string; onEdit?: () => void; lockedReason?: string }) {
  return (
    <div className="flex items-center justify-between">
      <h2 className="text-sm font-semibold">{title}</h2>
      {onEdit && (
        <DisabledReason reason={lockedReason}>
          <button
            type="button"
            onClick={onEdit}
            disabled={Boolean(lockedReason)}
            className="flex h-8 items-center gap-1.5 rounded-lg border border-input px-2.5 text-xs font-semibold transition-colors hover:bg-accent disabled:pointer-events-none disabled:opacity-50"
          >
            <Pencil className="h-3.5 w-3.5" aria-hidden />
            Edit
          </button>
        </DisabledReason>
      )}
    </div>
  );
}

/** Basic Information — matches the wizard's step 1 field set exactly (Program Name, Sport,
 *  Description, Program Type, Age Group, Skill Level, Program Image), including fields the
 *  program was created without, so they can be filled in here. */
function EditBasicInfoDialog({ program, onClose, onSaved }: { program: ProgramDetail; onClose: () => void; onSaved: () => void }) {
  const perms = usePermissionContext();
  const sportsQuery = useFacilitySportOptions(perms?.facilityId ?? undefined);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [name, setName] = useState(program.name);
  const [facilitySportId, setFacilitySportId] = useState(program.facilitySportId ?? "");
  const [description, setDescription] = useState(program.description ?? "");
  const [programType, setProgramType] = useState<ProgramType>(program.programType);
  const [ageGroup, setAgeGroup] = useState(program.ageGroup);
  const [level, setLevel] = useState(program.level);
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(program.imageUrl);
  const [uploadingImage, setUploadingImage] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function pickImage(file: File | undefined) {
    if (!file) return;
    setImageFile(file);
    setImagePreview((prev) => {
      if (prev && prev.startsWith("blob:")) URL.revokeObjectURL(prev);
      return URL.createObjectURL(file);
    });
  }

  async function save() {
    setBusy(true);
    setError(null);
    try {
      let imageUrl: string | undefined;
      if (imageFile) {
        setUploadingImage(true);
        try {
          imageUrl = await getCoachingService().uploadProgramImage(imageFile);
        } finally {
          setUploadingImage(false);
        }
      }
      await getCoachingService().updateProgram({
        programId: program.id,
        name: name.trim(),
        facilitySportId: facilitySportId || null,
        description: description.trim() || null,
        programType,
        ageGroup,
        level,
        ...(imageUrl ? { imageUrl } : {}),
      });
      onSaved();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not save changes.");
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(v) => !v && !busy && onClose()}>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Edit Basic Information</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <Field label="Program Name">
            <Input value={name} onChange={(e) => setName(e.target.value)} />
          </Field>
          <Field label="Sport">
            <Select value={facilitySportId} onValueChange={setFacilitySportId}>
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
          <Field label="Description">
            <Textarea rows={3} maxLength={500} value={description} onChange={(e) => setDescription(e.target.value)} />
          </Field>
          <Field label="Program Image">
            <label className="flex h-24 w-32 cursor-pointer flex-col items-center justify-center gap-1.5 rounded-lg border border-dashed border-input text-muted-foreground transition-colors hover:border-foreground/30">
              {imagePreview ? (
                // eslint-disable-next-line @next/next/no-img-element -- a local object URL preview or the existing served image
                <img src={imagePreview} alt="" className="h-full w-full rounded-lg object-cover" />
              ) : (
                <>
                  <ImagePlus className="h-5 w-5" aria-hidden />
                  <span className="text-xs">Upload</span>
                </>
              )}
              <input ref={fileInputRef} type="file" accept="image/jpeg,image/png,image/webp" className="hidden" onChange={(e) => pickImage(e.target.files?.[0])} />
            </label>
          </Field>
          <Field label="Program Type">
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
              {PROGRAM_TYPES.map((t) => (
                <button
                  key={t.value}
                  type="button"
                  onClick={() => setProgramType(t.value)}
                  className={`rounded-lg border p-2 text-left text-xs font-medium transition-colors ${programType === t.value ? "border-success bg-success/10 text-success" : "border-input hover:bg-accent/50"}`}
                >
                  {t.label}
                </button>
              ))}
            </div>
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Age Group">
              <Select value={ageGroup} onValueChange={setAgeGroup}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {AGE_GROUPS.map((a) => (
                    <SelectItem key={a} value={a}>
                      {a}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field label="Skill Level">
              <Select value={level} onValueChange={setLevel}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {SKILL_LEVELS.map((l) => (
                    <SelectItem key={l} value={l}>
                      {l}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
          </div>
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" disabled={busy} onClick={onClose}>
            Cancel
          </Button>
          <Button disabled={busy} onClick={() => void save()}>
            {busy ? (uploadingImage ? "Uploading image…" : "Saving…") : "Save"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** Program Details — matches the wizard's step 2 field set exactly, so a program created without
 *  (say) a Session Format or Minimum Students can have them filled in here afterwards. */
function EditProgramDetailsDialog({ program, onClose, onSaved }: { program: ProgramDetail; onClose: () => void; onSaved: () => void }) {
  const perms = usePermissionContext();
  const sportsQuery = useFacilitySportOptions(perms?.facilityId ?? undefined);
  const sportName = sportsQuery.data?.find((s) => s.facilitySportId === program.facilitySportId)?.name;
  const structurePresets = programStructurePresetsForSport(sportName);

  const isDurationPreset = SESSION_DURATIONS.some((d) => d.value === String(program.defaultDurationMinutes));
  const [sessionDuration, setSessionDuration] = useState(isDurationPreset ? String(program.defaultDurationMinutes) : "custom");
  const [customDuration, setCustomDuration] = useState(isDurationPreset ? "" : String(program.defaultDurationMinutes));
  const [sessionsPerWeek, setSessionsPerWeek] = useState(program.sessionsPerWeek ?? 3);

  const startDate = program.startDate ?? "";
  const weeksFromDates =
    program.startDate && program.endDate
      ? Math.max(1, Math.round((new Date(program.endDate).getTime() - new Date(program.startDate).getTime()) / (7 * 86_400_000)))
      : null;
  const isWeeksPreset = weeksFromDates != null && PROGRAM_DURATIONS.some((d) => d.value === String(weeksFromDates));
  const [durationWeeks, setDurationWeeks] = useState(weeksFromDates == null ? "12" : isWeeksPreset ? String(weeksFromDates) : "custom");
  const [start, setStart] = useState(startDate || new Date().toISOString().slice(0, 10));
  const [customEndDate, setCustomEndDate] = useState(!isWeeksPreset ? (program.endDate ?? "") : "");

  const [maxCapacity, setMaxCapacity] = useState(String(program.defaultCapacity));
  const [minCapacity, setMinCapacity] = useState(program.minCapacity != null ? String(program.minCapacity) : "");
  const [structure, setStructure] = useState<string[]>(program.programStructure);
  const [sessionFormat, setSessionFormat] = useState(program.sessionFormat ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const endDate = durationWeeks === "custom" ? customEndDate : addWeeksIso(start, Number(durationWeeks));

  function toggleStructure(value: string) {
    setStructure((s) => (s.includes(value) ? s.filter((v) => v !== value) : [...s, value]));
  }

  async function save() {
    setBusy(true);
    setError(null);
    try {
      await getCoachingService().updateProgram({
        programId: program.id,
        defaultDurationMinutes: sessionDuration === "custom" ? Number(customDuration) || program.defaultDurationMinutes : Number(sessionDuration),
        sessionsPerWeek,
        startDate: start,
        endDate,
        defaultCapacity: Number(maxCapacity) || program.defaultCapacity,
        minCapacity: minCapacity.trim() ? Number(minCapacity) : null,
        programStructure: structure,
        sessionFormat: sessionFormat.trim() || null,
      });
      onSaved();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not save changes.");
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(v) => !v && !busy && onClose()}>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Edit Program Details</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <Field label="Session Duration">
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
              {SESSION_DURATIONS.map((d) => (
                <button
                  key={d.value}
                  type="button"
                  onClick={() => setSessionDuration(d.value)}
                  className={`h-9 rounded-lg border text-sm font-medium transition-colors ${sessionDuration === d.value ? "border-success bg-success/10 text-success" : "border-input hover:bg-accent/50"}`}
                >
                  {d.label}
                </button>
              ))}
            </div>
            {sessionDuration === "custom" && (
              <Input type="number" min="1" onWheel={blurOnWheel} className={NO_SPINNER_INPUT} placeholder="Minutes" value={customDuration} onChange={(e) => setCustomDuration(e.target.value)} />
            )}
          </Field>
          <Field label="Sessions Per Week">
            <div className="flex flex-wrap gap-2">
              {SESSIONS_PER_WEEK.map((n) => (
                <button
                  key={n}
                  type="button"
                  onClick={() => setSessionsPerWeek(n)}
                  className={`h-9 w-9 rounded-lg border text-sm font-medium transition-colors ${sessionsPerWeek === n ? "border-success bg-success/10 text-success" : "border-input hover:bg-accent/50"}`}
                >
                  {n}
                </button>
              ))}
            </div>
          </Field>
          <Field label="Program Duration">
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
              {PROGRAM_DURATIONS.map((d) => (
                <button
                  key={d.value}
                  type="button"
                  onClick={() => setDurationWeeks(d.value)}
                  className={`h-9 rounded-lg border text-sm font-medium transition-colors ${durationWeeks === d.value ? "border-success bg-success/10 text-success" : "border-input hover:bg-accent/50"}`}
                >
                  {d.label}
                </button>
              ))}
            </div>
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Start Date">
              <Input type="date" value={start} onChange={(e) => setStart(e.target.value)} />
            </Field>
            {durationWeeks === "custom" ? (
              <Field label="End Date">
                <Input type="date" min={start} value={customEndDate} onChange={(e) => setCustomEndDate(e.target.value)} />
              </Field>
            ) : (
              <Field label="End Date (computed)">
                <Input type="date" value={endDate} disabled />
              </Field>
            )}
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Max Capacity">
              <Input type="number" min="1" onWheel={blurOnWheel} className={NO_SPINNER_INPUT} value={maxCapacity} onChange={(e) => setMaxCapacity(e.target.value)} />
            </Field>
            <Field label="Minimum Students (optional)">
              <Input type="number" min="0" onWheel={blurOnWheel} className={NO_SPINNER_INPUT} value={minCapacity} onChange={(e) => setMinCapacity(e.target.value)} />
            </Field>
          </div>
          <Field label="Program Structure">
            <div className="flex flex-wrap gap-2">
              {structurePresets.map((s) => (
                <Chip key={s} label={s} selected={structure.includes(s)} onToggle={() => toggleStructure(s)} />
              ))}
            </div>
          </Field>
          <Field label="Session Format (optional)">
            <Input value={sessionFormat} onChange={(e) => setSessionFormat(e.target.value)} placeholder="e.g. On-court group drills" />
          </Field>
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" disabled={busy} onClick={onClose}>
            Cancel
          </Button>
          <Button disabled={busy} onClick={() => void save()}>
            {busy ? "Saving…" : "Save"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** Pricing & Settings — matches the wizard's step 4 field set exactly. */
function EditPricingDialog({ program, onClose, onSaved }: { program: ProgramDetail; onClose: () => void; onSaved: () => void }) {
  const [programFee, setProgramFee] = useState(minorToRupees(program.defaultPriceMinor));
  const [paymentMode, setPaymentMode] = useState<ProgramPaymentMode>(program.paymentMode);
  const [feeType, setFeeType] = useState<ProgramFeeType>(program.feeType);
  const [earlyBirdDiscount, setEarlyBirdDiscount] = useState(minorToRupees(program.earlyBirdDiscountMinor));
  const [discountValidTill, setDiscountValidTill] = useState(program.discountValidTill ?? "");
  const [taxApplicable, setTaxApplicable] = useState(program.taxPercent != null);
  const [taxPercent, setTaxPercent] = useState(program.taxPercent != null ? String(program.taxPercent) : "18");
  const [paymentNotes, setPaymentNotes] = useState(program.paymentNotes ?? "");
  const [allowWaitlist, setAllowWaitlist] = useState(program.allowWaitlist);
  const [allowTrialSession, setAllowTrialSession] = useState(program.allowTrialSession);
  const [autoEnrollNextBatch, setAutoEnrollNextBatch] = useState(program.autoEnrollNextBatch);
  const [sendNotifications, setSendNotifications] = useState(program.sendNotifications);
  const [visibleInBooking, setVisibleInBooking] = useState(program.visibleInBooking);
  const [enrollmentDeadlineEnabled, setEnrollmentDeadlineEnabled] = useState(Boolean(program.enrollmentDeadline));
  const [enrollmentDeadline, setEnrollmentDeadline] = useState(program.enrollmentDeadline ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save() {
    setBusy(true);
    setError(null);
    try {
      await getCoachingService().updateProgram({
        programId: program.id,
        defaultPriceMinor: programFee.trim() ? rupeesToMinor(programFee) : null,
        paymentMode,
        feeType,
        earlyBirdDiscountMinor: earlyBirdDiscount.trim() ? rupeesToMinor(earlyBirdDiscount) : null,
        discountValidTill: discountValidTill.trim() || null,
        taxPercent: taxApplicable ? Number(taxPercent) : null,
        paymentNotes: paymentNotes.trim() || null,
        allowWaitlist,
        allowTrialSession,
        autoEnrollNextBatch,
        sendNotifications,
        visibleInBooking,
        enrollmentDeadline: enrollmentDeadlineEnabled && enrollmentDeadline.trim() ? enrollmentDeadline : null,
      });
      onSaved();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not save changes.");
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(v) => !v && !busy && onClose()}>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Edit Pricing &amp; Settings</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Field label="Fee Type">
              <Select value={feeType} onValueChange={(v) => setFeeType(v as ProgramFeeType)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="ONE_TIME">One-time</SelectItem>
                  <SelectItem value="MONTHLY">Monthly (fee below is per month)</SelectItem>
                </SelectContent>
              </Select>
            </Field>
            <Field label={feeType === "MONTHLY" ? "Fee per Month (₹)" : "Program Fee (₹)"}>
              <Input type="number" min="0" onWheel={blurOnWheel} className={NO_SPINNER_INPUT} value={programFee} onChange={(e) => setProgramFee(e.target.value)} />
            </Field>
            <Field label="Payment Mode">
              <Select value={paymentMode} onValueChange={(v) => setPaymentMode(v as ProgramPaymentMode)}>
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
          <div className="grid grid-cols-2 gap-3">
            <Field label="Early Bird Discount (₹, optional)">
              <Input type="number" min="0" onWheel={blurOnWheel} className={NO_SPINNER_INPUT} value={earlyBirdDiscount} onChange={(e) => setEarlyBirdDiscount(e.target.value)} />
            </Field>
            <Field label="Discount Valid Till (optional)">
              <Input type="date" value={discountValidTill} onChange={(e) => setDiscountValidTill(e.target.value)} />
            </Field>
          </div>
          <div className="flex items-center justify-between gap-3 rounded-lg border border-input px-3 py-2.5">
            <span className="text-sm">Apply Tax (GST)</span>
            <ToggleSwitch checked={taxApplicable} onChange={setTaxApplicable} label="Apply Tax" onClass="bg-[#0B9B63]" />
          </div>
          {taxApplicable && (
            <Field label="Tax Percent">
              <Input type="number" min="0" max="100" onWheel={blurOnWheel} className={NO_SPINNER_INPUT} value={taxPercent} onChange={(e) => setTaxPercent(e.target.value)} />
            </Field>
          )}
          <Field label="Payment Notes (optional)">
            <Textarea rows={2} value={paymentNotes} onChange={(e) => setPaymentNotes(e.target.value)} />
          </Field>

          <div className="space-y-2 border-t border-border pt-3">
            <p className="text-sm font-semibold">Additional Settings</p>
            {[
              { label: "Allow Waitlist", checked: allowWaitlist, onChange: setAllowWaitlist },
              { label: "Allow Trial Session", checked: allowTrialSession, onChange: setAllowTrialSession },
              { label: "Auto Enroll to Next Batch", checked: autoEnrollNextBatch, onChange: setAutoEnrollNextBatch },
              { label: "Send Notifications", checked: sendNotifications, onChange: setSendNotifications },
              { label: "Visible in Online Booking", checked: visibleInBooking, onChange: setVisibleInBooking },
            ].map((s) => (
              <div key={s.label} className="flex items-center justify-between gap-3 rounded-lg border border-input px-3 py-2.5">
                <span className="text-sm">{s.label}</span>
                <ToggleSwitch checked={s.checked} onChange={s.onChange} label={s.label} onClass="bg-[#0B9B63]" />
              </div>
            ))}
            <div className="flex items-center justify-between gap-3 rounded-lg border border-input px-3 py-2.5">
              <span className="text-sm">Enrollment Deadline</span>
              <ToggleSwitch checked={enrollmentDeadlineEnabled} onChange={setEnrollmentDeadlineEnabled} label="Enrollment Deadline" onClass="bg-[#0B9B63]" />
            </div>
            {enrollmentDeadlineEnabled && <Input type="date" value={enrollmentDeadline} onChange={(e) => setEnrollmentDeadline(e.target.value)} />}
          </div>
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" disabled={busy} onClick={onClose}>
            Cancel
          </Button>
          <Button disabled={busy} onClick={() => void save()}>
            {busy ? "Saving…" : "Save"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** Real total sessions — sessions per week × the weeks the program runs — falling back to the
 *  legacy `sessionCount` ("sessions per package") field only when that can't be computed. */
function durationWeeksLabel(p: ProgramDetail): string {
  if (!p.startDate || !p.endDate) return "—";
  const weeks = Math.max(1, Math.round((new Date(p.endDate).getTime() - new Date(p.startDate).getTime()) / (7 * 86_400_000)));
  return `${weeks} Weeks`;
}

function totalSessions(p: ProgramDetail): string {
  if (p.sessionsPerWeek && p.startDate && p.endDate) {
    const weeks = Math.max(1, Math.round((new Date(p.endDate).getTime() - new Date(p.startDate).getTime()) / (7 * 86_400_000)));
    return String(p.sessionsPerWeek * weeks);
  }
  return p.sessionCount != null ? String(p.sessionCount) : "—";
}

function Back() {
  return (
    <Link href="/coaching/programs" className="text-sm text-muted-foreground hover:underline">
      ← Back to programs
    </Link>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between gap-4 border-b border-border/60 py-1.5 last:border-0">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="font-medium">{value}</dd>
    </div>
  );
}

function IconRow({ icon: Icon, label, value }: { icon: typeof Users; label: string; value: string }) {
  return (
    <div className="flex items-center justify-between gap-4 border-b border-border/60 py-1.5 last:border-0">
      <dt className="flex items-center gap-1.5 text-muted-foreground">
        <Icon className="h-3.5 w-3.5 shrink-0" aria-hidden />
        {label}
      </dt>
      <dd className="font-medium">{value}</dd>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <Card className="p-3">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="mt-0.5 text-lg font-semibold tabular-nums">{value}</p>
    </Card>
  );
}

const DAY_ABBR = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label>{label}</Label>
      {children}
    </div>
  );
}
