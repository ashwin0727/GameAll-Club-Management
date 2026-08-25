"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { getMembershipSessionService } from "@/services/membership-sessions";
import { computeSlotDisplayState, maxReleasable, maxRestorable, slotToCapacity } from "@/features/membership-sessions/capacity";
import type { MembershipSessionSlot } from "@/features/membership-sessions/types";
import { BookGuestSlotDialog } from "@/features/membership-sessions/components/book-guest-slot-dialog";
import { ServiceError } from "@/services/shared/service-error";

/**
 * The single membership-slot presentation, shared by the dedicated
 * Membership Sessions page and the Bookings grid's membership-protected
 * cells — one place owns "what does this state look like", so the two
 * surfaces can never drift out of sync (spec: "the same availability state
 * must be reflected consistently across Web/Flutter/Booking/Availability").
 *
 * Never renders a bare "disabled"/"unavailable" cell — every state explains
 * what's protected, what's used, what's unused, and what action (if any)
 * the owner can take right now.
 */
export function MembershipSlotCard({
  facilityId,
  slot,
  onChanged,
}: {
  facilityId: string;
  slot: MembershipSessionSlot;
  onChanged: () => void;
}) {
  const [guestSlotOpen, setGuestSlotOpen] = useState(false);
  const [pending, setPending] = useState<"release" | "restore" | null>(null);
  const [error, setError] = useState<string | null>(null);

  const capacity = slotToCapacity(slot);
  const state = computeSlotDisplayState(capacity);
  const releasable = maxReleasable(capacity);
  const restorable = maxRestorable(capacity);

  async function release(count: number) {
    setPending("release");
    setError(null);
    try {
      const sessionId = slot.sessionId ?? (await getMembershipSessionService().getOrCreateSession(slot.batchId, slot.sessionDate));
      await getMembershipSessionService().releaseCapacity(sessionId, count);
      onChanged();
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to release capacity.");
    } finally {
      setPending(null);
    }
  }

  async function restore(count: number) {
    if (!slot.sessionId) return;
    setPending("restore");
    setError(null);
    try {
      await getMembershipSessionService().restoreCapacity(slot.sessionId, count);
      onChanged();
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to restore capacity.");
    } finally {
      setPending(null);
    }
  }

  let emoji: string;
  let title: string;
  let tone: "success" | "warning" | "destructive" | "secondary";
  switch (state) {
    case "MEMBERSHIP_ALLOCATED":
    case "MEMBERSHIP_PARTIALLY_USED":
      emoji = "🔒";
      title = "Membership Protected";
      tone = "secondary";
      break;
    case "MEMBERSHIP_FULL":
      emoji = "🔒";
      title = "Membership Full";
      tone = "secondary";
      break;
    case "RELEASED_FOR_GUEST":
      emoji = "🟢";
      title = capacity.guestBookedCount === 0 ? "Guest Capacity Released" : `${capacity.guestAvailableCapacity} Guest Slot${capacity.guestAvailableCapacity === 1 ? "" : "s"} Available`;
      tone = "warning";
      break;
    case "GUEST_BOOKED":
      emoji = "🔴";
      title = "Guest Capacity Full";
      tone = "destructive";
      break;
  }

  return (
    <div className="rounded-lg border border-border p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <p className="font-medium">
            {slot.courtName} · {slot.sportName} · {slot.startTime.slice(0, 5)}–{slot.endTime.slice(0, 5)}
          </p>
          <p className="text-sm text-muted-foreground">{slot.batchName}</p>
        </div>
        <Badge variant={tone}>
          {emoji} {title}
        </Badge>
      </div>

      <p className="mt-2 text-sm">
        {capacity.memberBookedCount} / {capacity.capacity} members using
        {capacity.releasedCapacity > 0 && (
          <>
            {" "}
            · {capacity.guestBookedCount} / {capacity.releasedCapacity} guest slots used
          </>
        )}
      </p>

      {state === "MEMBERSHIP_FULL" && <p className="text-xs text-muted-foreground">Guest Play Unavailable — no unused capacity to release.</p>}
      {(state === "MEMBERSHIP_ALLOCATED" || state === "MEMBERSHIP_PARTIALLY_USED") && (
        <p className="text-xs text-muted-foreground">{capacity.unusedCapacity} unused membership slot{capacity.unusedCapacity === 1 ? "" : "s"}.</p>
      )}

      {error && <p className="mt-1 text-sm text-destructive">{error}</p>}

      <div className="mt-3 flex flex-wrap gap-2">
        {releasable > 0 && (
          <Button type="button" size="sm" variant="outline" disabled={pending !== null} onClick={() => release(releasable)}>
            {pending === "release" ? "Releasing…" : `Release ${releasable} for Guest Play`}
          </Button>
        )}
        {restorable > 0 && (
          <Button type="button" size="sm" variant="outline" disabled={pending !== null} onClick={() => restore(restorable)}>
            {pending === "restore" ? "Restoring…" : `Restore ${restorable} Slot${restorable === 1 ? "" : "s"}`}
          </Button>
        )}
        {capacity.releasedCapacity > 0 && (
          <Button type="button" size="sm" disabled={capacity.guestAvailableCapacity === 0} onClick={() => setGuestSlotOpen(true)}>
            {capacity.guestAvailableCapacity > 0 ? "Book Guest" : "Guest Capacity Full"}
          </Button>
        )}
      </div>

      {guestSlotOpen && (
        <BookGuestSlotDialog
          open={guestSlotOpen}
          onOpenChange={setGuestSlotOpen}
          facilityId={facilityId}
          slot={slot}
          onBooked={() => {
            setGuestSlotOpen(false);
            onChanged();
          }}
        />
      )}
    </div>
  );
}