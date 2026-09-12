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
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { EnrollmentDetail } from "@/features/coaching/types";
import {
  ErrorState,
  PROGRESS_LABEL,
  PageHeader,
  TableSkeleton,
  Tabs,
  enrollmentStatusBadge,
  fmtDate,
  fmtDateTime,
  minorToRupees,
  money,
  progressBadge,
  rupeesToMinor,
  sessionStatusBadge,
} from "@/features/coaching/components/shared";

const TABS = ["Overview", "Sessions", "Payments", "Progress"] as const;

export function EnrollmentDetailsPage({ enrollmentId }: { enrollmentId: string }) {
  const perms = usePermissionContext();
  const [tab, setTab] = useState<(typeof TABS)[number]>("Overview");
  const [e, setE] = useState<EnrollmentDetail | null>(null);
  const [state, setState] = useState<"loading" | "ready" | "error">("loading");
  const [error, setError] = useState<string | null>(null);
  const [dialog, setDialog] = useState<"edit" | "cancel" | "progress" | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setState("loading");
    setError(null);
    try {
      setE(await getCoachingService().getEnrollment(enrollmentId));
      setState("ready");
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to load this enrollment.");
      setState("error");
    }
  }, [enrollmentId]);

  useEffect(() => {
    void load();
  }, [load]);

  async function setStatus(status: "ACTIVE" | "PAUSED" | "COMPLETED") {
    setBusy(true);
    try {
      await getCoachingService().setEnrollmentStatus(enrollmentId, status);
      await load();
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Could not update the enrollment.");
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
  if (state === "loading" || !e) {
    return (
      <div className="space-y-4">
        <Back />
        <Card className="p-0">
          <TableSkeleton rows={6} />
        </Card>
      </div>
    );
  }

  const canManage = perms?.can("COACHING_MANAGE_ENROLLMENTS") ?? false;
  const canProgress = perms?.can("COACHING_MANAGE_PROGRESS") ?? false;
  const canViewProgress = perms?.can("COACHING_VIEW_PROGRESS") ?? false;
  const canRecordPayment = perms?.can("FINANCE_RECORD_PAYMENT") ?? false;

  return (
    <div className="space-y-4">
      <Back />
      <PageHeader
        title={e.studentName}
        subtitle={`${e.programName} · ${e.programLevel}`}
        action={
          <div className="flex flex-wrap gap-2">
            {canRecordPayment && e.pricingType !== "MEMBERSHIP_INCLUDED" && e.outstandingMinor > 0 && (
              <Button asChild size="sm" variant="outline">
                <Link href={`/finance/pending-payments/${e.id}/record`}>Record Payment</Link>
              </Button>
            )}
            {canManage && e.status === "ACTIVE" && (
              <Button size="sm" variant="outline" disabled={busy} onClick={() => void setStatus("PAUSED")}>
                Pause
              </Button>
            )}
            {canManage && e.status === "PAUSED" && (
              <Button size="sm" variant="outline" disabled={busy} onClick={() => void setStatus("ACTIVE")}>
                Resume
              </Button>
            )}
            {canManage && (e.status === "ACTIVE" || e.status === "PAUSED") && (
              <Button size="sm" variant="outline" disabled={busy} onClick={() => void setStatus("COMPLETED")}>
                Complete
              </Button>
            )}
            {canManage && e.status !== "CANCELLED" && e.status !== "COMPLETED" && (
              <Button size="sm" variant="outline" onClick={() => setDialog("cancel")}>
                Cancel
              </Button>
            )}
            {canManage && (
              <Button size="sm" onClick={() => setDialog("edit")}>
                Edit
              </Button>
            )}
          </div>
        }
      />

      <Card className="p-4">
        <div className="flex flex-wrap items-center gap-2">
          {enrollmentStatusBadge(e.status)}
          {e.status === "CANCELLED" && e.cancelReason && (
            <span className="text-sm text-muted-foreground">Cancelled: {e.cancelReason}</span>
          )}
        </div>
        <div className="mt-3 grid grid-cols-2 gap-3 lg:grid-cols-4">
          <Stat label="Fee" value={e.pricingType === "MEMBERSHIP_INCLUDED" ? "Included" : money(e.priceMinor)} />
          <Stat label="Paid" value={money(e.paidMinor)} />
          <Stat label="Outstanding" value={money(e.outstandingMinor)} />
          <Stat label="Sessions" value={e.sessionsTotal != null ? String(e.sessionsTotal) : "—"} />
        </div>
      </Card>

      <Tabs tabs={TABS} active={tab} onChange={setTab} />

      {tab === "Overview" && (
        <Card className="p-4">
          <h3 className="text-sm font-semibold">Enrollment</h3>
          <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2 text-sm md:grid-cols-3">
            <Row label="Student" value={`${e.studentName}${e.studentPhone ? ` · ${e.studentPhone}` : ""}`} />
            <Row label="Program" value={e.programName} />
            <Row label="Coach" value={e.coachName ?? "—"} />
            <Row label="Start date" value={fmtDate(e.startDate)} />
            <Row label="End date" value={fmtDate(e.endDate)} />
            <Row label="Pricing" value={e.pricingType} />
            <Row label="Enrolled" value={fmtDate(e.createdAt)} />
          </dl>
          {e.notes && <p className="mt-3 text-sm text-muted-foreground">{e.notes}</p>}
        </Card>
      )}

      {tab === "Sessions" && (
        <Card className="p-0">
          {e.sessions.length === 0 ? (
            <div className="p-10 text-center text-sm text-muted-foreground">Not on any session rosters yet.</div>
          ) : (
            <ul className="divide-y divide-border">
              {e.sessions.map((s) => (
                <li key={s.id} className="flex items-center justify-between p-3 text-sm">
                  <Link href={`/coaching/sessions/${s.id}`} className="font-medium hover:underline">
                    {s.programName}
                  </Link>
                  <span className="flex items-center gap-2 text-muted-foreground">
                    {fmtDateTime(s.startAt)} · {s.courtName}
                    {sessionStatusBadge(s.status)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      )}

      {tab === "Payments" && (
        <Card className="p-0">
          {e.payments.length === 0 ? (
            <div className="p-10 text-center text-sm text-muted-foreground">No payments recorded.</div>
          ) : (
            <ul className="divide-y divide-border">
              {e.payments.map((p) => (
                <li key={p.id} className="flex items-center justify-between p-3 text-sm">
                  <span>{money(p.amountMinor)}</span>
                  <span className="text-muted-foreground">
                    {fmtDate(p.paidAt)}
                    {p.method ? ` · ${p.method}` : ""}
                    {p.reference ? ` · ${p.reference}` : ""}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      )}

      {tab === "Progress" && (
        <Card className="p-0">
          <div className="flex items-center justify-between p-4">
            <h3 className="text-sm font-semibold">Progress Notes</h3>
            {canProgress && (
              <Button size="sm" variant="outline" onClick={() => setDialog("progress")}>
                Add note
              </Button>
            )}
          </div>
          {!canViewProgress ? (
            <div className="p-10 text-center text-sm text-muted-foreground">
              You don&apos;t have permission to view student progress.
            </div>
          ) : !e.progressNotes || e.progressNotes.length === 0 ? (
            <div className="p-10 text-center text-sm text-muted-foreground">No progress notes yet.</div>
          ) : (
            <ul className="divide-y divide-border">
              {e.progressNotes.map((n) => (
                <li key={n.id} className="p-3 text-sm">
                  <div className="flex items-center justify-between">
                    <span className="font-medium">{n.skillOrGoal ?? "Progress note"}</span>
                    {progressBadge(n.progressStatus)}
                  </div>
                  <p className="mt-1">{n.note}</p>
                  <p className="mt-1 text-xs text-muted-foreground">
                    {n.coachName ? `${n.coachName} · ` : ""}
                    {fmtDate(n.createdAt)}
                  </p>
                </li>
              ))}
            </ul>
          )}
        </Card>
      )}

      {dialog === "edit" && (
        <EditEnrollmentDialog
          enrollment={e}
          canPrice={perms?.can("COACHING_MANAGE_PRICING") ?? false}
          onClose={() => setDialog(null)}
          onSaved={() => {
            setDialog(null);
            void load();
          }}
        />
      )}
      {dialog === "cancel" && (
        <CancelEnrollmentDialog
          enrollmentId={e.id}
          onClose={() => setDialog(null)}
          onDone={() => {
            setDialog(null);
            void load();
          }}
        />
      )}
      {dialog === "progress" && (
        <AddProgressDialog
          enrollmentId={e.id}
          onClose={() => setDialog(null)}
          onDone={() => {
            setDialog(null);
            void load();
          }}
        />
      )}
    </div>
  );
}

function EditEnrollmentDialog({
  enrollment,
  canPrice,
  onClose,
  onSaved,
}: {
  enrollment: EnrollmentDetail;
  canPrice: boolean;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [startDate, setStartDate] = useState(enrollment.startDate);
  const [endDate, setEndDate] = useState(enrollment.endDate ?? "");
  const [sessionsTotal, setSessionsTotal] = useState(enrollment.sessionsTotal != null ? String(enrollment.sessionsTotal) : "");
  const [price, setPrice] = useState(minorToRupees(enrollment.priceMinor));
  const [notes, setNotes] = useState(enrollment.notes ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save() {
    setBusy(true);
    setError(null);
    try {
      await getCoachingService().updateEnrollment({
        enrollmentId: enrollment.id,
        startDate,
        endDate: endDate || null,
        sessionsTotal: sessionsTotal.trim() ? Number(sessionsTotal) : null,
        priceMinor: canPrice && enrollment.pricingType !== "MEMBERSHIP_INCLUDED" ? rupeesToMinor(price) : null,
        notes: notes.trim() || null,
      });
      onSaved();
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Could not save changes.");
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(v) => !v && !busy && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Edit enrollment</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Field label="Start date">
              <Input type="date" value={startDate} onChange={(ev) => setStartDate(ev.target.value)} />
            </Field>
            <Field label="End date">
              <Input type="date" value={endDate} onChange={(ev) => setEndDate(ev.target.value)} />
            </Field>
          </div>
          <Field label="Sessions in package">
            <Input type="number" min="1" step="1" value={sessionsTotal} onChange={(ev) => setSessionsTotal(ev.target.value)} />
          </Field>
          {canPrice && enrollment.pricingType !== "MEMBERSHIP_INCLUDED" && (
            <Field label="Fee (₹)">
              <Input type="number" min="0" step="1" value={price} onChange={(ev) => setPrice(ev.target.value)} />
            </Field>
          )}
          <Field label="Notes">
            <Textarea rows={2} value={notes} onChange={(ev) => setNotes(ev.target.value)} />
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

function CancelEnrollmentDialog({
  enrollmentId,
  onClose,
  onDone,
}: {
  enrollmentId: string;
  onClose: () => void;
  onDone: () => void;
}) {
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
      await getCoachingService().setEnrollmentStatus(enrollmentId, "CANCELLED", reason.trim());
      onDone();
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Could not cancel the enrollment.");
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(v) => !v && !busy && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Cancel enrollment</DialogTitle>
          <DialogDescription>
            The enrollment record is kept. Any refund is handled separately through Finance.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <Field label="Reason">
            <Textarea rows={3} value={reason} onChange={(e) => setReason(e.target.value)} />
          </Field>
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" disabled={busy} onClick={onClose}>
            Keep enrollment
          </Button>
          <Button variant="destructive" disabled={busy} onClick={() => void submit()}>
            {busy ? "Cancelling…" : "Cancel Enrollment"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function AddProgressDialog({
  enrollmentId,
  onClose,
  onDone,
}: {
  enrollmentId: string;
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
      });
      onDone();
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Could not save the note.");
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(v) => !v && !busy && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Add progress note</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <Field label="Skill or goal (optional)">
            <Input value={skill} onChange={(e) => setSkill(e.target.value)} />
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
    <Link href="/coaching/enrollments" className="text-sm text-muted-foreground hover:underline">
      ← Back to enrollments
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
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="mt-0.5 text-lg font-semibold tabular-nums">{value}</p>
    </div>
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
