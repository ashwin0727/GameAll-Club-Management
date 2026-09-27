"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { Camera } from "lucide-react";
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
import { getStaffService } from "@/services/staff";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import { CoachAvailabilityEditor, validateAvailabilityWindows } from "@/features/coaching/components/coach-availability-editor";
import { AVATAR_ACCEPT, AVATAR_MAX_BYTES, DURATION_OPTIONS } from "@/features/coaching/components/use-add-coach-form";
import { useFacilitySportOptions } from "@/features/facility/hooks/use-facility-sport-options";
import { COACH_EXPERTISE_LEVELS, type CoachAvailabilityWindow, type CoachDetail, type CoachStatus } from "@/features/coaching/types";
import {
  Chip,
  ErrorState,
  PageHeader,
  TableSkeleton,
  Tabs,
  coachStatusBadge,
  enrollmentStatusBadge,
  fmtDate,
  fmtDateTime,
  initials,
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
            {/* Only what the Add Coach wizard actually collects — a field it never asks for
             *  (e.g. specialization, hourly rate) has nothing real to show and stays hidden
             *  rather than rendering as a permanent "—". */}
            <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
              {c.sports.length > 0 && <Row label="Sports" value={c.sports.map((s) => s.name).join(", ")} />}
              {c.expertiseLevels.length > 0 && <Row label="Expertise Level" value={c.expertiseLevels.join(", ")} />}
              {c.experienceYears != null && <Row label="Experience" value={`${c.experienceYears} years`} />}
              {c.defaultSessionDurationMinutes != null && <Row label="Default Session Duration" value={`${c.defaultSessionDurationMinutes} minutes`} />}
              {c.certifications && <Row label="Certifications" value={c.certifications} />}
              {c.dateOfBirth && <Row label="Date of Birth" value={fmtDate(c.dateOfBirth)} />}
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
    const validation = validateAvailabilityWindows(windows);
    if (validation) {
      setError(validation);
      setBusy(false);
      return;
    }
    try {
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

      <div className="mt-3">
        <CoachAvailabilityEditor windows={windows} onChange={set} readOnly={!canManage} />
      </div>

      {canManage && (
        <div className="mt-3 flex flex-wrap gap-2">
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

/** Mirrors the Add Coach wizard's own field set exactly — this dialog edits the same attributes
 *  it collects (sports, expertise, experience, session duration, certifications, bio, date of
 *  birth, status), not the old free-text specialization/hourly-rate fields that wizard dropped. */
function EditCoachDialog({
  coach,
  onClose,
  onSaved,
}: {
  coach: CoachDetail;
  onClose: () => void;
  onSaved: () => void;
}) {
  const perms = usePermissionContext();
  const sportsQuery = useFacilitySportOptions(perms?.facilityId ?? undefined);
  const avatarInputRef = useRef<HTMLInputElement>(null);

  const [fullName, setFullName] = useState(coach.fullName);
  const [phone, setPhone] = useState(coach.phone ?? "");
  const [avatarFile, setAvatarFile] = useState<File | null>(null);
  const [avatarPreview, setAvatarPreview] = useState<string | null>(coach.avatarUrl);
  const [avatarError, setAvatarError] = useState<string | null>(null);
  const [uploadingAvatar, setUploadingAvatar] = useState(false);

  const [sportIds, setSportIds] = useState<string[]>(coach.sports.map((s) => s.id));
  const [expertiseLevels, setExpertiseLevels] = useState<string[]>(coach.expertiseLevels);
  const [experience, setExperience] = useState(coach.experienceYears != null ? String(coach.experienceYears) : "");
  const isPreset = coach.defaultSessionDurationMinutes != null && DURATION_OPTIONS.some((d) => d.value === String(coach.defaultSessionDurationMinutes));
  const [duration, setDuration] = useState(coach.defaultSessionDurationMinutes == null ? "60" : isPreset ? String(coach.defaultSessionDurationMinutes) : "custom");
  const [customDuration, setCustomDuration] = useState(!isPreset && coach.defaultSessionDurationMinutes != null ? String(coach.defaultSessionDurationMinutes) : "");
  const [certifications, setCertifications] = useState(coach.certifications ?? "");
  const [bio, setBio] = useState(coach.bio ?? "");
  const [dateOfBirth, setDateOfBirth] = useState(coach.dateOfBirth ?? "");
  const [status, setStatus] = useState<CoachStatus>(coach.status);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function toggle(list: string[], setList: (v: string[]) => void, value: string) {
    setList(list.includes(value) ? list.filter((v) => v !== value) : [...list, value]);
  }

  function pickAvatar(file: File | undefined) {
    if (!file) return;
    setAvatarError(null);
    if (!AVATAR_ACCEPT.includes(file.type)) {
      setAvatarError("Please choose a JPG, PNG or WEBP image.");
      return;
    }
    if (file.size > AVATAR_MAX_BYTES) {
      setAvatarError("That photo is larger than 2MB.");
      return;
    }
    setAvatarFile(file);
    setAvatarPreview((prev) => {
      if (prev && prev.startsWith("blob:")) URL.revokeObjectURL(prev);
      return URL.createObjectURL(file);
    });
  }

  async function save() {
    if (!perms?.facilityId) return;
    setBusy(true);
    setError(null);
    try {
      let avatarUrl: string | null = null;
      if (avatarFile) {
        setUploadingAvatar(true);
        try {
          avatarUrl = await getStaffService().uploadAvatar(avatarFile);
        } finally {
          setUploadingAvatar(false);
        }
      }
      await getStaffService().updateProfile(perms.facilityId, coach.userId, {
        fullName: fullName.trim() || null,
        phone: phone.trim() || null,
        avatarUrl,
      });
      await getCoachingService().updateCoach(coach.id, {
        sportIds,
        expertiseLevels,
        experienceYears: experience.trim() ? Number(experience) : null,
        defaultSessionDurationMinutes: duration === "custom" ? Number(customDuration) || null : Number(duration),
        certifications: certifications.trim() || null,
        bio: bio.trim() || null,
        dateOfBirth: dateOfBirth.trim() || null,
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
          <div className="flex items-center gap-3">
            <Avatar className="h-14 w-14">
              {avatarPreview && <AvatarImage src={avatarPreview} alt="" />}
              <AvatarFallback>
                <Camera className="h-5 w-5 text-muted-foreground" aria-hidden />
              </AvatarFallback>
            </Avatar>
            <div>
              <input ref={avatarInputRef} type="file" accept={AVATAR_ACCEPT.join(",")} className="hidden" onChange={(e) => pickAvatar(e.target.files?.[0])} />
              <Button type="button" size="sm" variant="outline" onClick={() => avatarInputRef.current?.click()}>
                Change Photo
              </Button>
              <p className="mt-1 text-xs text-muted-foreground">JPG, PNG (Max 2MB)</p>
              {avatarError && <p className="mt-1 text-xs text-destructive">{avatarError}</p>}
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <F label="Full Name">
              <Input value={fullName} onChange={(e) => setFullName(e.target.value)} />
            </F>
            <F label="Phone">
              <Input value={phone} onChange={(e) => setPhone(e.target.value)} />
            </F>
          </div>
          <F label="Sports">
            <div className="flex flex-wrap gap-2">
              {(sportsQuery.data ?? []).map((s) => (
                <Chip key={s.facilitySportId} label={s.name} selected={sportIds.includes(s.facilitySportId)} onToggle={() => toggle(sportIds, setSportIds, s.facilitySportId)} />
              ))}
            </div>
          </F>
          <F label="Expertise Level">
            <div className="flex flex-wrap gap-2">
              {COACH_EXPERTISE_LEVELS.map((l) => (
                <Chip key={l} label={l} selected={expertiseLevels.includes(l)} onToggle={() => toggle(expertiseLevels, setExpertiseLevels, l)} />
              ))}
            </div>
          </F>
          <div className="grid grid-cols-2 gap-3">
            <F label="Experience (years)">
              <Input type="number" min="0" step="0.5" value={experience} onChange={(e) => setExperience(e.target.value)} />
            </F>
            <F label="Default Session Duration">
              <Select value={duration} onValueChange={setDuration}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {DURATION_OPTIONS.map((d) => (
                    <SelectItem key={d.value} value={d.value}>
                      {d.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {duration === "custom" && (
                <Input type="number" min="1" className="mt-2" placeholder="Minutes" value={customDuration} onChange={(e) => setCustomDuration(e.target.value)} />
              )}
            </F>
          </div>
          <F label="Certifications">
            <Input value={certifications} onChange={(e) => setCertifications(e.target.value)} />
          </F>
          <F label="Bio">
            <Textarea rows={3} value={bio} onChange={(e) => setBio(e.target.value)} />
          </F>
          <F label="Date of Birth">
            <Input type="date" value={dateOfBirth} onChange={(e) => setDateOfBirth(e.target.value)} />
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
            {busy ? (uploadingAvatar ? "Uploading photo…" : "Saving…") : "Save"}
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
