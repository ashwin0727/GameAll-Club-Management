"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Badge } from "@/components/ui/badge";
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
import { Textarea } from "@/components/ui/textarea";
import { ServiceError } from "@/services/shared/service-error";
import { getCoachingService } from "@/services/coaching";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { ProgramDetail } from "@/features/coaching/types";
import {
  ErrorState,
  PageHeader,
  TableSkeleton,
  fmtDate,
  minorToRupees,
  money,
  rupeesToMinor,
} from "@/features/coaching/components/shared";

export function ProgramDetailsPage({ programId }: { programId: string }) {
  const perms = usePermissionContext();
  const [program, setProgram] = useState<ProgramDetail | null>(null);
  const [state, setState] = useState<"loading" | "ready" | "error">("loading");
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
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

  return (
    <div className="space-y-4">
      <Back />
      <PageHeader
        title={p.name}
        subtitle={`${p.level} · ${p.ageGroup} · ${p.category}`}
        action={
          canManage && (
            <div className="flex gap-2">
              <Button size="sm" variant="outline" disabled={busy} onClick={() => void toggleStatus()}>
                {p.status === "ACTIVE" ? "Deactivate" : "Reactivate"}
              </Button>
              <Button size="sm" onClick={() => setEditing(true)}>
                Edit
              </Button>
            </div>
          )
        }
      />

      <div className="flex flex-wrap items-center gap-2">
        <Badge variant={p.status === "ACTIVE" ? "success" : "secondary"}>
          {p.status === "ACTIVE" ? "Active" : "Inactive"}
        </Badge>
        {p.isMembershipIncluded && <Badge variant="outline">Membership-included</Badge>}
      </div>

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Stat label="Active Students" value={String(p.stats.activeStudents)} />
        <Stat label="Total Enrollments" value={String(p.stats.totalEnrollments)} />
        <Stat label="Scheduled Sessions" value={String(p.stats.scheduledSessions)} />
        <Stat label="Completed Sessions" value={String(p.stats.completedSessions)} />
      </div>

      <Card className="p-4">
        <h2 className="text-sm font-semibold">Details</h2>
        <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
          <Row label="Default duration" value={`${p.defaultDurationMinutes} min`} />
          <Row label="Default capacity" value={String(p.defaultCapacity)} />
          <Row label="Sessions / package" value={p.sessionCount != null ? String(p.sessionCount) : "—"} />
          <Row
            label="Default price"
            value={p.isMembershipIncluded ? "Included" : p.defaultPriceMinor != null ? money(p.defaultPriceMinor) : "Per enrollment"}
          />
          <Row label="Created" value={fmtDate(p.createdAt)} />
        </dl>
        {p.description && <p className="mt-3 text-sm text-muted-foreground">{p.description}</p>}
      </Card>

      {editing && (
        <EditProgramDialog
          program={p}
          canPrice={perms?.can("COACHING_MANAGE_PRICING") ?? false}
          onClose={() => setEditing(false)}
          onSaved={() => {
            setEditing(false);
            void load();
          }}
        />
      )}
    </div>
  );
}

function EditProgramDialog({
  program,
  canPrice,
  onClose,
  onSaved,
}: {
  program: ProgramDetail;
  canPrice: boolean;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [name, setName] = useState(program.name);
  const [level, setLevel] = useState(program.level);
  const [ageGroup, setAgeGroup] = useState(program.ageGroup);
  const [category, setCategory] = useState(program.category);
  const [description, setDescription] = useState(program.description ?? "");
  const [duration, setDuration] = useState(String(program.defaultDurationMinutes));
  const [capacity, setCapacity] = useState(String(program.defaultCapacity));
  const [sessionCount, setSessionCount] = useState(program.sessionCount != null ? String(program.sessionCount) : "");
  const [price, setPrice] = useState(minorToRupees(program.defaultPriceMinor));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save() {
    setBusy(true);
    setError(null);
    try {
      await getCoachingService().updateProgram({
        programId: program.id,
        name: name.trim(),
        level,
        ageGroup,
        category,
        description: description.trim() || null,
        defaultDurationMinutes: Number(duration) || program.defaultDurationMinutes,
        defaultCapacity: Number(capacity) || program.defaultCapacity,
        sessionCount: sessionCount.trim() ? Number(sessionCount) : null,
        defaultPriceMinor: canPrice && !program.isMembershipIncluded ? rupeesToMinor(price) : null,
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
          <DialogTitle>Edit program</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <Field label="Name">
            <Input value={name} onChange={(e) => setName(e.target.value)} />
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Level">
              <Input value={level} onChange={(e) => setLevel(e.target.value)} />
            </Field>
            <Field label="Age group">
              <Input value={ageGroup} onChange={(e) => setAgeGroup(e.target.value)} />
            </Field>
          </div>
          <Field label="Category">
            <Input value={category} onChange={(e) => setCategory(e.target.value)} />
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Duration (min)">
              <Input type="number" min="15" step="5" value={duration} onChange={(e) => setDuration(e.target.value)} />
            </Field>
            <Field label="Capacity">
              <Input type="number" min="1" step="1" value={capacity} onChange={(e) => setCapacity(e.target.value)} />
            </Field>
          </div>
          <Field label="Sessions / package">
            <Input type="number" min="1" step="1" value={sessionCount} onChange={(e) => setSessionCount(e.target.value)} />
          </Field>
          {canPrice && !program.isMembershipIncluded && (
            <Field label="Default price (₹)">
              <Input type="number" min="0" step="1" value={price} onChange={(e) => setPrice(e.target.value)} />
            </Field>
          )}
          <Field label="Description">
            <Textarea rows={3} value={description} onChange={(e) => setDescription(e.target.value)} />
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

function Back() {
  return (
    <Link href="/coaching/programs" className="text-sm text-muted-foreground hover:underline">
      ← Back to programs
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
    <Card className="p-3">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="mt-0.5 text-lg font-semibold tabular-nums">{value}</p>
    </Card>
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
