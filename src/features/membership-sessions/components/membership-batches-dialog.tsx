"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { getMembershipService } from "@/services/memberships";
import { getMembershipSessionService } from "@/services/membership-sessions";
import { getSportsService } from "@/services/sports";
import { getPlayingAreasService } from "@/services/playing-areas";
import type { MembershipBatch } from "@/features/membership-sessions/types";
import type { MembershipPlan } from "@/features/memberships/types";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";
import type { PlayingArea } from "@/features/courts-setup/types";
import { ServiceError } from "@/services/shared/service-error";
import { BatchMembersDialog } from "@/features/membership-sessions/components/batch-members-dialog";

const DAYS = [
  { value: 1, label: "Mon" },
  { value: 2, label: "Tue" },
  { value: 3, label: "Wed" },
  { value: 4, label: "Thu" },
  { value: 5, label: "Fri" },
  { value: 6, label: "Sat" },
  { value: 0, label: "Sun" },
];

function daysLabel(daysOfWeek: number[]): string {
  return DAYS.filter((d) => daysOfWeek.includes(d.value))
    .map((d) => d.label)
    .join("/");
}

export function MembershipBatchesDialog({
  open,
  onOpenChange,
  facilityId,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  facilityId: string;
}) {
  const [batches, setBatches] = useState<MembershipBatch[] | null>(null);
  const [plans, setPlans] = useState<MembershipPlan[]>([]);
  const [facilitySports, setFacilitySports] = useState<FacilitySport[]>([]);
  const [sports, setSports] = useState<Sport[]>([]);
  const [areas, setAreas] = useState<PlayingArea[]>([]);
  const [managingBatch, setManagingBatch] = useState<MembershipBatch | null>(null);

  const [name, setName] = useState("");
  const [planId, setPlanId] = useState("");
  const [facilitySportId, setFacilitySportId] = useState("");
  const [courtId, setCourtId] = useState("");
  const [days, setDays] = useState<number[]>([]);
  const [startTime, setStartTime] = useState("18:00");
  const [endTime, setEndTime] = useState("19:00");
  const [capacity, setCapacity] = useState("5");
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function reload() {
    getMembershipSessionService()
      .getFacilityBatches(facilityId)
      .then(setBatches)
      .catch(() => setBatches([]));
  }

  useEffect(() => {
    if (!open) return;
    setBatches(null);
    setName("");
    setPlanId("");
    setFacilitySportId("");
    setCourtId("");
    setDays([]);
    setStartTime("18:00");
    setEndTime("19:00");
    setCapacity("5");
    setError(null);
    reload();
    Promise.all([
      getMembershipService().getFacilityPlans(facilityId, { activeOnly: true }),
      getSportsService().getFacilitySports(facilityId),
      getSportsService().getActiveSports(),
      getPlayingAreasService().getPlayingAreas(facilityId),
    ]).then(([p, fs, allSports, playingAreas]) => {
      setPlans(p);
      setFacilitySports(fs.filter((f) => f.enabled));
      setSports(allSports);
      setAreas(playingAreas.filter((a) => !a.archived && a.status === "ACTIVE" && a.bookingEnabled));
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, facilityId]);

  const courtsForSport = areas.filter((a) => a.facilitySportId === facilitySportId);

  function toggleDay(value: number) {
    setDays((prev) => (prev.includes(value) ? prev.filter((d) => d !== value) : [...prev, value]));
  }

  async function addBatch() {
    const cap = Number(capacity);
    if (name.trim().length < 2) {
      setError("Enter a batch name.");
      return;
    }
    if (!planId || !facilitySportId || !courtId) {
      setError("Select a plan, sport, and court.");
      return;
    }
    if (days.length === 0) {
      setError("Select at least one day.");
      return;
    }
    if (!Number.isInteger(cap) || cap <= 0) {
      setError("Enter a valid capacity.");
      return;
    }
    if (endTime <= startTime) {
      setError("End time must be after start time.");
      return;
    }
    setIsSaving(true);
    setError(null);
    try {
      await getMembershipSessionService().createBatch({
        facilityId,
        planId,
        facilitySportId,
        courtId,
        name: name.trim(),
        daysOfWeek: days,
        startTime,
        endTime,
        capacity: cap,
      });
      setName("");
      setDays([]);
      setCapacity("5");
      reload();
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to save this batch.");
    } finally {
      setIsSaving(false);
    }
  }

  async function toggleActive(batch: MembershipBatch) {
    await getMembershipSessionService().updateBatch(batch.id, { isActive: !batch.isActive });
    reload();
  }

  return (
    <>
      <Dialog open={open && !managingBatch} onOpenChange={onOpenChange}>
        <DialogContent className="max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Membership Batches</DialogTitle>
            <DialogDescription>Recurring sessions that reserve court capacity for a membership plan.</DialogDescription>
          </DialogHeader>

          {batches === null ? (
            <Skeleton className="h-40 w-full rounded-lg" />
          ) : (
            <div className="space-y-4">
              {batches.length === 0 ? (
                <p className="text-sm text-muted-foreground">No batches yet — add the first one below.</p>
              ) : (
                <div className="divide-y rounded-md border border-border">
                  {batches.map((batch) => (
                    <div key={batch.id} className="flex items-center justify-between gap-2 p-3 text-sm">
                      <div>
                        <p className="font-medium">
                          {batch.name} {!batch.isActive && <Badge variant="secondary">Inactive</Badge>}
                        </p>
                        <p className="text-muted-foreground">
                          {daysLabel(batch.daysOfWeek)} · {batch.startTime.slice(0, 5)}–{batch.endTime.slice(0, 5)} · Capacity {batch.capacity}
                        </p>
                      </div>
                      <div className="flex shrink-0 gap-2">
                        <Button type="button" variant="outline" size="sm" onClick={() => setManagingBatch(batch)}>
                          Members
                        </Button>
                        <Button type="button" variant="outline" size="sm" onClick={() => toggleActive(batch)}>
                          {batch.isActive ? "Deactivate" : "Activate"}
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>
              )}

              <div className="space-y-2 rounded-md border border-dashed border-border p-3">
                <p className="text-sm font-medium">Add a batch</p>
                <input
                  aria-label="Batch name"
                  placeholder="e.g. Evening Badminton"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  className="h-10 w-full rounded-md border border-input bg-secondary/60 px-3 text-sm"
                />
                <div className="grid grid-cols-2 gap-2">
                  <select
                    aria-label="Plan"
                    value={planId}
                    onChange={(e) => setPlanId(e.target.value)}
                    className="h-10 rounded-md border border-input bg-secondary/60 px-3 text-sm"
                  >
                    <option value="">Select plan</option>
                    {plans.map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.name}
                      </option>
                    ))}
                  </select>
                  <select
                    aria-label="Sport"
                    value={facilitySportId}
                    onChange={(e) => {
                      setFacilitySportId(e.target.value);
                      setCourtId("");
                    }}
                    className="h-10 rounded-md border border-input bg-secondary/60 px-3 text-sm"
                  >
                    <option value="">Select sport</option>
                    {facilitySports.map((fs) => {
                      const s = sports.find((sp) => sp.id === fs.sportId);
                      return (
                        <option key={fs.id} value={fs.id}>
                          {fs.customSportName ?? s?.name ?? "Sport"}
                        </option>
                      );
                    })}
                  </select>
                </div>
                <select
                  aria-label="Court"
                  value={courtId}
                  onChange={(e) => setCourtId(e.target.value)}
                  disabled={!facilitySportId}
                  className="h-10 w-full rounded-md border border-input bg-secondary/60 px-3 text-sm disabled:opacity-50"
                >
                  <option value="">Select court</option>
                  {courtsForSport.map((a) => (
                    <option key={a.id} value={a.id}>
                      {a.name}
                    </option>
                  ))}
                </select>
                <div className="flex flex-wrap gap-2">
                  {DAYS.map((d) => (
                    <button
                      key={d.value}
                      type="button"
                      onClick={() => toggleDay(d.value)}
                      className={`h-8 rounded-md border px-2 text-xs font-medium ${
                        days.includes(d.value) ? "border-primary bg-primary text-primary-foreground" : "border-input bg-secondary/60"
                      }`}
                    >
                      {d.label}
                    </button>
                  ))}
                </div>
                <div className="grid grid-cols-3 gap-2">
                  <input aria-label="Start time" type="time" value={startTime} onChange={(e) => setStartTime(e.target.value)} className="h-10 rounded-md border border-input bg-secondary/60 px-3 text-sm" />
                  <input aria-label="End time" type="time" value={endTime} onChange={(e) => setEndTime(e.target.value)} className="h-10 rounded-md border border-input bg-secondary/60 px-3 text-sm" />
                  <input aria-label="Capacity" placeholder="Capacity" inputMode="numeric" value={capacity} onChange={(e) => setCapacity(e.target.value)} className="h-10 rounded-md border border-input bg-secondary/60 px-3 text-sm" />
                </div>
                {error && <p className="text-sm text-destructive">{error}</p>}
                <Button type="button" size="sm" onClick={addBatch} disabled={isSaving}>
                  {isSaving ? "Saving…" : "Add Batch"}
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>

      {managingBatch && (
        <BatchMembersDialog
          open={managingBatch !== null}
          onOpenChange={(open) => !open && setManagingBatch(null)}
          facilityId={facilityId}
          batch={managingBatch}
        />
      )}
    </>
  );
}