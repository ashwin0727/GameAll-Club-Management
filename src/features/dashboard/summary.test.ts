import { describe, expect, it } from "vitest";
import {
  bookingDurationMinutes,
  buildAttentionItems,
  buildTodaysSchedule,
  computeKpiValue,
  computeUtilization,
  computeUtilizationPercent,
  operatingMinutesForDay,
  resolveDateRange,
  summarizeMemberships,
  summarizePayments,
} from "@/features/dashboard/summary";
import type { OperatingDay } from "@/features/operating-hours/types";

function openDay(dayOfWeek: OperatingDay["dayOfWeek"], startTime = "06:00", endTime = "23:00"): OperatingDay {
  return { dayOfWeek, isClosed: false, is24Hours: false, slots: [{ startTime, endTime, crossesMidnight: false, displayOrder: 0 }] };
}
function closedDay(dayOfWeek: OperatingDay["dayOfWeek"]): OperatingDay {
  return { dayOfWeek, isClosed: true, is24Hours: false, slots: [] };
}

describe("resolveDateRange (date range filtering)", () => {
  const now = new Date("2026-08-24T15:00:00.000Z"); // a Monday

  it("TODAY resolves to a 24h window with yesterday as the comparison period", () => {
    const { current, previous } = resolveDateRange("TODAY", now);
    expect(new Date(current.to).getTime() - new Date(current.from).getTime()).toBe(24 * 60 * 60 * 1000);
    expect(previous).not.toBeNull();
  });

  it("THIS_MONTH starts at the 1st of the current month", () => {
    const { current } = resolveDateRange("THIS_MONTH", now);
    expect(new Date(current.from).getDate()).toBe(1);
  });

  it("CUSTOM has no previous-period comparison", () => {
    const { previous } = resolveDateRange("CUSTOM", now, { from: "2026-08-01T00:00:00.000Z", to: "2026-08-10T00:00:00.000Z" });
    expect(previous).toBeNull();
  });

  it("CUSTOM without a range throws rather than silently guessing one", () => {
    expect(() => resolveDateRange("CUSTOM", now)).toThrow();
  });
});

describe("computeKpiValue (KPI calculation)", () => {
  it("computes a positive percent change", () => {
    const kpi = computeKpiValue(120, 100);
    expect(kpi.changePercent).toBe(20);
  });

  it("computes a negative percent change", () => {
    const kpi = computeKpiValue(80, 100);
    expect(kpi.changePercent).toBe(-20);
  });

  it("never divides by zero — a zero previous value has no percent change, not Infinity", () => {
    const kpi = computeKpiValue(50, 0);
    expect(kpi.changePercent).toBeNull();
  });

  it("has no comparison at all when there's no previous period (e.g. a custom range)", () => {
    const kpi = computeKpiValue(50, null);
    expect(kpi.changePercent).toBeNull();
    expect(kpi.previousValue).toBeNull();
  });
});

describe("operatingMinutesForDay + computeUtilizationPercent (utilization calculation)", () => {
  it("a closed day has zero available minutes", () => {
    expect(operatingMinutesForDay({ isClosed: true, is24Hours: false, slots: [] })).toBe(0);
  });

  it("a 24-hour day has 1440 available minutes", () => {
    expect(operatingMinutesForDay({ isClosed: false, is24Hours: true, slots: [] })).toBe(1440);
  });

  it("sums multiple slots, handling an overnight slot's wraparound", () => {
    const minutes = operatingMinutesForDay({
      isClosed: false,
      is24Hours: false,
      slots: [
        { startTime: "06:00", endTime: "12:00", crossesMidnight: false, displayOrder: 0 },
        { startTime: "22:00", endTime: "02:00", crossesMidnight: true, displayOrder: 1 },
      ],
    });
    expect(minutes).toBe(360 + 240); // 6h + 4h
  });

  it("utilization is 0% when there's no available time, not a division error", () => {
    expect(computeUtilizationPercent(60, 0)).toBe(0);
  });

  it("caps utilization at 100%", () => {
    expect(computeUtilizationPercent(200, 100)).toBe(100);
  });

  it("computes a normal percentage, rounded", () => {
    expect(computeUtilizationPercent(37, 60)).toBe(62);
  });
});

