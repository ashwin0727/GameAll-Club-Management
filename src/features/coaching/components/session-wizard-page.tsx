"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ArrowLeft, BookOpen, CalendarPlus, ChevronRight, IndianRupee, MapPin, Star, Users } from "lucide-react";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { ToggleSwitch } from "@/features/bookings/components/toggle-switch";
import { TimeField } from "@/features/memberships/components/time-field";
import { formatClock12 } from "@/features/memberships/components/member-schedule-grid";
import { usePlayingAreasList } from "@/features/memberships/hooks/use-member-schedule";
import { courtsForSport } from "@/features/memberships/sport-scope";
import { useFacilitySportOptions } from "@/features/facility/hooks/use-facility-sport-options";
import { getPublicCourtAvailability } from "@/features/public-booking/public-booking";
import type { PublicBookingCourt } from "@/features/public-booking/types";
import { ServiceError } from "@/services/shared/service-error";
import { getCoachingService } from "@/services/coaching";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import { PermissionDenied } from "@/features/staff/components/permission-denied";
import { blurOnWheel, initials, money, NO_SPINNER_INPUT } from "@/features/coaching/components/shared";
import { SKILL_LEVELS } from "@/features/coaching/components/use-program-wizard-form";
import type { CoachRow, ProgramType } from "@/features/coaching/types";
import { cn } from "@/lib/utils";

const SESSION_TYPES: { value: ProgramType; label: string }[] = [
  { value: "GROUP", label: "Group Session" },
  { value: "ONE_ON_ONE", label: "Individual Session" },
  { value: "TRIAL", label: "Trial Session" },
];

