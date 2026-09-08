"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { AlertTriangle, ArrowLeft, Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";
import { PRIORITY_LABEL, formatDateTime, formatMoney } from "@/features/maintenance/status";
import { getCourtOptions, type CourtOption } from "@/features/maintenance/court-options";
import type { AffectedBooking, MaintenanceIssueCategory, MaintenancePriority } from "@/features/maintenance/types";
import { getFacilityService } from "@/services/facility";
import { getMaintenanceService, type FacilityStaffOption } from "@/services/maintenance";
import { ServiceError } from "@/services/shared/service-error";

const STEPS = ["Issue Details", "Schedule", "Assignment", "Review"] as const;
const PRIORITIES: MaintenancePriority[] = ["LOW", "MEDIUM", "HIGH", "CRITICAL"];

const selectCls =
  "h-11 w-full appearance-none rounded-lg border border-input bg-background px-3 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30";

function toLocalInputValue(d: Date): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function CreateTicketWizard() {
  const router = useRouter();
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [loadState, setLoadState] = useState<"loading" | "ready" | "none" | "error">("loading");
  const [courts, setCourts] = useState<CourtOption[]>([]);
  const [categories, setCategories] = useState<MaintenanceIssueCategory[]>([]);
  const [staff, setStaff] = useState<FacilityStaffOption[]>([]);

  const [step, setStep] = useState(0);

  // Step 1
  const [courtId, setCourtId] = useState("");
  const [issueCategoryId, setIssueCategoryId] = useState("");
  const [priority, setPriority] = useState<MaintenancePriority>("MEDIUM");
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");

  // Step 2
  const [shouldSchedule, setShouldSchedule] = useState(false);
  const now = useMemo(() => new Date(), []);
  const [scheduledStart, setScheduledStart] = useState(toLocalInputValue(new Date(now.getTime() + 60 * 60 * 1000)));
  const [scheduledEnd, setScheduledEnd] = useState(toLocalInputValue(new Date(now.getTime() + 4 * 60 * 60 * 1000)));
  const [affected, setAffected] = useState<AffectedBooking[]>([]);
  const [checkingConflicts, setCheckingConflicts] = useState(false);

  // Step 3
  const [assignedTo, setAssignedTo] = useState("");
  const [estimatedCost, setEstimatedCost] = useState("");
  const [notes, setNotes] = useState("");

  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    getFacilityService()
      .getFacility()
      .then(async (f) => {
        if (cancelled) return;
        if (!f) return setLoadState("none");
        setFacilityId(f.id);
        const [courtOptions, cats, staffOptions] = await Promise.all([
          getCourtOptions(f.id),
          getMaintenanceService().listIssueCategories(f.id, false),
          getMaintenanceService().listAssignableStaff(f.id),
        ]);
        if (cancelled) return;
        setCourts(courtOptions);
        setCategories(cats);
        setStaff(staffOptions);
        setLoadState("ready");
      })
      .catch(() => !cancelled && setLoadState("error"));
    return () => {
      cancelled = true;
    };
  }, []);

  const checkConflicts = useCallback(async () => {
    if (!courtId || !shouldSchedule) {
      setAffected([]);
      return;
    }
    const start = new Date(scheduledStart);
    const end = new Date(scheduledEnd);
    if (end <= start) {
      setAffected([]);
      return;
    }
    setCheckingConflicts(true);
    try {
      const rows = await getMaintenanceService().detectAffectedBookings(courtId, start.toISOString(), end.toISOString());
      setAffected(rows);
    } catch {
      setAffected([]);
    } finally {
      setCheckingConflicts(false);
    }
  }, [courtId, shouldSchedule, scheduledStart, scheduledEnd]);

  useEffect(() => {
    void checkConflicts();
  }, [checkConflicts]);

  const canProceed = useMemo(() => {
    if (step === 0) return !!courtId && !!issueCategoryId && title.trim().length >= 3 && description.trim().length >= 5;
    if (step === 1) return !shouldSchedule || new Date(scheduledEnd) > new Date(scheduledStart);
    return true;
  }, [step, courtId, issueCategoryId, title, description, shouldSchedule, scheduledStart, scheduledEnd]);

  async function handleCreate() {
    if (!facilityId) return;
    setSubmitting(true);
    setError(null);
    try {
      const created = await getMaintenanceService().createTicket({
        facilityId,
        courtId,
        issueCategoryId,
        priority,
        title: title.trim(),
        description: description.trim(),
        scheduledStart: shouldSchedule ? new Date(scheduledStart).toISOString() : null,
        scheduledEnd: shouldSchedule ? new Date(scheduledEnd).toISOString() : null,
        assignedTo: assignedTo || null,
        estimatedCostMinor: estimatedCost ? Math.round(Number(estimatedCost) * 100) : null,
        notes: notes || null,
      });
      router.push(`/maintenance/tickets/${created.id}`);
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to create this ticket.");
    } finally {
      setSubmitting(false);
    }
  }

  if (loadState === "loading") return <Skeleton className="h-96 w-full rounded-xl" />;
  if (loadState === "none") return <p className="text-sm text-muted-foreground">No facility found for this account yet.</p>;
  if (loadState === "error") return <p className="text-sm text-destructive">Unable to load this page. Please try again.</p>;

  const selectedCourt = courts.find((c) => c.id === courtId);
  const selectedCategory = categories.find((c) => c.id === issueCategoryId);
  const selectedStaff = staff.find((s) => s.userId === assignedTo);

  return (
    <div className="space-y-6">
      <div className="space-y-1">
        <button onClick={() => router.push("/maintenance/tickets")} className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground">
          <ArrowLeft className="h-4 w-4" /> Back to Tickets
        </button>
        <h1 className="text-xl font-semibold">Create Maintenance Ticket</h1>
        <p className="text-sm text-muted-foreground">Report an issue, schedule maintenance and keep your courts in top condition.</p>
      </div>

      <div className="flex flex-wrap items-center gap-x-2 gap-y-3">
        {STEPS.map((label, i) => (
          <div key={label} className="flex items-center gap-2">
            <span
              className={cn(
                "flex h-6 w-6 items-center justify-center rounded-full text-xs font-semibold",
                i < step ? "bg-success text-white" : i === step ? "bg-primary text-primary-foreground" : "bg-secondary text-muted-foreground",
              )}
            >
              {i < step ? <Check className="h-3.5 w-3.5" /> : i + 1}
            </span>
            <span className={cn("text-sm", i === step ? "font-medium text-foreground" : "text-muted-foreground")}>{label}</span>
            {i < STEPS.length - 1 && <span className="mx-1 hidden h-px w-8 bg-border sm:block" />}
          </div>
        ))}
      </div>

      <div key={step} className="stat-enter rounded-xl border border-border p-5">
        {step === 0 && (
          <div className="space-y-4">
            <div className="grid gap-3 sm:grid-cols-2">
              <label className="space-y-1">
                <span className="text-xs text-muted-foreground">Court *</span>
                <select value={courtId} onChange={(e) => setCourtId(e.target.value)} className={selectCls}>
                  <option value="">Select court</option>
                  {courts.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name} — {c.sportName}
                    </option>
                  ))}
                </select>
              </label>
              <label className="space-y-1">
                <span className="text-xs text-muted-foreground">Issue Category *</span>
                <select value={issueCategoryId} onChange={(e) => setIssueCategoryId(e.target.value)} className={selectCls}>
                  <option value="">Select issue type</option>
                  {categories.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name}
                    </option>
                  ))}
                </select>
              </label>
            </div>

            <div className="space-y-1.5">
              <span className="text-xs text-muted-foreground">Priority *</span>
              <div className="flex flex-wrap gap-2">
                {PRIORITIES.map((p) => (
                  <button
                    key={p}
                    type="button"
                    onClick={() => setPriority(p)}
                    className={cn(
                      "rounded-md border px-3 py-1.5 text-xs font-medium",
                      priority === p ? "border-primary bg-primary/10 text-primary" : "border-border text-muted-foreground hover:bg-secondary",
                    )}
                  >
                    {PRIORITY_LABEL[p]}
                  </button>
                ))}
              </div>
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="mt-title">Title *</Label>
              <Input id="mt-title" value={title} onChange={(e) => setTitle(e.target.value.slice(0, 100))} placeholder="e.g. Net damaged, AC not working" />
              <p className="text-right text-[11px] text-muted-foreground">{title.length}/100</p>
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="mt-desc">Description *</Label>
              <Textarea
                id="mt-desc"
                value={description}
                onChange={(e) => setDescription(e.target.value.slice(0, 500))}
                rows={4}
                placeholder="Describe the issue, its impact on play, and any additional notes…"
              />
              <p className="text-right text-[11px] text-muted-foreground">{description.length}/500</p>
            </div>
          </div>
        )}

        {step === 1 && (
          <div className="space-y-4">
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={shouldSchedule} onChange={(e) => setShouldSchedule(e.target.checked)} className="h-4 w-4 rounded border-input" />
              Schedule maintenance now
            </label>

            {shouldSchedule && (
              <>
                <div className="grid gap-3 sm:grid-cols-2">
                  <label className="space-y-1">
                    <span className="text-xs text-muted-foreground">Start</span>
                    <Input type="datetime-local" value={scheduledStart} onChange={(e) => setScheduledStart(e.target.value)} />
                  </label>
                  <label className="space-y-1">
                    <span className="text-xs text-muted-foreground">End</span>
                    <Input type="datetime-local" value={scheduledEnd} onChange={(e) => setScheduledEnd(e.target.value)} />
                  </label>
                </div>

                {checkingConflicts && <p className="text-xs text-muted-foreground">Checking for affected bookings…</p>}
                {!checkingConflicts && affected.length > 0 && (
                  <div className="flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">
                    <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
                    <div>
                      <p className="font-medium">{affected.length} existing booking{affected.length > 1 ? "s" : ""} will be affected</p>
                      <p className="text-xs">This window overlaps existing bookings. They will not be cancelled automatically — handle them from the ticket after creation.</p>
                    </div>
                  </div>
                )}
              </>
            )}
            {!shouldSchedule && <p className="text-sm text-muted-foreground">You can schedule this ticket later from its details page.</p>}
          </div>
        )}

        {step === 2 && (
          <div className="space-y-4">
            <label className="space-y-1">
              <span className="text-xs text-muted-foreground">Assign Staff</span>
              <select value={assignedTo} onChange={(e) => setAssignedTo(e.target.value)} className={selectCls}>
                <option value="">Unassigned</option>
                {staff.map((s) => (
                  <option key={s.userId} value={s.userId}>
                    {s.fullName} ({s.role})
                  </option>
                ))}
              </select>
            </label>
            <label className="space-y-1">
              <span className="text-xs text-muted-foreground">Estimated Repair Cost (₹)</span>
              <Input type="number" min={0} value={estimatedCost} onChange={(e) => setEstimatedCost(e.target.value)} placeholder="0" />
            </label>
            <label className="space-y-1">
              <span className="text-xs text-muted-foreground">Notes</span>
              <Textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={3} placeholder="Any additional notes for the assigned staff" />
            </label>
          </div>
        )}

        {step === 3 && (
          <div className="space-y-3 text-sm">
            <ReviewRow label="Court" value={selectedCourt ? `${selectedCourt.name} — ${selectedCourt.sportName}` : "—"} />
            <ReviewRow label="Issue" value={selectedCategory?.name ?? "—"} />
            <ReviewRow label="Priority" value={PRIORITY_LABEL[priority]} />
            <ReviewRow label="Title" value={title} />
            <ReviewRow label="Description" value={description} />
            <ReviewRow label="Schedule" value={shouldSchedule ? `${formatDateTime(new Date(scheduledStart).toISOString())} → ${formatDateTime(new Date(scheduledEnd).toISOString())}` : "Not scheduled"} />
            <ReviewRow label="Assigned Staff" value={selectedStaff?.fullName ?? "Unassigned"} />
            <ReviewRow label="Estimated Cost" value={estimatedCost ? formatMoney(Math.round(Number(estimatedCost) * 100)) : "—"} />
            {affected.length > 0 && shouldSchedule && (
              <p className="flex items-center gap-1.5 text-xs text-destructive">
                <AlertTriangle className="h-3.5 w-3.5" /> {affected.length} booking(s) overlap this schedule — review them after creating the ticket.
              </p>
            )}
          </div>
        )}

        {error && <p className="mt-4 text-sm text-destructive" role="alert">{error}</p>}
      </div>

      <div className="flex items-center justify-between">
        <Button variant="outline" onClick={() => (step === 0 ? router.push("/maintenance/tickets") : setStep((s) => s - 1))} disabled={submitting}>
          {step === 0 ? "Cancel" : "Back"}
        </Button>
        {step < STEPS.length - 1 ? (
          <Button onClick={() => setStep((s) => s + 1)} disabled={!canProceed}>
            Next
          </Button>
        ) : (
          <Button onClick={handleCreate} disabled={submitting}>
            {submitting ? "Creating…" : "Create Maintenance Ticket"}
          </Button>
        )}
      </div>
    </div>
  );
}

function ReviewRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="grid grid-cols-3 gap-3 border-b border-border py-2 last:border-0">
      <span className="text-muted-foreground">{label}</span>
      <span className="col-span-2 font-medium">{value}</span>
    </div>
  );
}
