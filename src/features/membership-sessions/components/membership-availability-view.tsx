"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { getFacilityService } from "@/services/facility";
import { getMembershipSessionService } from "@/services/membership-sessions";
import type { MembershipSessionSlot } from "@/features/membership-sessions/types";
import { MembershipBatchesDialog } from "@/features/membership-sessions/components/membership-batches-dialog";
import { MembershipSlotCard } from "@/features/membership-sessions/components/membership-slot-card";

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

export function MembershipAvailabilityView() {
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [date, setDate] = useState(todayIso());
  const [slots, setSlots] = useState<MembershipSessionSlot[] | null>(null);
  const [batchesOpen, setBatchesOpen] = useState(false);

  useEffect(() => {
    getFacilityService()
      .getFacility()
      .then((f) => setFacilityId(f?.id ?? null));
  }, []);

  function reload() {
    if (!facilityId) return;
    setSlots(null);
    getMembershipSessionService()
      .listSessionsForDate(facilityId, date)
      .then(setSlots)
      .catch(() => setSlots([]));
  }

  useEffect(() => {
    reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [facilityId, date]);

  if (!facilityId) {
    return <Skeleton className="h-64 w-full rounded-xl" />;
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <input
          aria-label="Date"
          type="date"
          value={date}
          onChange={(e) => setDate(e.target.value)}
          className="h-11 rounded-md border border-input bg-secondary/60 px-3 text-sm"
        />
        <Button type="button" variant="outline" onClick={() => setBatchesOpen(true)}>
          Manage Batches
        </Button>
      </div>

      {slots === null ? (
        <Skeleton className="h-64 w-full rounded-xl" />
      ) : slots.length === 0 ? (
        <div className="rounded-lg border border-dashed border-border p-8 text-center text-sm text-muted-foreground">
          No membership sessions today.
        </div>
      ) : (
        <div className="space-y-3">
          {slots.map((slot) => (
            <MembershipSlotCard key={`${slot.batchId}-${slot.sessionDate}`} facilityId={facilityId} slot={slot} onChanged={reload} />
          ))}
        </div>
      )}

      <MembershipBatchesDialog open={batchesOpen} onOpenChange={setBatchesOpen} facilityId={facilityId} />
    </div>
  );
}