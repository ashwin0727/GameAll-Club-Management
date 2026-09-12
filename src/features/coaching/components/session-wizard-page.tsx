"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { ServiceError } from "@/services/shared/service-error";
import { getCoachingService } from "@/services/coaching";
import { getCourtOptions, type CourtOption } from "@/features/maintenance/court-options";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import { PermissionDenied } from "@/features/staff/components/permission-denied";
import { PageHeader } from "@/features/coaching/components/shared";
import type { CoachOption, ProgramOption } from "@/features/coaching/types";

export function SessionWizardPage() {
  const perms = usePermissionContext();
  const router = useRouter();
  const facilityId = perms?.facilityId ?? null;

  const [programs, setPrograms] = useState<ProgramOption[]>([]);
  const [coaches, setCoaches] = useState<CoachOption[]>([]);
  const [courts, setCourts] = useState<CourtOption[]>([]);
  const [refsLoading, setRefsLoading] = useState(true);

  const [programId, setProgramId] = useState("");
  const [coachId, setCoachId] = useState("");
  const [courtId, setCourtId] = useState("");
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [startTime, setStartTime] = useState("09:00");
  const [endTime, setEndTime] = useState("10:00");
  const [capacity, setCapacity] = useState("");
  const [objective, setObjective] = useState("");
  const [notes, setNotes] = useState("");
  const [autoEnroll, setAutoEnroll] = useState(true);
  const [confirmNow, setConfirmNow] = useState(false);

  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const program = useMemo(() => programs.find((p) => p.id === programId), [programs, programId]);

  useEffect(() => {
    if (!facilityId) return;
    Promise.all([
      getCoachingService().listProgramOptions(facilityId),
      getCoachingService().listCoachOptions(facilityId),
      getCourtOptions(facilityId),
    ])
      .then(([p, c, ct]) => {
        setPrograms(p);
        setCoaches(c);
        setCourts(ct);
      })
      .catch(() => setError("Could not load programs, coaches or courts."))
      .finally(() => setRefsLoading(false));
  }, [facilityId]);

  // Prefill duration + capacity from the chosen program.
  useEffect(() => {
    if (!program) return;
    setCapacity((cur) => cur || String(program.defaultCapacity));
    const [h = 0, m = 0] = startTime.split(":").map(Number);
    const end = new Date(2000, 0, 1, h, m + program.defaultDurationMinutes);
    setEndTime(`${String(end.getHours()).padStart(2, "0")}:${String(end.getMinutes()).padStart(2, "0")}`);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [programId]);

  if (!perms?.can("COACHING_CREATE_SESSION")) {
    return <PermissionDenied message="You don't have permission to create coaching sessions." />;
  }

  async function submit() {
    if (!facilityId) return;
    if (!programId || !coachId || !courtId) {
      setError("Choose a program, coach and court.");
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
      const id = await getCoachingService().createSession({
        facilityId,
        programId,
        coachId,
        courtId,
        startAt: startAt.toISOString(),
        endAt: endAt.toISOString(),
        capacity: capacity.trim() ? Number(capacity) : null,
        objective: objective.trim() || null,
        notes: notes.trim() || null,
        status: confirmNow ? "CONFIRMED" : "SCHEDULED",
        autoEnroll,
      });
      router.push(`/coaching/sessions/${id}`);
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not create the session.");
      setBusy(false);
    }
  }

  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <PageHeader
        title="New Session"
        subtitle="The court, coach and time are checked against every other booking, session and maintenance block."
      />

      <Card className="space-y-4 p-5">
        {refsLoading ? (
          <p className="text-sm text-muted-foreground">Loading…</p>
        ) : (
          <>
            <F label="Program">
              <Select value={programId} onValueChange={setProgramId}>
                <SelectTrigger>
                  <SelectValue placeholder="Select a program" />
                </SelectTrigger>
                <SelectContent>
                  {programs.map((p) => (
                    <SelectItem key={p.id} value={p.id}>
                      {p.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </F>
            <F label="Coach">
              <Select value={coachId} onValueChange={setCoachId}>
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
            </F>
            <F label="Court">
              <Select value={courtId} onValueChange={setCourtId}>
                <SelectTrigger>
                  <SelectValue placeholder="Select a court" />
                </SelectTrigger>
                <SelectContent>
                  {courts.map((c) => (
                    <SelectItem key={c.id} value={c.id}>
                      {c.name} · {c.sportName}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </F>
            <div className="grid grid-cols-3 gap-3">
              <F label="Date">
                <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
              </F>
              <F label="Start">
                <Input type="time" value={startTime} onChange={(e) => setStartTime(e.target.value)} />
              </F>
              <F label="End">
                <Input type="time" value={endTime} onChange={(e) => setEndTime(e.target.value)} />
              </F>
            </div>
            <F label="Capacity">
              <Input
                type="number"
                min="1"
                step="1"
                value={capacity}
                onChange={(e) => setCapacity(e.target.value)}
                placeholder={program ? String(program.defaultCapacity) : "10"}
              />
            </F>
            <F label="Objective (optional)">
              <Input value={objective} onChange={(e) => setObjective(e.target.value)} />
            </F>
            <F label="Notes (optional)">
              <Textarea rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
            </F>
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={autoEnroll} onChange={(e) => setAutoEnroll(e.target.checked)} />
              Add the program&apos;s active students to this session&apos;s roster
            </label>
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={confirmNow} onChange={(e) => setConfirmNow(e.target.checked)} />
              Mark as confirmed
            </label>
          </>
        )}

        {error && <p className="text-sm text-destructive">{error}</p>}

        <div className="flex items-center justify-between border-t border-border pt-4">
          <Button asChild variant="outline">
            <Link href="/coaching/schedule">Cancel</Link>
          </Button>
          <Button onClick={() => void submit()} disabled={busy || refsLoading}>
            {busy ? "Creating…" : "Create Session"}
          </Button>
        </div>
      </Card>
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
