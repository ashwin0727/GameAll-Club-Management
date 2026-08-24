import type { MembershipSessionCapacity, MembershipSessionSlot } from "./types";

/**
 * Single source of truth for turning the four raw counts (capacity,
 * releasedCapacity, memberBookedCount, guestBookedCount) into the derived
 * numbers every screen shows. The backend (get_membership_session_capacity /
 * release_membership_capacity / restore_membership_capacity) is the
 * authority for what's actually allowed to happen — this mirrors that same
 * arithmetic client-side so the UI can disable buttons and show live
 * numbers without a round trip, but every write still goes through the RPC.
 */
export function deriveMembershipCapacity(counts: {
  capacity: number;
  releasedCapacity: number;
  memberBookedCount: number;
  guestBookedCount: number;
}): MembershipSessionCapacity {
  const unusedCapacity = counts.capacity - counts.memberBookedCount;
  const guestAvailableCapacity = counts.releasedCapacity - counts.guestBookedCount;
  return {
    capacity: counts.capacity,
    releasedCapacity: counts.releasedCapacity,
    memberBookedCount: counts.memberBookedCount,
    guestBookedCount: counts.guestBookedCount,
    unusedCapacity,
    guestAvailableCapacity,
  };
}

/** How many more slots the owner is allowed to release right now (never negative). */
export function maxReleasable(capacity: MembershipSessionCapacity): number {
  return Math.max(0, capacity.unusedCapacity - capacity.releasedCapacity);
}

/** How many released slots the owner is allowed to restore right now (never negative) — capped by what guests haven't already booked. */
export function maxRestorable(capacity: MembershipSessionCapacity): number {
  return Math.max(0, capacity.releasedCapacity - capacity.guestBookedCount);
}

/**
 * The display state a slot is in, per spec §7. Derived, never stored — a
 * pure function of the same four counts, evaluated in priority order (a
 * fully-booked membership with no release still reads as MEMBERSHIP_FULL,
 * not RELEASED_FOR_GUEST, even if released_capacity is nonzero, because the
 * member side is what "full" means here).
 */
export type MembershipSlotDisplayState =
  | "MEMBERSHIP_ALLOCATED"
  | "MEMBERSHIP_PARTIALLY_USED"
  | "MEMBERSHIP_FULL"
  | "RELEASED_FOR_GUEST"
  | "GUEST_BOOKED";

export function computeSlotDisplayState(capacity: MembershipSessionCapacity): MembershipSlotDisplayState {
  if (capacity.guestBookedCount >= capacity.releasedCapacity && capacity.releasedCapacity > 0) {
    return "GUEST_BOOKED";
  }
  if (capacity.releasedCapacity > capacity.guestBookedCount) {
    return "RELEASED_FOR_GUEST";
  }
  if (capacity.memberBookedCount >= capacity.capacity) {
    return "MEMBERSHIP_FULL";
  }
  if (capacity.memberBookedCount > 0) {
    return "MEMBERSHIP_PARTIALLY_USED";
  }
  return "MEMBERSHIP_ALLOCATED";
}

export function slotToCapacity(slot: MembershipSessionSlot): MembershipSessionCapacity {
  return deriveMembershipCapacity({
    capacity: slot.capacity,
    releasedCapacity: slot.releasedCapacity,
    memberBookedCount: slot.memberBookedCount,
    guestBookedCount: slot.guestBookedCount,
  });
}