describe("bookingDurationMinutes", () => {
  it("computes duration between two ISO timestamps", () => {
    expect(bookingDurationMinutes("2026-08-24T06:00:00.000Z", "2026-08-24T07:30:00.000Z")).toBe(90);
  });
});

describe("computeUtilization (sport/court utilization + court/turf breakdown)", () => {
  const period = { from: "2026-08-24T00:00:00.000Z", to: "2026-08-25T00:00:00.000Z" }; // one Monday
  const facilityOperatingDays = [openDay(1, "06:00", "12:00")]; // Monday 6h open

  it("aggregates overall utilization across all courts, excluding cancelled bookings", () => {
    const result = computeUtilization({
      playingAreas: [{ id: "court-1", name: "Court 1", facilitySportId: "fs-1" }],
      facilitySports: [{ id: "fs-1", sportId: "sport-1" }],
      sports: [{ id: "sport-1", name: "Badminton" }],
      facilityOperatingDays,
      bookings: [
        { playingAreaId: "court-1", startTime: "2026-08-24T06:00:00.000Z", endTime: "2026-08-24T09:00:00.000Z", status: "confirmed" },
        { playingAreaId: "court-1", startTime: "2026-08-24T09:00:00.000Z", endTime: "2026-08-24T12:00:00.000Z", status: "cancelled" },
      ],
      period,
    });
    // 3h booked (confirmed only) of 6h available = 50%
    expect(result.overallPercent).toBe(50);
  });

  it("breaks utilization down per sport and per playing area", () => {
    const result = computeUtilization({
      playingAreas: [
        { id: "court-1", name: "Court 1", facilitySportId: "fs-1" },
        { id: "court-2", name: "Court 2", facilitySportId: "fs-1" },
      ],
      facilitySports: [{ id: "fs-1", sportId: "sport-1" }],
      sports: [{ id: "sport-1", name: "Badminton" }],
      facilityOperatingDays,
      bookings: [
        { playingAreaId: "court-1", startTime: "2026-08-24T06:00:00.000Z", endTime: "2026-08-24T12:00:00.000Z", status: "confirmed" },
      ],
      period,
    });
    expect(result.bySport[0]?.courts.find((c) => c.playingAreaId === "court-1")?.utilizationPercent).toBe(100);
    expect(result.bySport[0]?.courts.find((c) => c.playingAreaId === "court-2")?.utilizationPercent).toBe(0);
  });

  it("returns 0% overall when the facility has no operating hours configured", () => {
    const result = computeUtilization({
      playingAreas: [{ id: "court-1", name: "Court 1", facilitySportId: "fs-1" }],
      facilitySports: [{ id: "fs-1", sportId: "sport-1" }],
      sports: [{ id: "sport-1", name: "Badminton" }],
      facilityOperatingDays: [closedDay(1)],
      bookings: [],
      period,
    });
    expect(result.overallPercent).toBe(0);
  });
});

