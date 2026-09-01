import { describe, expect, it } from "vitest";
import { computeTodaysOperations, currentCourtStatus } from "@/features/bookings/operations";
import type { Booking } from "@/features/bookings/types";

const now = new Date(2026, 7, 23, 10, 0);

function booking(overrides: Partial<Booking> = {}): Booking {
  return {
    id: "b1",
    facilityId: "f1",
    courtId: "court-1",
    facilitySportId: "fs-1",
    memberId: null,
    customerType: "GUEST",
    guestPlayerId: null,
    guestName: "Uma",
    guestPhone: null,
    startTime: new Date(2026, 7, 23, 9, 0).toISOString(),
    endTime: new Date(2026, 7, 23, 10, 0).toISOString(),
    status: "confirmed",
    amountMinor: 50000,
    currency: "INR",
    paymentStatus: "PENDING",
    cancellationReason: null,
    notes: null,
    partySize: 1,
    paymentMethod: null,
    createdBy: "u1",
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    ...overrides,
  };
}

describe("computeTodaysOperations", () => {
  it("counts only live (pending/confirmed) bookings", () => {
    const bookings = [booking({ status: "cancelled" }), booking({ status: "confirmed" })];
    expect(computeTodaysOperations(bookings, now).totalBookings).toBe(1);
  });

  it("splits into upcoming vs currently occupied", () => {
    const occupied = booking({ startTime: new Date(2026, 7, 23, 9, 30).toISOString(), endTime: new Date(2026, 7, 23, 10, 30).toISOString() });
    const upcoming = booking({ startTime: new Date(2026, 7, 23, 11, 0).toISOString(), endTime: new Date(2026, 7, 23, 12, 0).toISOString() });
    const past = booking({ startTime: new Date(2026, 7, 23, 7, 0).toISOString(), endTime: new Date(2026, 7, 23, 8, 0).toISOString() });
    const summary = computeTodaysOperations([occupied, upcoming, past], now);
    expect(summary.currentlyOccupied).toBe(1);
    expect(summary.upcoming).toBe(1);
    expect(summary.totalBookings).toBe(3);
  });
});

describe("currentCourtStatus", () => {
  it("is available when nothing occupies the court right now", () => {
    expect(currentCourtStatus("court-1", [], now)).toEqual({ state: "available" });
  });

  it("is occupied when a live booking spans the current time", () => {
    const b = booking({ startTime: new Date(2026, 7, 23, 9, 30).toISOString(), endTime: new Date(2026, 7, 23, 10, 30).toISOString() });
    expect(currentCourtStatus("court-1", [b], now)).toEqual({ state: "occupied", booking: b });
  });

  it("ignores a cancelled booking even if its window covers now", () => {
    const b = booking({ status: "cancelled", startTime: new Date(2026, 7, 23, 9, 30).toISOString(), endTime: new Date(2026, 7, 23, 10, 30).toISOString() });
    expect(currentCourtStatus("court-1", [b], now)).toEqual({ state: "available" });
  });

  it("ignores bookings on a different court", () => {
    const b = booking({ courtId: "court-2", startTime: new Date(2026, 7, 23, 9, 30).toISOString(), endTime: new Date(2026, 7, 23, 10, 30).toISOString() });
    expect(currentCourtStatus("court-1", [b], now)).toEqual({ state: "available" });
  });
});