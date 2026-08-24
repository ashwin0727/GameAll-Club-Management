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