describe("buildTodaysSchedule", () => {
  it("marks a slot BOOKED only when an active booking overlaps it", () => {
    const now = new Date("2026-08-24T10:00:00.000Z"); // Monday
    const schedule = buildTodaysSchedule({
      playingAreas: [{ id: "court-1", name: "Court 1", facilitySportId: "fs-1" }],
      facilitySports: [{ id: "fs-1", sportId: "sport-1" }],
      sports: [{ id: "sport-1", name: "Badminton" }],
      facilityOperatingDays: [openDay(1, "06:00", "12:00")],
      bookings: [
        { playingAreaId: "court-1", startTime: "2026-08-24T06:00:00.000Z", endTime: "2026-08-24T07:00:00.000Z", status: "confirmed" },
      ],
      now,
    });
    expect(schedule).toHaveLength(1);
    expect(schedule[0]?.status).toBe("BOOKED");
  });

  it("marks a slot AVAILABLE when nothing is booked", () => {
    const now = new Date("2026-08-24T10:00:00.000Z");
    const schedule = buildTodaysSchedule({
      playingAreas: [{ id: "court-1", name: "Court 1", facilitySportId: "fs-1" }],
      facilitySports: [{ id: "fs-1", sportId: "sport-1" }],
      sports: [{ id: "sport-1", name: "Badminton" }],
      facilityOperatingDays: [openDay(1)],
      bookings: [],
      now,
    });
    expect(schedule[0]?.status).toBe("AVAILABLE");
  });

  it("is empty when the facility is closed today", () => {
    const now = new Date("2026-08-24T10:00:00.000Z");
    const schedule = buildTodaysSchedule({
      playingAreas: [{ id: "court-1", name: "Court 1", facilitySportId: "fs-1" }],
      facilitySports: [{ id: "fs-1", sportId: "sport-1" }],
      sports: [{ id: "sport-1", name: "Badminton" }],
      facilityOperatingDays: [closedDay(1)],
      bookings: [],
      now,
    });
    expect(schedule).toEqual([]);
  });
});

describe("summarizeMemberships (member count calculation)", () => {
  const now = new Date("2026-08-24T00:00:00.000Z");

  it("counts active, expired, expiring-soon, and new-this-month independently", () => {
    const result = summarizeMemberships(
      [
        { status: "active", end_date: "2026-08-26", created_at: "2026-08-01T00:00:00.000Z" }, // active, expiring soon, new this month
        { status: "active", end_date: "2026-12-01", created_at: "2026-01-01T00:00:00.000Z" }, // active, not expiring, not new
        { status: "expired", end_date: "2026-07-01", created_at: "2026-01-01T00:00:00.000Z" },
      ],
      now,
    );
    expect(result).toEqual({ active: 2, expiringSoon: 1, expired: 1, newThisMonth: 1 });
  });

  it("is all zero for an empty facility — a valid empty state, not an error", () => {
    expect(summarizeMemberships([], now)).toEqual({ active: 0, expiringSoon: 0, expired: 0, newThisMonth: 0 });
  });
});

describe("summarizePayments (payment status calculation)", () => {
  it("splits paid/created/refunded into collected/pending/refunds", () => {
    const result = summarizePayments([
      { status: "paid", amount_inr: 1000 },
      { status: "created", amount_inr: 500 },
      { status: "refunded", amount_inr: 200 },
      { status: "failed", amount_inr: 300 },
    ]);
    expect(result).toEqual({ collectedInr: 1000, pendingInr: 500, refundsInr: 200 });
  });

  it("does not assume every booking/payment is paid — a failed payment counts toward nothing", () => {
    const result = summarizePayments([{ status: "failed", amount_inr: 900 }]);
    expect(result).toEqual({ collectedInr: 0, pendingInr: 0, refundsInr: 0 });
  });
});

describe("buildAttentionItems (attention item generation, empty-state logic)", () => {
  it("generates no items when everything is healthy", () => {
    expect(buildAttentionItems({ membershipsExpiringSoon: 0, paymentsPendingInr: 0 })).toEqual([]);
  });

  it("generates an item only for conditions that are actually true", () => {
    const items = buildAttentionItems({ membershipsExpiringSoon: 3, paymentsPendingInr: 0 });
    expect(items).toHaveLength(1);
    expect(items[0]?.id).toBe("memberships-expiring");
  });

  it("generates one item per real condition when multiple apply", () => {
    const items = buildAttentionItems({ membershipsExpiringSoon: 2, paymentsPendingInr: 500 });
    expect(items.map((i) => i.id)).toEqual(["memberships-expiring", "payments-pending"]);
  });
});