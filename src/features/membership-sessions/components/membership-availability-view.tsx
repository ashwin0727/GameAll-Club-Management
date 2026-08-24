"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { getFacilityService } from "@/services/facility";
import { getMembershipSessionService } from "@/services/membership-sessions";
import { computeSlotDisplayState, maxReleasable, maxRestorable, slotToCapacity } from "@/features/membership-sessions/capacity";
import type { MembershipSessionSlot } from "@/features/membership-sessions/types";
import { MembershipBatchesDialog } from "@/features/membership-sessions/components/membership-batches-dialog";
import { BookGuestSlotDialog } from "@/features/membership-sessions/components/book-guest-slot-dialog";
import { ServiceError } from "@/services/shared/service-error";

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

function stateBadge(state: ReturnType<typeof computeSlotDisplayState>): { label: string; tone: "success" | "warning" | "destructive" | "secondary" } {
  switch (state) {
    case "MEMBERSHIP_ALLOCATED":
      return { label: "Membership reserved", tone: "secondary" };
    case "MEMBERSHIP_PARTIALLY_USED":
      return { label: "Membership session", tone: "secondary" };
    case "MEMBERSHIP_FULL":
      return { label: "Membership full", tone: "success" };
    case "RELEASED_FOR_GUEST":
      return { label: "Guest slots available", tone: "warning" };
    case "GUEST_BOOKED":
      return { label: "Fully booked", tone: "destructive" };
  }
}

export function MembershipAvailabilityView() {
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [date, setDate] = useState(todayIso());
  const [slots, setSlots] = useState<MembershipSessionSlot[] | null>(null);
  const [batchesOpen, setBatchesOpen] = useState(false);
  const [guestSlot, setGuestSlot] = useState<MembershipSessionSlot | null>(null);
  const [pendingKey, setPendingKey] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

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

  async function release(slot: MembershipSessionSlot, count: number) {
    const key = `release-${slot.batchId}`;
    setPendingKey(key);
    setError(null);
    try {
      // A session that has never been touched has no id yet — releasing
      // capacity is itself the first action, so materialize it first the
      // same way book_membership_slot/book_guest_slot do internally.
      const sessionId = slot.sessionId ?? (await getMembershipSessionService().getOrCreateSession(slot.batchId, slot.sessionDate));
      await getMembershipSessionService().releaseCapacity(sessionId, count);
      reload();
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to release capacity.");
    } finally {
      setPendingKey(null);
    }
  }

  async function restore(slot: MembershipSessionSlot, count: number) {
    if (!slot.sessionId) return;
    const key = `restore-${slot.batchId}`;
    setPendingKey(key);
    setError(null);
    try {
      await getMembershipSessionService().restoreCapacity(slot.sessionId, count);
      reload();
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to restore capacity.");
    } finally {
      setPendingKey(null);
    }
  }

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

      {error && <p className="text-sm text-destructive">{error}</p>}

      {slots === null ? (
        <Skeleton className="h-64 w-full rounded-xl" />
      ) : slots.length === 0 ? (
        <div className="rounded-lg border border-dashed border-border p-8 text-center text-sm text-muted-foreground">
          No membership sessions today.
        </div>
      ) : (
        <div className="space-y-3">
          {slots.map((slot) => {
            const capacity = slotToCapacity(slot);
            const state = computeSlotDisplayState(capacity);
            const badge = stateBadge(state);
            const releasable = maxReleasable(capacity);
            const restorable = maxRestorable(capacity);
            const key = `${slot.batchId}-${slot.sessionDate}`;

            return (
              <div key={key} className="rounded-lg border border-border p-4">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div>
                    <p className="font-medium">
                      {slot.courtName} · {slot.startTime.slice(0, 5)}–{slot.endTime.slice(0, 5)}
                    </p>
                    <p className="text-sm text-muted-foreground">
                      {slot.batchName} · {slot.sportName}
                    </p>
                  </div>
                  <Badge variant={badge.tone}>{badge.label}</Badge>
                </div>

                <div className="mt-3 grid grid-cols-2 gap-2 text-sm sm:grid-cols-5">
                  <div className="rounded-md bg-secondary/50 p-2">
                    <p className="text-xs text-muted-foreground">Capacity</p>
                    <p className="font-semibold">{capacity.capacity}</p>
                  </div>
                  <div className="rounded-md bg-secondary/50 p-2">
                    <p className="text-xs text-muted-foreground">Member Booked</p>
                    <p className="font-semibold">{capacity.memberBookedCount}</p>
                  </div>
                  <div className="rounded-md bg-secondary/50 p-2">
                    <p className="text-xs text-muted-foreground">Unused</p>
                    <p className="font-semibold">{capacity.unusedCapacity}</p>
                  </div>
                  <div className="rounded-md bg-secondary/50 p-2">
                    <p className="text-xs text-muted-foreground">Released</p>
                    <p className="font-semibold">{capacity.releasedCapacity}</p>
                  </div>
                  <div className="rounded-md bg-secondary/50 p-2">
                    <p className="text-xs text-muted-foreground">Guest Available</p>
                    <p className="font-semibold">{capacity.guestAvailableCapacity}</p>
                  </div>
                </div>

                {capacity.releasedCapacity === 0 && capacity.guestAvailableCapacity === 0 && capacity.unusedCapacity === 0 && capacity.memberBookedCount === 0 && (
                  <p className="mt-2 text-xs text-muted-foreground">This time is currently reserved for members.</p>
                )}

                <div className="mt-3 flex flex-wrap gap-2">
                  <Button
                    type="button"
                    size="sm"
                    variant="outline"
                    disabled={releasable === 0 || pendingKey === `release-${slot.batchId}`}
                    onClick={() => release(slot, releasable)}
                  >
                    Release {releasable > 0 ? releasable : ""} Unused Slot{releasable === 1 ? "" : "s"}
                  </Button>
                  <Button
                    type="button"
                    size="sm"
                    variant="outline"
                    disabled={restorable === 0 || pendingKey === `restore-${slot.batchId}`}
                    onClick={() => restore(slot, restorable)}
                  >
                    Restore {restorable > 0 ? restorable : ""} Released Slot{restorable === 1 ? "" : "s"}
                  </Button>
                  <Button
                    type="button"
                    size="sm"
                    disabled={capacity.guestAvailableCapacity === 0}
                    onClick={() => setGuestSlot(slot)}
                  >
                    {capacity.guestAvailableCapacity > 0 ? "Book Guest Slot" : "Guest Booking Unavailable"}
                  </Button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      <MembershipBatchesDialog open={batchesOpen} onOpenChange={setBatchesOpen} facilityId={facilityId} />

      {guestSlot && (
        <BookGuestSlotDialog
          open={guestSlot !== null}
          onOpenChange={(open) => !open && setGuestSlot(null)}
          facilityId={facilityId}
          slot={guestSlot}
          onBooked={() => {
            setGuestSlot(null);
            reload();
          }}
        />
      )}
    </div>
  );
}