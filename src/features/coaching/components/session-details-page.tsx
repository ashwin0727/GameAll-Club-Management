"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
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
import { getCourtOptions, type CourtOption } from "@/features/maintenance/court-options";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { CoachOption, EnrollmentRow, SessionDetail } from "@/features/coaching/types";
import {
  ErrorState,
  PROGRESS_LABEL,
  PageHeader,
  TableSkeleton,
  Tabs,
  fmtDateTime,
  isoToLocal,
  progressBadge,
  sessionStatusBadge,
} from "@/features/coaching/components/shared";

const TABS = ["Students", "Session Notes", "Progress", "Activity"] as const;

export function SessionDetailsPage({ sessionId }: { sessionId: string }) {
  const perms = usePermissionContext();
  const [tab, setTab] = useState<(typeof TABS)[number]>("Students");
  const [session, setSession] = useState<SessionDetail | null>(null);
  const [state, setState] = useState<"loading" | "ready" | "error">("loading");
  const [error, setError] = useState<string | null>(null);
  const [dialog, setDialog] = useState<"reschedule" | "cancel" | "complete" | "add-student" | null>(null);
  const [progressFor, setProgressFor] = useState<{ enrollmentId: string; name: string } | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setState("loading");
    setError(null);
    try {
      setSession(await getCoachingService().getSession(sessionId));
      setState("ready");
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to load this session.");
      setState("error");
    }
  }, [sessionId]);

  useEffect(() => {
    void load();
  }, [load]);

  async function run(fn: () => Promise<void>) {
    setBusy(true);
    setError(null);
    try {
      await fn();
      await load();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not complete that action.");
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
  if (state === "loading" || !session) {
    return (
      <div className="space-y-4">
        <Back />
        <Card className="p-0">
          <TableSkeleton rows={6} />
        </Card>
      </div>
    );
  }

  const s = session;
  const canEdit = perms?.can("COACHING_EDIT_SESSION") ?? false;
  const canCancel = perms?.can("COACHING_CANCEL_SESSION") ?? false;
  const canProgress = perms?.can("COACHING_MANAGE_PROGRESS") ?? false;
  const canViewProgress = perms?.can("COACHING_VIEW_PROGRESS") ?? false;
  const live = s.status === "SCHEDULED" || s.status === "CONFIRMED";

  return (
    <div className="space-y-4">
      <Back />
      <PageHeader
        title="Session Details"
        subtitle={`${s.programName} · ${fmtDateTime(s.startAt)}`}
        action={
          <div className="flex flex-wrap gap-2">
            {canEdit && s.status === "SCHEDULED" && (
              <Button size="sm" variant="outline" disabled={busy} onClick={() => run(() => getCoachingService().setSessionStatus(s.id, "CONFIRMED"))}>
                Confirm
              </Button>
            )}
            {canEdit && live && (
              <Button size="sm" variant="outline" disabled={busy} onClick={() => run(() => getCoachingService().setSessionStatus(s.id, "IN_PROGRESS"))}>
                Start
              </Button>
            )}
            {canEdit && (live || s.status === "IN_PROGRESS") && (
              <Button size="sm" onClick={() => setDialog("complete")}>
                Complete
              </Button>
            )}
            {canEdit && live && (
              <Button size="sm" variant="outline" onClick={() => setDialog("reschedule")}>
                Edit
              </Button>
            )}
            {canCancel && s.status !== "COMPLETED" && s.status !== "CANCELLED" && (
              <Button size="sm" variant="outline" onClick={() => setDialog("cancel")}>
                Cancel
              </Button>
            )}
          </div>
        }
      />

      <Card className="p-4">
        <div className="flex flex-wrap items-center gap-2">
          {sessionStatusBadge(s.status)}
          {s.status === "CANCELLED" && s.cancelReason && (
            <span className="text-sm text-muted-foreground">Cancelled: {s.cancelReason}</span>
          )}
        </div>
        <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2 text-sm md:grid-cols-3">
          <Row label="Program" value={`${s.programName} (${s.programLevel})`} />
          <Row label="Coach" value={s.coachName} />
          <Row label="Court" value={s.courtName} />
          <Row label="Time" value={fmtDateTime(s.startAt)} />
          <Row label="Capacity" value={`${s.enrolledCount} / ${s.capacity}`} />
          {s.objective && <Row label="Objective" value={s.objective} />}
        </dl>
      </Card>

      <Tabs tabs={TABS} active={tab} onChange={setTab} />

      {tab === "Students" && (
        <Card className="p-0">
          <div className="flex items-center justify-between p-4">
            <h3 className="text-sm font-semibold">
              Students ({s.enrolledCount}/{s.capacity})
            </h3>
            {canEdit && live && s.enrolledCount < s.capacity && (
              <Button size="sm" variant="outline" onClick={() => setDialog("add-student")}>
                Add student
              </Button>
            )}
          </div>
          {s.students.length === 0 ? (
            <div className="p-10 text-center text-sm text-muted-foreground">No students on the roster.</div>
          ) : (
            <ul className="divide-y divide-border">
              {s.students.map((st) => (
                <li key={st.enrollmentId} className="flex items-center justify-between p-3 text-sm">
                  <Link href={`/coaching/enrollments/${st.enrollmentId}`} className="font-medium hover:underline">
                    {st.name}
                  </Link>
                  <div className="flex items-center gap-2">
                    {canProgress && (
                      <Button size="sm" variant="ghost" onClick={() => setProgressFor({ enrollmentId: st.enrollmentId, name: st.name })}>
                        Add progress note
                      </Button>
                    )}
                    {canEdit && live && (
                      <Button
                        size="sm"
                        variant="ghost"
                        disabled={busy}
                        onClick={() => run(() => getCoachingService().removeSessionStudent(s.id, st.enrollmentId))}
                      >
                        Remove
                      </Button>
                    )}
                  </div>
                </li>
              ))}
            </ul>
          )}
        </Card>
      )}

      {tab === "Session Notes" && (
        <Card className="p-4 text-sm">
          {s.notes ? <p className="whitespace-pre-wrap">{s.notes}</p> : <p className="text-muted-foreground">No session notes yet.</p>}
          {s.objectiveResult && (
            <div className="mt-3">
              <p className="text-xs font-semibold text-muted-foreground">Objective result</p>
              <p className="whitespace-pre-wrap">{s.objectiveResult}</p>
            </div>
          )}
        </Card>
      )}

      {tab === "Progress" && (
        <Card className="p-0">
          {!canViewProgress ? (
            <div className="p-10 text-center text-sm text-muted-foreground">
              You don&apos;t have permission to view student progress.
            </div>
          ) : !s.progressNotes || s.progressNotes.length === 0 ? (
            <div className="p-10 text-center text-sm text-muted-foreground">No progress notes for this session.</div>
          ) : (
            <ul className="divide-y divide-border">
              {s.progressNotes.map((n) => (
                <li key={n.id} className="p-3 text-sm">
                  <div className="flex items-center justify-between">
                    <span className="font-medium">{n.memberName}</span>
                    {progressBadge(n.progressStatus)}
                  </div>
                  {n.skillOrGoal && <p className="text-xs text-muted-foreground">{n.skillOrGoal}</p>}
                  <p className="mt-1">{n.note}</p>
                </li>
              ))}
            </ul>
          )}
        </Card>
      )}

      {tab === "Activity" && (
        <Card className="p-0">
          {s.events.length === 0 ? (
            <div className="p-10 text-center text-sm text-muted-foreground">Nothing recorded yet.</div>
          ) : (
            <ul className="divide-y divide-border text-sm">
              {s.events.map((e) => (
                <li key={e.id} className="flex items-center justify-between p-3">
                  <span>{e.summary}</span>
                  <span className="text-muted-foreground">
                    {e.actorName ? `${e.actorName} · ` : ""}
                    {fmtDateTime(e.createdAt)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      )}

      {dialog === "reschedule" && (
        <RescheduleDialog session={s} onClose={() => setDialog(null)} onDone={() => { setDialog(null); void load(); }} />
      )}
      {dialog === "cancel" && (
        <CancelDialog sessionId={s.id} onClose={() => setDialog(null)} onDone={() => { setDialog(null); void load(); }} />
      )}
      {dialog === "complete" && (
        <CompleteDialog sessionId={s.id} onClose={() => setDialog(null)} onDone={() => { setDialog(null); void load(); }} />
      )}
      {dialog === "add-student" && (
        <AddStudentDialog session={s} onClose={() => setDialog(null)} onDone={() => { setDialog(null); void load(); }} />
      )}
      {progressFor && (
        <ProgressDialog
          sessionId={s.id}
          enrollmentId={progressFor.enrollmentId}
          studentName={progressFor.name}
          onClose={() => setProgressFor(null)}
          onDone={() => { setProgressFor(null); void load(); }}
        />
      )}
    </div>
  );
}

function RescheduleDialog({
  session,
  onClose,
  onDone,
}: {
  session: SessionDetail;
  onClose: () => void;
  onDone: () => void;
}) {
  const perms = usePermissionContext();
  const [coachId, setCoachId] = useState(session.coachId);
  const [courtId, setCourtId] = useState(session.courtId);
  const [start, setStart] = useState(isoToLocal(session.startAt));
  const [end, setEnd] = useState(isoToLocal(session.endAt));
  const [capacity, setCapacity] = useState(String(session.capacity));
  const [coaches, setCoaches] = useState<CoachOption[]>([]);
  const [courts, setCourts] = useState<CourtOption[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const fid = perms?.facilityId;
    if (!fid) return;
    getCoachingService().listCoachOptions(fid).then(setCoaches).catch(() => setCoaches([]));
    getCourtOptions(fid).then(setCourts).catch(() => setCourts([]));
  }, [perms?.facilityId]);

  async function save() {
    setBusy(true);
    setError(null);
    try {
      await getCoachingService().rescheduleSession({
        sessionId: session.id,
        coachId,
        courtId,
        startAt: new Date(start).toISOString(),
        endAt: new Date(end).toISOString(),
        capacity: Number(capacity) || session.capacity,
      });
      onDone();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not reschedule.");
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(v) => !v && !busy && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Edit session</DialogTitle>
          <DialogDescription>Every change is re-checked against courts, coaches and maintenance.</DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <Field label="Coach">
            <Select value={coachId} onValueChange={setCoachId}>
              <SelectTrigger>
                <SelectValue />
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
          <Field label="Court">
            <Select value={courtId} onValueChange={setCourtId}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {courts.map((c) => (
                  <SelectItem key={c.id} value={c.id}>
                    {c.name} · {c.sportName}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Start">
              <Input type="datetime-local" value={start} onChange={(e) => setStart(e.target.value)} />
            </Field>
            <Field label="End">
              <Input type="datetime-local" value={end} onChange={(e) => setEnd(e.target.value)} />
            </Field>
          </div>
          <Field label="Capacity">
            <Input type="number" min="1" step="1" value={capacity} onChange={(e) => setCapacity(e.target.value)} />
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

function CancelDialog({ sessionId, onClose, onDone }: { sessionId: string; onClose: () => void; onDone: () => void }) {
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    if (!reason.trim()) {
      setError("A reason is required.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await getCoachingService().cancelSession(sessionId, reason.trim());
      onDone();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not cancel the session.");
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(v) => !v && !busy && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Cancel session</DialogTitle>
          <DialogDescription>The session record is kept — its status becomes Cancelled.</DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <Field label="Reason">
            <Textarea rows={3} value={reason} onChange={(e) => setReason(e.target.value)} />
          </Field>
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" disabled={busy} onClick={onClose}>
            Keep session
          </Button>
          <Button variant="destructive" disabled={busy} onClick={() => void submit()}>
            {busy ? "Cancelling…" : "Cancel Session"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function CompleteDialog({ sessionId, onClose, onDone }: { sessionId: string; onClose: () => void; onDone: () => void }) {
  const [notes, setNotes] = useState("");
  const [result, setResult] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setBusy(true);
    setError(null);
    try {
      await getCoachingService().completeSession(sessionId, notes.trim() || null, result.trim() || null);
      onDone();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not complete the session.");
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(v) => !v && !busy && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Complete session</DialogTitle>
          <DialogDescription>
            Records completion and coach notes. Student attendance is not tracked.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <Field label="Session notes (optional)">
            <Textarea rows={3} value={notes} onChange={(e) => setNotes(e.target.value)} />
          </Field>
          <Field label="Objective result (optional)">
            <Textarea rows={2} value={result} onChange={(e) => setResult(e.target.value)} />
          </Field>
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" disabled={busy} onClick={onClose}>
            Cancel
          </Button>
          <Button disabled={busy} onClick={() => void submit()}>
            {busy ? "Saving…" : "Complete Session"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function AddStudentDialog({
  session,
  onClose,
  onDone,
}: {
  session: SessionDetail;
  onClose: () => void;
  onDone: () => void;
}) {
  const [candidates, setCandidates] = useState<EnrollmentRow[]>([]);
  const [enrollmentId, setEnrollmentId] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const onRoster = new Set(session.students.map((s) => s.enrollmentId));

  useEffect(() => {
    getCoachingService()
      .listEnrollments({
        facilityId: session.facilityId,
        filters: { programId: session.programId, status: "ACTIVE" },
        limit: 200,
      })
      .then((p) => setCandidates(p.enrollments.filter((e) => !onRoster.has(e.id))))
      .catch(() => setCandidates([]));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function submit() {
    if (!enrollmentId) {
      setError("Choose a student.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await getCoachingService().addSessionStudent(session.id, enrollmentId);
      onDone();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not add the student.");
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(v) => !v && !busy && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Add student</DialogTitle>
          <DialogDescription>Only active enrollments in this program can be added.</DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <Select value={enrollmentId} onValueChange={setEnrollmentId}>
            <SelectTrigger>
              <SelectValue placeholder={candidates.length ? "Select a student" : "No eligible students"} />
            </SelectTrigger>
            <SelectContent>
              {candidates.map((e) => (
                <SelectItem key={e.id} value={e.id}>
                  {e.studentName}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" disabled={busy} onClick={onClose}>
            Cancel
          </Button>
          <Button disabled={busy} onClick={() => void submit()}>
            {busy ? "Adding…" : "Add"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function ProgressDialog({
  sessionId,
  enrollmentId,
  studentName,
  onClose,
  onDone,
}: {
  sessionId: string;
  enrollmentId: string;
  studentName: string;
  onClose: () => void;
  onDone: () => void;
}) {
  const [skill, setSkill] = useState("");
  const [note, setNote] = useState("");
  const [status, setStatus] = useState("ON_TRACK");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    if (!note.trim()) {
      setError("Enter a progress note.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await getCoachingService().addProgressNote({
        enrollmentId,
        note: note.trim(),
        skillOrGoal: skill.trim() || null,
        progressStatus: status,
        sessionId,
      });
      onDone();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not save the note.");
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(v) => !v && !busy && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Progress note — {studentName}</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <Field label="Skill or goal (optional)">
            <Input value={skill} onChange={(e) => setSkill(e.target.value)} placeholder="e.g. Backhand consistency" />
          </Field>
          <Field label="Note">
            <Textarea rows={3} value={note} onChange={(e) => setNote(e.target.value)} />
          </Field>
          <Field label="Status">
            <Select value={status} onValueChange={setStatus}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {Object.entries(PROGRESS_LABEL).map(([k, v]) => (
                  <SelectItem key={k} value={k}>
                    {v}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Field>
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" disabled={busy} onClick={onClose}>
            Cancel
          </Button>
          <Button disabled={busy} onClick={() => void submit()}>
            {busy ? "Saving…" : "Save note"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function Back() {
  return (
    <Link href="/coaching/schedule" className="text-sm text-muted-foreground hover:underline">
      ← Back to schedule
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

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label>{label}</Label>
      {children}
    </div>
  );
}