function todayIso(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function addMinutes(time: string, minutes: number): string {
  const [h = 0, m = 0] = time.split(":").map(Number);
  const total = (h * 60 + m + minutes + 1440) % 1440;
  return `${String(Math.floor(total / 60)).padStart(2, "0")}:${String(total % 60).padStart(2, "0")}`;
}

function durationLabel(start: string, end: string): string {
  const [sh = 0, sm = 0] = start.split(":").map(Number);
  const [eh = 0, em = 0] = end.split(":").map(Number);
  const mins = eh * 60 + em - (sh * 60 + sm);
  if (mins <= 0) return "—";
  if (mins % 60 === 0) return `${mins / 60} Hour${mins === 60 ? "" : "s"}`;
  return `${mins} minutes`;
}

function fmtDate(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(y!, (m ?? 1) - 1, d ?? 1).toLocaleDateString("en-IN", { weekday: "long", day: "2-digit", month: "short", year: "numeric" });
}

function Field({ label, required, children }: { label: string; required?: boolean; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label>
        {label}
        {required && <span className="text-destructive"> *</span>}
      </Label>
      {children}
    </div>
  );
}

function StepNumber({ n }: { n: number }) {
  return <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-success text-sm font-semibold text-white">{n}</span>;
}

/**
 * Coach Scheduler's "Schedule Coaching Session" — a standalone, directly member-bookable coaching
 * session (no coaching program required), matching the reference design. Reuses the existing
 * conflict-checking session RPC (`create_coaching_session`, unchanged apart from the program
 * becoming optional) and the same court-availability engine the public booking flow already uses
 * (`get_public_court_availability`) — no new scheduling or availability system.
 */
export function SessionWizardPage() {
  const perms = usePermissionContext();
  const router = useRouter();
  const facilityId = perms?.facilityId ?? null;

  const [coaches, setCoaches] = useState<CoachRow[] | null>(null);
  const [coachId, setCoachId] = useState("");
  const sportsQuery = useFacilitySportOptions(facilityId ?? undefined);
  const areasQuery = usePlayingAreasList(facilityId);

  const [facilitySportId, setFacilitySportId] = useState("");
  const [sessionType, setSessionType] = useState<ProgramType>("GROUP");
  const [level, setLevel] = useState("Beginners");
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");

  const [date, setDate] = useState(todayIso());
  const [startTime, setStartTime] = useState("16:00");
  const [endTime, setEndTime] = useState("17:00");

  const [courtId, setCourtId] = useState("");
  const [maxStudents, setMaxStudents] = useState("8");
  const [pricePerStudent, setPricePerStudent] = useState("");

  const [visibleForBooking, setVisibleForBooking] = useState(true);
  const [sendNotification, setSendNotification] = useState(true);
  const [allowWaitlist, setAllowWaitlist] = useState(false);

  const [availability, setAvailability] = useState<PublicBookingCourt[] | null>(null);

  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!facilityId) return;
    getCoachingService()
      .listCoaches({ facilityId, filters: { status: "ACTIVE" }, limit: 100 })
      .then((page) => {
        setCoaches(page.coaches);
        setCoachId((cur) => cur || page.coaches[0]?.id || "");
      })
      .catch(() => setCoaches([]));
  }, [facilityId]);

  const courts = courtsForSport((areasQuery.data ?? []).filter((a) => a.status === "ACTIVE"), facilitySportId || null);

  // Default the sport to the first one offered, and the court to the first one for that sport,
  // once the reference data has actually loaded — mirrors the wizard's own smart-defaults pattern.
  useEffect(() => {
    if (!facilitySportId && sportsQuery.data?.length) setFacilitySportId(sportsQuery.data[0]!.facilitySportId);
  }, [sportsQuery.data, facilitySportId]);
  useEffect(() => {
    if (courts.length && !courts.some((c) => c.id === courtId)) setCourtId(courts[0]?.id ?? "");
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [facilitySportId, courts.length]);

  useEffect(() => {
    if (!facilityId || !facilitySportId || !date) return;
    let cancelled = false;
    getPublicCourtAvailability(facilityId, facilitySportId, date)
      .then((r) => !cancelled && setAvailability(r))
      .catch(() => !cancelled && setAvailability([]));
    return () => {
      cancelled = true;
    };
  }, [facilityId, facilitySportId, date]);

  const coach = coaches?.find((c) => c.id === coachId) ?? null;
  const court = courts.find((c) => c.id === courtId);
  const courtSlots = availability?.find((c) => c.courtId === courtId)?.slots ?? [];
  const matchedSlot = courtSlots.find((s) => s.startTime.slice(0, 5) === startTime);

  if (!perms?.can("COACHING_CREATE_SESSION")) {
    return <PermissionDenied message="You don't have permission to create coaching sessions." />;
  }

  async function submit() {
    if (!facilityId) return;
    if (!coachId || !courtId || !facilitySportId || !title.trim()) {
      setError("Choose a coach, sport, court and enter a title.");
      return;
    }
    const startAt = new Date(`${date}T${startTime}`);
    const endAt = new Date(`${date}T${endTime}`);
    if (endAt <= startAt) {
      setError("End time must be after start time.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await getCoachingService().createSession({
        facilityId,
        coachId,
        courtId,
        startAt: startAt.toISOString(),
        endAt: endAt.toISOString(),
        capacity: maxStudents.trim() ? Number(maxStudents) : null,
        title: title.trim(),
        description: description.trim() || null,
        level,
        facilitySportId,
        sessionType,
        pricePerStudentMinor: pricePerStudent.trim() ? Math.round(Number(pricePerStudent) * 100) : null,
        visibleForBooking,
        sendNotification,
        allowWaitlist,
      });
      // A successfully scheduled session lands the owner back on the Coaching Overview, not this
      // form or the session's own details page — the explicit "on success, go to Overview" flow.
      router.push("/coaching");
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not schedule the session.");
      setBusy(false);
    }
  }

  const sportName = sportsQuery.data?.find((s) => s.facilitySportId === facilitySportId)?.name;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
            <Link href="/dashboard" className="hover:text-foreground">
              Home
            </Link>
            <ChevronRight className="h-3.5 w-3.5" aria-hidden />
            <Link href="/coaching" className="hover:text-foreground">
              Coaching
            </Link>
            <ChevronRight className="h-3.5 w-3.5" aria-hidden />
            <span className="font-medium text-foreground">Schedule Session</span>
          </nav>
          <h1 className="mt-1 text-2xl font-bold">Schedule Coaching Session</h1>
          <p className="text-sm text-muted-foreground">Create a new coaching session for a coach. This session will be visible to members for booking.</p>
        </div>
        <Link href="/coaching/coaches" className="flex h-10 shrink-0 items-center gap-2 rounded-lg border border-input px-4 text-sm font-medium hover:bg-accent">
          <ArrowLeft className="h-4 w-4" aria-hidden />
          Back to Coaches
        </Link>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1fr_360px]">
        <div className="space-y-4">
          <section className="space-y-3 rounded-xl border border-border bg-card p-5">
            <div className="flex items-center gap-2.5">
              <StepNumber n={1} />
              <div>
                <h2 className="font-bold">Select Coach</h2>
                <p className="text-xs text-muted-foreground">Choose a coach for this session.</p>
              </div>
            </div>
            <Select value={coachId} onValueChange={setCoachId}>
              <SelectTrigger className="h-auto py-2">
                {coach ? (
                  <div className="flex items-center gap-3 text-left">
                    <Avatar className="h-9 w-9">
                      <AvatarImage src={coach.avatarUrl ?? undefined} alt="" />
                      <AvatarFallback>{initials(coach.fullName)}</AvatarFallback>
                    </Avatar>
                    <div className="min-w-0">
                      <p className="font-semibold">{coach.fullName}</p>
                      <p className="flex items-center gap-1 text-xs text-muted-foreground">
                        {coach.rating != null && (
                          <span className="flex items-center gap-0.5">
                            <Star className="h-3 w-3 fill-warning text-warning" aria-hidden /> {coach.rating.toFixed(1)}
                          </span>
                        )}
                        {coach.experienceYears != null && <span>{coach.rating != null ? " | " : ""}{coach.experienceYears} yrs exp</span>}
                      </p>
                    </div>
                  </div>
                ) : (
                  <SelectValue placeholder={coaches === null ? "Loading coaches…" : "Select a coach"} />
                )}
              </SelectTrigger>
              <SelectContent>
                {(coaches ?? []).map((c) => (
                  <SelectItem key={c.id} value={c.id}>
                    {c.fullName}
                    {c.rating != null ? ` — ${c.rating.toFixed(1)}★` : ""}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </section>

          <section className="space-y-3 rounded-xl border border-border bg-card p-5">
            <div className="flex items-center gap-2.5">
              <StepNumber n={2} />
              <div>
                <h2 className="font-bold">Session Details</h2>
                <p className="text-xs text-muted-foreground">Set the sport, session type and other details.</p>
              </div>
            </div>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
              <Field label="Sport" required>
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
              <Field label="Session Type" required>
                <Select value={sessionType} onValueChange={(v) => setSessionType(v as ProgramType)}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {SESSION_TYPES.map((t) => (
                      <SelectItem key={t.value} value={t.value}>
                        {t.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </Field>
              <Field label="Level" required>
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
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <Field label="Title" required>
                <Input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="e.g. Beginner Badminton Coaching" />
              </Field>
              <Field label="Description (Optional)">
                <Textarea rows={2} maxLength={500} value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Learn basic strokes, footwork and game techniques…" />
                <p className="text-right text-xs text-muted-foreground">{description.length}/500</p>
              </Field>
            </div>
          </section>

          <section className="space-y-3 rounded-xl border border-border bg-card p-5">
            <div className="flex items-center gap-2.5">
              <StepNumber n={3} />
              <div>
                <h2 className="font-bold">Date &amp; Time</h2>
                <p className="text-xs text-muted-foreground">Select the date, time and duration for this session.</p>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
              <Field label="Date" required>
                <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
              </Field>
              <Field label="Start Time" required>
                <TimeField ariaLabel="Start time" value={startTime} onChange={(v) => { setStartTime(v); setEndTime(addMinutes(v, 60)); }} />
              </Field>
              <Field label="End Time" required>
                <TimeField ariaLabel="End time" value={endTime} onChange={setEndTime} />
              </Field>
              <Field label="Duration">
                <Input value={durationLabel(startTime, endTime)} disabled />
              </Field>
            </div>
            {matchedSlot && (
              <p className={cn("rounded-lg px-3 py-2 text-xs", matchedSlot.available ? "bg-success/10 text-success" : "bg-destructive/10 text-destructive")}>
                {matchedSlot.available
                  ? "This time slot is within facility operating hours."
                  : `${court?.name ?? "This court"} is unavailable from ${formatClock12(startTime)} to ${formatClock12(endTime)}.`}
              </p>
            )}
          </section>

          <section className="space-y-3 rounded-xl border border-border bg-card p-5">
            <div className="flex items-center gap-2.5">
              <StepNumber n={4} />
              <div>
                <h2 className="font-bold">Location &amp; Capacity</h2>
                <p className="text-xs text-muted-foreground">Choose the court and set the capacity for this session.</p>
              </div>
            </div>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
              <Field label="Court" required>
                <Select value={courtId} onValueChange={setCourtId}>
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
              <Field label="Max Students" required>
                <Input type="number" min="1" step="1" onWheel={blurOnWheel} className={NO_SPINNER_INPUT} value={maxStudents} onChange={(e) => setMaxStudents(e.target.value)} />
                <p className="text-xs text-muted-foreground">Maximum 20 students</p>
              </Field>
              <Field label="Price per Student (Optional)">
                <Input type="number" min="0" onWheel={blurOnWheel} className={NO_SPINNER_INPUT} value={pricePerStudent} onChange={(e) => setPricePerStudent(e.target.value)} placeholder="0" />
                <p className="text-xs text-muted-foreground">Leave empty if it&apos;s a free session</p>
              </Field>
            </div>
          </section>

          <section className="space-y-3 rounded-xl border border-border bg-card p-5">
            <div className="flex items-center gap-2.5">
              <StepNumber n={5} />
              <div>
                <h2 className="font-bold">Additional Settings</h2>
                <p className="text-xs text-muted-foreground">Set visibility and other preferences.</p>
              </div>
            </div>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
              <div className="flex items-center justify-between gap-3 rounded-lg border border-input p-3">
                <div>
                  <p className="text-sm font-medium">Make Visible for Booking</p>
                  <p className="text-xs text-muted-foreground">Members can book this session</p>
                </div>
                <ToggleSwitch checked={visibleForBooking} onChange={setVisibleForBooking} label="Make Visible for Booking" onClass="bg-[#0B9B63]" />
              </div>
              <div className="flex items-center justify-between gap-3 rounded-lg border border-input p-3">
                <div>
                  <p className="text-sm font-medium">Send Notification</p>
                  <p className="text-xs text-muted-foreground">Notify members about this session</p>
                </div>
                <ToggleSwitch checked={sendNotification} onChange={setSendNotification} label="Send Notification" onClass="bg-[#0B9B63]" />
              </div>
              <div className="flex items-center justify-between gap-3 rounded-lg border border-input p-3">
                <div>
                  <p className="text-sm font-medium">Allow Waitlist</p>
                  <p className="text-xs text-muted-foreground">Allow members to join waitlist if full</p>
                </div>
                <ToggleSwitch checked={allowWaitlist} onChange={setAllowWaitlist} label="Allow Waitlist" onClass="bg-[#0B9B63]" />
              </div>
            </div>
          </section>

          {error && <p className="text-sm text-destructive">{error}</p>}

          <div className="flex items-center justify-between rounded-xl border border-border bg-card p-4">
            <Link href="/coaching/sessions" className="flex h-10 items-center rounded-lg border border-input px-5 text-sm font-medium hover:bg-accent">
              Cancel
            </Link>
            <button
              type="button"
              onClick={() => void submit()}
              disabled={busy}
              className="flex h-10 items-center gap-2 rounded-lg bg-[#0B7A55] px-5 text-sm font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-60"
            >
              <CalendarPlus className="h-4 w-4" aria-hidden />
              {busy ? "Scheduling…" : "Schedule Session"}
            </button>
          </div>
        </div>

        <div className="space-y-4">
          <div className="rounded-xl border border-border bg-card p-4">
            <h2 className="text-sm font-bold">Session Preview</h2>
            <p className="text-xs text-muted-foreground">Review how this session will appear to members.</p>
            <div className="relative mt-3 flex h-32 items-center justify-center rounded-lg bg-muted">
              <BookOpen className="h-8 w-8 text-muted-foreground" aria-hidden />
              <Badge className="absolute right-2 top-2" variant="secondary">
                {SESSION_TYPES.find((t) => t.value === sessionType)?.label}
              </Badge>
            </div>
            <p className="mt-3 font-semibold">{title.trim() || "Session Title"}</p>
            <div className="mt-2 flex items-center gap-2">
              <Avatar className="h-6 w-6">
                <AvatarImage src={coach?.avatarUrl ?? undefined} alt="" />
                <AvatarFallback className="text-[10px]">{coach ? initials(coach.fullName) : "?"}</AvatarFallback>
              </Avatar>
              <span className="text-sm">{coach?.fullName ?? "—"}</span>
              {coach?.rating != null && (
                <span className="flex items-center gap-0.5 text-xs text-muted-foreground">
                  <Star className="h-3 w-3 fill-warning text-warning" aria-hidden /> {coach.rating.toFixed(1)}
                </span>
              )}
            </div>
            <dl className="mt-3 space-y-1.5 text-xs text-muted-foreground">
              <Row icon={BookOpen} value={`${sportName ?? "—"} | ${level}`} />
              <Row icon={ChevronRight} value={fmtDate(date)} />
              <Row icon={ChevronRight} value={`${formatClock12(startTime)} - ${formatClock12(endTime)} (${durationLabel(startTime, endTime)})`} />
              <Row icon={MapPin} value={`${court?.name ?? "—"} · ${sportName ?? ""}`} />
              <Row icon={Users} value={`Max ${maxStudents || "—"} students`} />
              <Row icon={IndianRupee} value={pricePerStudent.trim() ? `${money(Math.round(Number(pricePerStudent) * 100))} per student` : "Free session"} />
            </dl>
            {description.trim() && <p className="mt-3 border-t border-border pt-3 text-xs text-muted-foreground">{description}</p>}
          </div>

          <div className="rounded-xl border border-border bg-card p-4">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-bold">Court Availability</h2>
              <Link href="/coaching/schedule" className="text-xs text-primary hover:underline">
                View Full Calendar →
              </Link>
            </div>
            <p className="mt-1 text-xs text-muted-foreground">{fmtDate(date)}</p>
            {!availability ? (
              <p className="mt-3 text-xs text-muted-foreground">Loading availability…</p>
            ) : courtSlots.length === 0 ? (
              <p className="mt-3 text-xs text-muted-foreground">No slots configured for this court on this date.</p>
            ) : (
              <div className="mt-3 grid grid-cols-2 gap-2">
                {courtSlots.map((s) => {
                  const key = s.startTime.slice(0, 5);
                  const selected = key === startTime;
                  return (
                    <button
                      key={key}
                      type="button"
                      disabled={!s.available && !selected}
                      onClick={() => {
                        setStartTime(key);
                        setEndTime(addMinutes(key, 60));
                      }}
                      className={cn(
                        "rounded-lg border px-2 py-2 text-center text-xs font-medium transition-colors",
                        selected
                          ? "border-success bg-success text-white"
                          : s.available
                            ? "border-success/30 bg-success/10 text-success hover:bg-success/20"
                            : "cursor-not-allowed border-input text-muted-foreground/60",
                      )}
                    >
                      {formatClock12(key)}
                      <span className="block text-[10px] font-normal opacity-80">{selected ? "Selected" : s.available ? "Available" : "Booked"}</span>
                    </button>
                  );
                })}
              </div>
            )}
            {matchedSlot && (
              <p className="mt-3 rounded-lg bg-blue-500/10 p-2.5 text-xs text-blue-700 dark:text-blue-300">
                {matchedSlot.available
                  ? `Selected time slot is available for ${court?.name ?? "this court"}.`
                  : `Selected time slot is not available for ${court?.name ?? "this court"}.`}
              </p>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function Row({ icon: Icon, value }: { icon: typeof Users; value: string }) {
  return (
    <div className="flex items-center gap-1.5">
      <Icon className="h-3.5 w-3.5 shrink-0" aria-hidden />
      <span>{value}</span>
    </div>
  );
}
