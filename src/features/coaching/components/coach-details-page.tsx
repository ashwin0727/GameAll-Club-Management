"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
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
import { ServiceError } from "@/services/shared/service-error";
import { getCoachingService } from "@/services/coaching";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { CoachAvailabilityWindow, CoachDetail, CoachStatus } from "@/features/coaching/types";
import {
  DAY_LABELS,
  ErrorState,
  PageHeader,
  TableSkeleton,
  Tabs,
  coachStatusBadge,
  enrollmentStatusBadge,
  fmtDate,
  fmtDateTime,
  initials,
  minorToRupees,
  money,
  rupeesToMinor,
  sessionStatusBadge,
} from "@/features/coaching/components/shared";

const TABS = ["Overview", "Schedule", "Programs", "Students", "Availability"] as const;

export function CoachDetailsPage({ coachId }: { coachId: string }) {
  const perms = usePermissionContext();
  const [tab, setTab] = useState<(typeof TABS)[number]>("Overview");
  const [coach, setCoach] = useState<CoachDetail | null>(null);
  const [state, setState] = useState<"loading" | "ready" | "error">("loading");
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);

  const load = useCallback(async () => {
    setState("loading");
    setError(null);
    try {
      setCoach(await getCoachingService().getCoach(coachId));
      setState("ready");
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to load this coach.");
      setState("error");
    }
  }, [coachId]);

  useEffect(() => {
    void load();
  }, [load]);

  const canManage = perms?.can("COACHING_MANAGE_COACHES") ?? false;

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
  if (state === "loading" || !coach) {
    return (
      <div className="space-y-4">
        <Back />
        <Card className="p-0">
          <TableSkeleton rows={6} />
        </Card>
      </div>
    );
  }

  const c = coach;

  return (
    <div className="space-y-4">
      <Back />
      <PageHeader
        title="Coach Details"
        action={
          canManage && (
            <Button size="sm" onClick={() => setEditing(true)}>
              Edit
            </Button>
          )
        }
      />

      <Card className="p-4">
        <div className="flex flex-wrap items-center gap-4">
          <Avatar className="h-16 w-16">
            {c.avatarUrl && <AvatarImage src={c.avatarUrl} alt="" />}
            <AvatarFallback>{initials(c.fullName)}</AvatarFallback>
          </Avatar>
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <h2 className="text-lg font-semibold">{c.fullName}</h2>
              {coachStatusBadge(c.status)}
            </div>
            <p className="text-sm text-muted-foreground">{c.title ?? "Coach"}</p>
            <p className="mt-1 text-sm text-muted-foreground">
              {c.email ?? "—"}
              {c.phone ? ` · ${c.phone}` : ""}
            </p>
            {c.bio && <p className="mt-2 max-w-prose text-sm text-muted-foreground">{c.bio}</p>}
          </div>
        </div>
      </Card>

      <Tabs tabs={TABS} active={tab} onChange={setTab} />

      {tab === "Overview" && (
        <div className="grid gap-4 lg:grid-cols-2">
          <Card className="p-4">
            <h3 className="text-sm font-semibold">About</h3>
            <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
              <Row label="Specialization" value={c.specialization ?? "—"} />
              <Row label="Experience" value={c.experienceYears != null ? `${c.experienceYears} years` : "—"} />
              <Row label="Certifications" value={c.certifications ?? "—"} />
              <Row label="Hourly rate" value={c.hourlyRateMinor != null ? `${money(c.hourlyRateMinor)} / hour` : "—"} />
              <Row label="Joined" value={fmtDate(c.joinedOn)} />
            </dl>
          </Card>
          <Card className="p-4">
            <h3 className="text-sm font-semibold">Stats (This Month)</h3>
            <div className="mt-3 grid grid-cols-3 gap-3 text-center">
              <Stat label="Sessions" value={String(c.stats.sessionsThisMonth)} />
              <Stat label="Students" value={String(c.stats.activeStudents)} />
              <Stat label="Programs" value={String(c.stats.programs)} />
            </div>
          </Card>
          <Card className="p-4 lg:col-span-2">
            <h3 className="text-sm font-semibold">Today&apos;s Schedule</h3>
            {c.todaySchedule.length === 0 ? (
              <p className="mt-3 text-sm text-muted-foreground">No sessions today.</p>
            ) : (
              <ul className="mt-3 divide-y divide-border">
                {c.todaySchedule.map((s) => (
                  <li key={s.id} className="flex items-center justify-between py-2 text-sm">
                    <Link href={`/coaching/sessions/${s.id}`} className="font-medium hover:underline">
                      {s.programName}
                    </Link>
                    <span className="text-muted-foreground">
                      {fmtDateTime(s.startAt)} · {s.courtName}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </div>
      )}

      {tab === "Schedule" && (
        <Card className="p-4">
          <h3 className="text-sm font-semibold">Today&apos;s Sessions</h3>
          {c.todaySchedule.length === 0 ? (
            <p className="mt-3 text-sm text-muted-foreground">No sessions today.</p>
          ) : (
            <ul className="mt-3 divide-y divide-border">
              {c.todaySchedule.map((s) => (
                <li key={s.id} className="flex items-center justify-between py-2 text-sm">
                  <span>
                    <Link href={`/coaching/sessions/${s.id}`} className="font-medium hover:underline">
                      {s.programName}
                    </Link>
                    <span className="block text-xs text-muted-foreground">
                      {fmtDateTime(s.startAt)} · {s.courtName}
                    </span>
                  </span>
                  {sessionStatusBadge(s.status)}
                </li>
              ))}
            </ul>
          )}
          <p className="mt-3 text-xs text-muted-foreground">
            The full calendar is on the <Link href="/coaching/schedule" className="text-primary hover:underline">Schedule</Link> page.
          </p>
        </Card>
      )}

      {tab === "Programs" && (
        <Card className="p-0">
          {c.programs.length === 0 ? (
            <div className="p-10 text-center text-sm text-muted-foreground">This coach has no programs yet.</div>
          ) : (
            <ul className="divide-y divide-border">
              {c.programs.map((p) => (
                <li key={p.id} className="flex items-center justify-between p-3 text-sm">
                  <Link href={`/coaching/programs/${p.id}`} className="font-medium hover:underline">
                    {p.name}
                  </Link>
                  <span className="text-muted-foreground">{p.level}</span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      )}

      {tab === "Students" && (
        <Card className="p-0">
          {c.students.length === 0 ? (
            <div className="p-10 text-center text-sm text-muted-foreground">No active students.</div>
          ) : (
            <ul className="divide-y divide-border">
              {c.students.map((s) => (
                <li key={s.enrollmentId} className="flex items-center justify-between p-3 text-sm">
                  <Link href={`/coaching/enrollments/${s.enrollmentId}`} className="font-medium hover:underline">
                    {s.name}
                  </Link>
                  <span className="flex items-center gap-2 text-muted-foreground">
                    {s.programName}
                    {enrollmentStatusBadge(s.status)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      )}

      {tab === "Availability" && (
        <AvailabilityTab coach={c} canManage={canManage} onSaved={() => void load()} />
      )}

      {editing && (
        <EditCoachDialog coach={c} onClose={() => setEditing(false)} onSaved={() => { setEditing(false); void load(); }} />
      )}
    </div>
  );
}

function AvailabilityTab({
  coach,
  canManage,
  onSaved,
}: {
  coach: CoachDetail;
  canManage: boolean;
  onSaved: () => void;
}) {
  const [windows, setWindows] = useState<CoachAvailabilityWindow[]>(coach.availability);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [dirty, setDirty] = useState(false);

  function set(next: CoachAvailabilityWindow[]) {
    setWindows(next);
    setDirty(true);
  }

  async function save() {
    setBusy(true);
    setError(null);
    try {
      for (const w of windows) {
        if (w.endTime <= w.startTime) {
          setError("Every window's end time must be after its start time.");
          setBusy(false);
          return;
        }
      }
      await getCoachingService().setCoachAvailability(coach.id, windows);
      setDirty(false);
      onSaved();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not save availability.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card className="p-4">
      <h3 className="text-sm font-semibold">Recurring Weekly Availability</h3>
      <p className="text-xs text-muted-foreground">
        Sessions can only be scheduled inside these windows, in the facility&apos;s timezone.
      </p>

      <div className="mt-3 space-y-2">
        {windows.length === 0 && <p className="text-sm text-muted-foreground">No availability set.</p>}
        {windows.map((w, i) => (
          <div key={i} className="flex flex-wrap items-center gap-2">
            <Select
              value={String(w.dayOfWeek)}
              onValueChange={(v) => set(windows.map((x, j) => (j === i ? { ...x, dayOfWeek: Number(v) } : x)))}
            >
              <SelectTrigger className="w-[7rem]">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {DAY_LABELS.map((d, di) => (
                  <SelectItem key={di} value={String(di)}>
                    {d}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Input
              type="time"
              className="w-[8rem]"
              value={w.startTime.slice(0, 5)}
              onChange={(e) => set(windows.map((x, j) => (j === i ? { ...x, startTime: e.target.value } : x)))}
            />
            <span className="text-muted-foreground">–</span>
            <Input
              type="time"
              className="w-[8rem]"
              value={w.endTime.slice(0, 5)}
              onChange={(e) => set(windows.map((x, j) => (j === i ? { ...x, endTime: e.target.value } : x)))}
            />
            {canManage && (
              <Button variant="ghost" size="sm" onClick={() => set(windows.filter((_, j) => j !== i))}>
                Remove
              </Button>
            )}
          </div>
        ))}
      </div>

      {canManage && (
        <div className="mt-3 flex flex-wrap gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => set([...windows, { dayOfWeek: 1, startTime: "16:00", endTime: "20:00" }])}
          >
            Add window
          </Button>
          <Button size="sm" disabled={busy || !dirty} onClick={() => void save()}>
            {busy ? "Saving…" : "Save availability"}
          </Button>
        </div>
      )}

      {error && <p className="mt-2 text-sm text-destructive">{error}</p>}

      {coach.availabilityExceptions.length > 0 && (
        <div className="mt-6">
          <h4 className="text-sm font-semibold">Upcoming Exceptions</h4>
          <ul className="mt-2 divide-y divide-border text-sm">
            {coach.availabilityExceptions.map((ex) => (
              <li key={ex.id} className="flex items-center justify-between py-2">
                <span>
                  {fmtDate(ex.date)} —{" "}
                  {ex.isAvailable ? `available ${ex.startTime?.slice(0, 5)}–${ex.endTime?.slice(0, 5)}` : "unavailable"}
                </span>
                <span className="text-muted-foreground">{ex.reason ?? ""}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </Card>
  );
}

function EditCoachDialog({
  coach,
  onClose,
  onSaved,
}: {
  coach: CoachDetail;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [specialization, setSpecialization] = useState(coach.specialization ?? "");
  const [experience, setExperience] = useState(coach.experienceYears != null ? String(coach.experienceYears) : "");
  const [certifications, setCertifications] = useState(coach.certifications ?? "");
  const [bio, setBio] = useState(coach.bio ?? "");
  const [hourlyRate, setHourlyRate] = useState(minorToRupees(coach.hourlyRateMinor));
  const [status, setStatus] = useState<CoachStatus>(coach.status);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save() {
    setBusy(true);
    setError(null);
    try {
      await getCoachingService().updateCoach(coach.id, {
        specialization: specialization.trim() || null,
        experienceYears: experience.trim() ? Number(experience) : null,
        certifications: certifications.trim() || null,
        bio: bio.trim() || null,
        hourlyRateMinor: hourlyRate.trim() ? rupeesToMinor(hourlyRate) : null,
        status,
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
          <DialogTitle>Edit coach</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <F label="Specialization">
            <Input value={specialization} onChange={(e) => setSpecialization(e.target.value)} />
          </F>
          <div className="grid grid-cols-2 gap-3">
            <F label="Experience (years)">
              <Input type="number" min="0" step="0.5" value={experience} onChange={(e) => setExperience(e.target.value)} />
            </F>
            <F label="Hourly rate (₹)">
              <Input type="number" min="0" step="1" value={hourlyRate} onChange={(e) => setHourlyRate(e.target.value)} />
            </F>
          </div>
          <F label="Certifications">
            <Input value={certifications} onChange={(e) => setCertifications(e.target.value)} />
          </F>
          <F label="Bio">
            <Textarea rows={3} value={bio} onChange={(e) => setBio(e.target.value)} />
          </F>
          <F label="Status">
            <Select value={status} onValueChange={(v) => setStatus(v as CoachStatus)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="ACTIVE">Active</SelectItem>
                <SelectItem value="ON_LEAVE">On Leave</SelectItem>
                <SelectItem value="INACTIVE">Inactive</SelectItem>
              </SelectContent>
            </Select>
          </F>
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

function Back() {
  return (
    <Link href="/coaching/coaches" className="text-sm text-muted-foreground hover:underline">
      ← Back to coaches
    </Link>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <>
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="font-medium">{value}</dd>
    </>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border border-border p-3">
      <p className="text-lg font-semibold tabular-nums">{value}</p>
      <p className="text-xs text-muted-foreground">{label}</p>
    </div>
  );
}

function F({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label>{label}</Label>
      {children}
    </div>
  );
}
