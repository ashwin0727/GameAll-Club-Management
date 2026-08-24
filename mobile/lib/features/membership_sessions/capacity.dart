/// Single source of truth for turning the four raw counts (capacity,
/// releasedCapacity, memberBookedCount, guestBookedCount) into the derived
/// numbers every screen shows. Mirrors
/// src/features/membership-sessions/capacity.ts exactly — port every branch,
/// do not re-derive this arithmetic anywhere else. The backend
/// (get_membership_session_capacity / release_membership_capacity /
/// restore_membership_capacity) is the authority for what's actually
/// allowed to happen — this mirrors that same arithmetic client-side so the
/// UI can disable buttons and show live numbers without a round trip, but
/// every write still goes through the RPC.
library;

import '../../data/models/membership_session.dart';

MembershipSessionCapacity deriveMembershipCapacity({
  required int capacity,
  required int releasedCapacity,
  required int memberBookedCount,
  required int guestBookedCount,
}) {
  final unusedCapacity = capacity - memberBookedCount;
  final guestAvailableCapacity = releasedCapacity - guestBookedCount;
  return MembershipSessionCapacity(
    capacity: capacity,
    releasedCapacity: releasedCapacity,
    memberBookedCount: memberBookedCount,
    guestBookedCount: guestBookedCount,
    unusedCapacity: unusedCapacity,
    guestAvailableCapacity: guestAvailableCapacity,
  );
}

/// How many more slots the owner is allowed to release right now (never negative).
int maxReleasable(MembershipSessionCapacity capacity) {
  final value = capacity.unusedCapacity - capacity.releasedCapacity;
  return value < 0 ? 0 : value;
}

/// How many released slots the owner is allowed to restore right now (never
/// negative) — capped by what guests haven't already booked.
int maxRestorable(MembershipSessionCapacity capacity) {
  final value = capacity.releasedCapacity - capacity.guestBookedCount;
  return value < 0 ? 0 : value;
}

/// The display state a slot is in, per spec §7. Derived, never stored — a
/// pure function of the same four counts, evaluated in priority order (a
/// fully-booked membership with no release still reads as membershipFull,
/// not releasedForGuest, even if releasedCapacity is nonzero, because the
/// member side is what "full" means here).
enum MembershipSlotDisplayState {
  membershipAllocated,
  membershipPartiallyUsed,
  membershipFull,
  releasedForGuest,
  guestBooked,
}

MembershipSlotDisplayState computeSlotDisplayState(MembershipSessionCapacity capacity) {
  if (capacity.guestBookedCount >= capacity.releasedCapacity && capacity.releasedCapacity > 0) {
    return MembershipSlotDisplayState.guestBooked;
  }
  if (capacity.releasedCapacity > capacity.guestBookedCount) {
    return MembershipSlotDisplayState.releasedForGuest;
  }
  if (capacity.memberBookedCount >= capacity.capacity) {
    return MembershipSlotDisplayState.membershipFull;
  }
  if (capacity.memberBookedCount > 0) {
    return MembershipSlotDisplayState.membershipPartiallyUsed;
  }
  return MembershipSlotDisplayState.membershipAllocated;
}

MembershipSessionCapacity slotToCapacity(MembershipSessionSlot slot) {
  return deriveMembershipCapacity(
    capacity: slot.capacity,
    releasedCapacity: slot.releasedCapacity,
    memberBookedCount: slot.memberBookedCount,
    guestBookedCount: slot.guestBookedCount,
  );
}