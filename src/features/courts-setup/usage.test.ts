import { describe, expect, it } from "vitest";
import { describeCourtUsage } from "@/features/courts-setup/usage";

describe("describeCourtUsage", () => {
  it("lists only what is there, with the right singular and plural", () => {
    expect(
      describeCourtUsage({ bookings: 1, membershipBatches: 2, membershipGuestSlots: 0, coachingSessions: 3, coachingBatches: 1, total: 7 }),
    ).toBe("1 upcoming booking, 2 membership session batches, 3 upcoming coaching sessions, 1 coaching batch with students");
  });

  it("is empty when nothing is ahead", () => {
    expect(describeCourtUsage({ bookings: 0, membershipBatches: 0, membershipGuestSlots: 0, coachingSessions: 0, coachingBatches: 0, total: 0 })).toBe("");
  });
});
