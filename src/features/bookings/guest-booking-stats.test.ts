import { describe, expect, it } from "vitest";
import { buildGuestStats, countUpcoming, previousRange } from "@/features/bookings/guest-booking-stats";
import type { GuestBookingRow } from "@/features/bookings/types";

function row(over: Partial<GuestBookingRow> & { status: GuestBookingRow["status"] }): GuestBookingRow {
  return {
    bookingId: "b",
    code: "GBK0001",
    guestName: "Guest",
    guestPhone: null,
    sportName: "Badminton",
    courtName: "Court 1",
    startTime: new Date(2026, 8, 10, 9).toISOString(),
    endTime: new Date(2026, 8, 10, 10).toISOString(),
    partySize: 2,
    amountMinor: 30000,
    paidMinor: 0,
    outstandingMinor: 0,
    currency: "INR",
    paymentStatus: "PENDING",
    paymentMethod: null,
    source: "COURT",
    ...over,
  };
}

describe("previousRange", () => {
  it("is the stretch of the same length immediately before", () => {
    expect(previousRange("2026-09-08", "2026-09-14")).toEqual({ from: "2026-09-01", to: "2026-09-07" });
    expect(previousRange("2026-09-21", "2026-09-21")).toEqual({ from: "2026-09-20", to: "2026-09-20" });
  });
  it("crosses month boundaries", () => {
    expect(previousRange("2026-10-01", "2026-10-30")).toEqual({ from: "2026-09-01", to: "2026-09-30" });
  });
});

describe("buildGuestStats", () => {
  const current = [
    row({ status: "completed", paidMinor: 30000 }),
    row({ status: "completed", paidMinor: 60000 }),
    row({ status: "confirmed", paidMinor: 0 }),
    row({ status: "pending" }),
    row({ status: "cancelled" }),
  ];

  it("counts every booking in the range, cancelled ones included, by status", () => {
    const { summary } = buildGuestStats(current, []);
    expect(summary).toMatchObject({ total: 5, completed: 2, confirmed: 1, pending: 1, cancelled: 1 });
  });

  it("measures revenue as money collected, with the average over paid bookings only", () => {
    const { summary } = buildGuestStats(current, []);
    expect(summary.totalRevenueMinor).toBe(90000);
    expect(summary.avgPerBookingMinor).toBe(45000);
    expect(summary.highestBookingMinor).toBe(60000);
  });

  it("has a zero average and highest when nothing was collected", () => {
    const { summary } = buildGuestStats([row({ status: "confirmed" })], []);
    expect(summary).toMatchObject({ avgPerBookingMinor: 0, highestBookingMinor: 0, totalRevenueMinor: 0 });
  });

  it("compares with the previous period, and has no change when there was nothing before", () => {
    const previous = [row({ status: "completed", paidMinor: 45000 }), row({ status: "cancelled" }), row({ status: "confirmed" }), row({ status: "confirmed" })];
    const stats = buildGuestStats(current, previous);
    expect(stats.summary.totalChangePct).toBe(25); // 5 vs 4
    expect(stats.summary.revenueChangePct).toBe(100); // 90000 vs 45000
    expect(stats.previous).toEqual({ total: 4, completed: 1, cancelled: 1, revenueMinor: 45000 });
    expect(buildGuestStats(current, []).summary.totalChangePct).toBeNull();
  });

  it("makes a per-day collected trend, oldest first", () => {
    const day = (d: number, paid: number) =>
      row({ status: "completed", paidMinor: paid, startTime: new Date(2026, 8, d, 9).toISOString(), endTime: new Date(2026, 8, d, 10).toISOString() });
    const { summary } = buildGuestStats([day(12, 100), day(10, 200), day(10, 50)], []);
    expect(summary.trend).toEqual([
      { date: "2026-09-10", amountMinor: 250 },
      { date: "2026-09-12", amountMinor: 100 },
    ]);
  });

  it("is all zeros for an empty range", () => {
    const { summary } = buildGuestStats([], []);
    expect(summary).toMatchObject({ total: 0, totalRevenueMinor: 0, trend: [] });
  });
});

describe("countUpcoming", () => {
  const now = new Date(2026, 8, 21, 12);
  const at = (h: number, day = 21) => ({
    startTime: new Date(2026, 8, day, h).toISOString(),
    endTime: new Date(2026, 8, day, h + 1).toISOString(),
  });
  it("counts confirmed and pending bookings that haven't finished", () => {
    const rows = [
      row({ status: "confirmed", ...at(15) }),
      row({ status: "pending", ...at(9, 25) }),
      row({ status: "confirmed", ...at(8) }), // already over today
      row({ status: "cancelled", ...at(16) }),
      row({ status: "completed", ...at(17) }),
    ];
    expect(countUpcoming(rows, now)).toBe(2);
  });
  it("counts a booking that is in progress right now as still to come until it ends", () => {
    expect(countUpcoming([row({ status: "confirmed", ...at(11) , endTime: new Date(2026, 8, 21, 13).toISOString() })], now)).toBe(1);
  });
});
