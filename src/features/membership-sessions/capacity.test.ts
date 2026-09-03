import { describe, expect, it } from "vitest";
import { computeSlotDisplayState, deriveMembershipCapacity, maxReleasable, maxRestorable } from "./capacity";

describe("deriveMembershipCapacity", () => {
  it("computes unused and guest-available capacity from the four raw counts", () => {
    const capacity = deriveMembershipCapacity({ capacity: 5, releasedCapacity: 0, memberBookedCount: 3, guestBookedCount: 0 });
    expect(capacity.unusedCapacity).toBe(2);
    expect(capacity.guestAvailableCapacity).toBe(0);
  });

  it("distinguishes allocated capacity from actual usage — never conflates the two (spec §41)", () => {
    const capacity = deriveMembershipCapacity({ capacity: 5, releasedCapacity: 2, memberBookedCount: 3, guestBookedCount: 2 });
    expect(capacity.capacity).toBe(5);
    expect(capacity.memberBookedCount).toBe(3);
    expect(capacity.releasedCapacity).toBe(2);
    expect(capacity.guestBookedCount).toBe(2);
    expect(capacity.unusedCapacity).toBe(2);
    expect(capacity.guestAvailableCapacity).toBe(0);
  });
});

describe("maxReleasable", () => {
  it("is the unused capacity minus what's already released", () => {
    const capacity = deriveMembershipCapacity({ capacity: 5, releasedCapacity: 0, memberBookedCount: 3, guestBookedCount: 0 });
    expect(maxReleasable(capacity)).toBe(2);
  });

  it("is zero once every unused slot has been released", () => {
    const capacity = deriveMembershipCapacity({ capacity: 5, releasedCapacity: 2, memberBookedCount: 3, guestBookedCount: 0 });
    expect(maxReleasable(capacity)).toBe(0);
  });

  it("is zero when membership capacity is fully used (spec §10)", () => {
    const capacity = deriveMembershipCapacity({ capacity: 5, releasedCapacity: 0, memberBookedCount: 5, guestBookedCount: 0 });
    expect(maxReleasable(capacity)).toBe(0);
  });
});

describe("maxRestorable", () => {
  it("is the full released amount when no guest has booked yet", () => {
    const capacity = deriveMembershipCapacity({ capacity: 5, releasedCapacity: 2, memberBookedCount: 3, guestBookedCount: 0 });
    expect(maxRestorable(capacity)).toBe(2);
  });

  it("is reduced by however many guests already booked (spec §18/§19)", () => {
    const capacity = deriveMembershipCapacity({ capacity: 5, releasedCapacity: 2, memberBookedCount: 3, guestBookedCount: 1 });
    expect(maxRestorable(capacity)).toBe(1);
  });

  it("is zero once every released slot is guest-booked", () => {
    const capacity = deriveMembershipCapacity({ capacity: 5, releasedCapacity: 2, memberBookedCount: 3, guestBookedCount: 2 });
    expect(maxRestorable(capacity)).toBe(0);
  });
});

