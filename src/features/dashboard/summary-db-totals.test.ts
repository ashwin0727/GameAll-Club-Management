import { describe, expect, it } from "vitest";
import { buildRevenueOverview, buildRevenueOverviewFromTotals, computeUtilization } from "@/features/dashboard/summary";
import type { OperatingDay } from "@/features/operating-hours/types";

// The database now adds up the revenue chart and booked court time. These tests prove the screen shows the same thing whether
// it is built from every payment/booking row (the old way) or from the database's totals (the new way).

describe("revenue chart from database totals", () => {
  const now = new Date(2026, 9, 29, 12, 0, 0); // 29 Oct 2026, local
  const at = (m: number, d: number, h = 10) => new Date(2026, m, d, h).toISOString();
  const payments = [
    { status: "paid", amount_inr: 1000, created_at: at(9, 10), booking_id: "b1" },
    { status: "paid", amount_inr: 500, created_at: at(9, 11), booking_id: "b2" },
    { status: "paid", amount_inr: 900, created_at: at(9, 15), membership_id: "m1" },
    { status: "paid", amount_inr: 400, created_at: at(9, 15) },
    { status: "paid", amount_inr: 250, created_at: at(9, 20), coaching_enrollment_id: "c1" },
    { status: "created", amount_inr: 300, created_at: at(9, 12), booking_id: "b1" },
    { status: "paid", amount_inr: 700, created_at: at(8, 15), booking_id: "b3" },
  ];

  it("gives the same panel as the row-by-row calculation", () => {
    const viaRows = buildRevenueOverview(payments, now, 0);
    const viaTotals = buildRevenueOverviewFromTotals(
      {
        totalInr: 3050,
        previousTotalInr: 700,
        byDay: { "2026-10-10": 1000, "2026-10-11": 500, "2026-10-15": 1300, "2026-10-20": 250 },
        breakdown: {
          bookings: { count: 2, inr: 1500 },
          memberships: { count: 1, inr: 900 },
          coaching: { count: 1, inr: 250 },
          other: { count: 1, inr: 400 },
        },
      },
      now,
      0,
    );
    expect(viaTotals).toEqual(viaRows);
  });

  it("draws a flat, zero-filled month when nothing was received", () => {
    const viaRows = buildRevenueOverview([], now, 1);
    const empty = { count: 0, inr: 0 };
    const viaTotals = buildRevenueOverviewFromTotals(
      { totalInr: 0, previousTotalInr: 0, byDay: {}, breakdown: { bookings: empty, memberships: empty, coaching: empty, other: empty } },
      now,
      1,
    );
    expect(viaTotals).toEqual(viaRows);
  });
});

describe("utilization from database minutes", () => {
  const openAllDay: OperatingDay[] = [0, 1, 2, 3, 4, 5, 6].map((dayOfWeek) => ({
    dayOfWeek: dayOfWeek as OperatingDay["dayOfWeek"],
    isClosed: false,
    is24Hours: false,
    slots: [{ startTime: "06:00", endTime: "22:00" }],
  })) as OperatingDay[];
  const base = {
    playingAreas: [
      { id: "c1", name: "Court 1", facilitySportId: "fs1" },
      { id: "c2", name: "Court 2", facilitySportId: "fs1" },
    ],
    facilitySports: [{ id: "fs1", sportId: "s1" }],
    sports: [{ id: "s1", name: "Badminton" }],
    facilityOperatingDays: openAllDay,
    period: { from: new Date(2026, 9, 5).toISOString(), to: new Date(2026, 9, 7).toISOString() },
  };

  it("matches the booking-by-booking calculation", () => {
    const viaRows = computeUtilization({
      ...base,
      bookings: [
        { playingAreaId: "c1", startTime: new Date(2026, 9, 5, 10).toISOString(), endTime: new Date(2026, 9, 5, 12).toISOString(), status: "confirmed" },
        { playingAreaId: "c1", startTime: new Date(2026, 9, 6, 18).toISOString(), endTime: new Date(2026, 9, 6, 19).toISOString(), status: "confirmed" },
        { playingAreaId: "c2", startTime: new Date(2026, 9, 6, 8).toISOString(), endTime: new Date(2026, 9, 6, 9, 30).toISOString(), status: "confirmed" },
        { playingAreaId: "c2", startTime: new Date(2026, 9, 6, 9).toISOString(), endTime: new Date(2026, 9, 6, 11).toISOString(), status: "cancelled" },
      ],
    });
    const viaMinutes = computeUtilization({ ...base, bookings: [], bookedMinutesByArea: new Map([["c1", 180], ["c2", 90]]) });
    expect(viaMinutes).toEqual(viaRows);
  });

  it("ignores the booking list when minutes are given", () => {
    const u = computeUtilization({
      ...base,
      bookings: [{ playingAreaId: "c1", startTime: new Date(2026, 9, 5, 10).toISOString(), endTime: new Date(2026, 9, 5, 12).toISOString(), status: "confirmed" }],
      bookedMinutesByArea: new Map(),
    });
    expect(u.overallPercent).toBe(0);
  });
});