describe("computeSlotDisplayState", () => {
  it("is MEMBERSHIP_ALLOCATED when nothing has happened yet", () => {
    const capacity = deriveMembershipCapacity({ capacity: 5, releasedCapacity: 0, memberBookedCount: 0, guestBookedCount: 0 });
    expect(computeSlotDisplayState(capacity)).toBe("MEMBERSHIP_ALLOCATED");
  });

  it("is MEMBERSHIP_PARTIALLY_USED once some but not all members have booked", () => {
    const capacity = deriveMembershipCapacity({ capacity: 5, releasedCapacity: 0, memberBookedCount: 3, guestBookedCount: 0 });
    expect(computeSlotDisplayState(capacity)).toBe("MEMBERSHIP_PARTIALLY_USED");
  });

  it("is MEMBERSHIP_FULL once every capacity slot is member-booked", () => {
    const capacity = deriveMembershipCapacity({ capacity: 5, releasedCapacity: 0, memberBookedCount: 5, guestBookedCount: 0 });
    expect(computeSlotDisplayState(capacity)).toBe("MEMBERSHIP_FULL");
  });

  it("is RELEASED_FOR_GUEST once the owner releases capacity that hasn't all been guest-booked", () => {
    const capacity = deriveMembershipCapacity({ capacity: 5, releasedCapacity: 2, memberBookedCount: 3, guestBookedCount: 0 });
    expect(computeSlotDisplayState(capacity)).toBe("RELEASED_FOR_GUEST");
  });

  it("is GUEST_BOOKED once every released slot is taken by a guest", () => {
    const capacity = deriveMembershipCapacity({ capacity: 5, releasedCapacity: 2, memberBookedCount: 3, guestBookedCount: 2 });
    expect(computeSlotDisplayState(capacity)).toBe("GUEST_BOOKED");
  });
});
/**
 * The end-to-end scenario from the Membership Sessions spec (§36), walked
 * through as the counts change. The database is the authority for every one
 * of these rules; this pins the arithmetic the owner screens display, so a
 * change to the derivation can't silently disagree with the backend.
 *
 * Champz Turf · Badminton · Court 1 · Mon/Wed/Fri 6–7pm
 * Capacity 5 · 3 members assigned · 2 released for guest play.
 */
describe("spec §36 — Evening Badminton, end to end", () => {
  const session = (guestBookedCount: number, releasedCapacity = 2) =>
    deriveMembershipCapacity({
      capacity: 5,
      releasedCapacity,
      memberBookedCount: 3,
      guestBookedCount,
    });

  it("starts with two guest slots open and none protected beyond them", () => {
    const c = session(0);
    expect(c.unusedCapacity).toBe(2);
    expect(c.guestAvailableCapacity).toBe(2);
    expect(computeSlotDisplayState(c)).toBe("RELEASED_FOR_GUEST");
  });

  it("has one guest slot left after the first guest books", () => {
    const c = session(1);
    expect(c.guestAvailableCapacity).toBe(1);
    expect(computeSlotDisplayState(c)).toBe("RELEASED_FOR_GUEST");
  });

  it("closes to the public once both released slots are taken", () => {
    const c = session(2);
    expect(c.guestAvailableCapacity).toBe(0);
    expect(computeSlotDisplayState(c)).toBe("GUEST_BOOKED");
  });

  it("reopens a slot when a guest booking is cancelled", () => {
    // Cancelling returns capacity; it must not alter what the owner released.
    const c = session(1);
    expect(c.releasedCapacity).toBe(2);
    expect(c.guestAvailableCapacity).toBe(1);
  });

  it("lets the owner take back only the slot no guest holds", () => {
    expect(maxRestorable(session(1))).toBe(1);
  });

  it("refuses to take back slots two guests already hold", () => {
    // The owner cannot drop release 2 -> 0 with two confirmed bookings;
    // restore_membership_capacity raises, and the UI must not offer it.
    expect(maxRestorable(session(2))).toBe(0);
  });

  it("never offers to release more than the members leave unused", () => {
    // Capacity 5, three members: two spare, both already released.
    expect(maxReleasable(session(0))).toBe(0);
    // With only one released, one more may be.
    expect(maxReleasable(session(0, 1))).toBe(1);
  });

  it("offers nothing to release once a fourth and fifth member join", () => {
    const full = deriveMembershipCapacity({
      capacity: 5,
      releasedCapacity: 0,
      memberBookedCount: 5,
      guestBookedCount: 0,
    });
    expect(maxReleasable(full)).toBe(0);
    expect(computeSlotDisplayState(full)).toBe("MEMBERSHIP_FULL");
  });

  it("does not free a member's slot for guests when they simply don't turn up", () => {
    // Absence is not a release (spec §17): the counts are unchanged, so the
    // guest side stays exactly where the owner set it.
    const c = session(0);
    expect(c.guestAvailableCapacity).toBe(2);
    expect(c.unusedCapacity).toBe(2);
  });
});
