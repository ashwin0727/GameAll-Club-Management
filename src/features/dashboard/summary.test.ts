import { describe, expect, it } from "vitest";
import {
  bookingDurationMinutes,
  buildAttentionItems,
  buildRevenueOverview,
  buildRevenueTrend,
  countActiveMemberships,
  countPaidGuestBookings,
  buildScheduleTimeline,
  computeKpiValue,
  computeUtilization,
  computeUtilizationPercent,
  operatingMinutesForDay,
  resolveDateRange,
  summarizeMemberships,
  sumPaidRevenueInr,
  summarizePayments,
  toUtilizationBookings,
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

describe("toUtilizationBookings (membership session usage feeds utilization, allocation alone does not)", () => {
  it("converts a confirmed-usage session into a synthetic booking spanning its full duration", () => {
    const [booking] = toUtilizationBookings([
      { courtId: "court-1", sessionDate: "2026-08-24", startTime: "18:00:00", endTime: "19:00:00" },
    ]);
    expect(booking).toMatchObject({ playingAreaId: "court-1", status: "confirmed" });
    expect(bookingDurationMinutes(booking!.startTime, booking!.endTime)).toBe(60);
  });

  it("occupies the court once per session regardless of how many members/guests are in it", () => {
    // get_membership_utilization_sessions already dedupes to one row per
    // session with any confirmed booking — the conversion must not
    // multiply that by headcount.
    const result = toUtilizationBookings([
      { courtId: "court-1", sessionDate: "2026-08-24", startTime: "18:00:00", endTime: "19:00:00" },
    ]);
    expect(result).toHaveLength(1);
  });

  it("merges into computeUtilization exactly like a real booking — spec's 80% partial-release scenario", () => {
    const period = { from: "2026-08-24T00:00:00.000Z", to: "2026-08-25T00:00:00.000Z" };
    // Capacity 5, 3 members + 1 guest confirmed (1 released slot still unused) — the
    // session occupies its single 1h slot out of a 5h open window = 20% for
    // that court, distinct from "5/5 allocated" or headcount-based math.
    const membershipBookings = toUtilizationBookings([
      { courtId: "court-1", sessionDate: "2026-08-24", startTime: "18:00:00", endTime: "19:00:00" },
    ]);
    const result = computeUtilization({
      playingAreas: [{ id: "court-1", name: "Court 1", facilitySportId: "fs-1" }],
      facilitySports: [{ id: "fs-1", sportId: "sport-1" }],
      sports: [{ id: "sport-1", name: "Badminton" }],
      facilityOperatingDays: [openDay(1, "18:00", "23:00")], // 5h open
      bookings: [...membershipBookings],
      period,
    });
    expect(result.overallPercent).toBe(20);
  });

  it("contributes zero occupied time when nothing has actually been confirmed (allocation ≠ usage)", () => {
    const period = { from: "2026-08-24T00:00:00.000Z", to: "2026-08-25T00:00:00.000Z" };
    const result = computeUtilization({
      playingAreas: [{ id: "court-1", name: "Court 1", facilitySportId: "fs-1" }],
      facilitySports: [{ id: "fs-1", sportId: "sport-1" }],
      sports: [{ id: "sport-1", name: "Badminton" }],
      facilityOperatingDays: [openDay(1, "18:00", "19:00")],
      bookings: [], // no membership session row is fed in when nobody confirmed
      period,
    });
    expect(result.overallPercent).toBe(0);
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

describe("buildScheduleTimeline", () => {
  const areas = [
    { id: "court-1", name: "Court 1", facilitySportId: "fs-1" },
    { id: "court-2", name: "Court 2", facilitySportId: "fs-1" },
  ];
  const facilitySports = [{ id: "fs-1", sportId: "sport-1" }];
  const sports = [{ id: "sport-1", name: "Badminton" }];
  // 2026-08-24 is a Monday; local hours are used, so build times off the local Date constructor.
  const local = (h: number, m = 0) => new Date(2026, 7, 24, h, m).toISOString();

  it("derives the hour axis from today's operating slots and positions a block by its real time", () => {
    const timeline = buildScheduleTimeline({
      playingAreas: areas,
      facilitySports,
      sports,
      facilityOperatingDays: [openDay(1, "06:00", "22:00")],
      bookings: [
        { id: "b1", playingAreaId: "court-1", startTime: local(17), endTime: local(18), status: "confirmed", type: "MEMBER", label: "Arun" },
      ],
      now: new Date(2026, 7, 24, 10),
    });
    expect(timeline.startHour).toBe(6);
    expect(timeline.endHour).toBe(22);
    expect(timeline.courts).toHaveLength(2);
    const court1 = timeline.courts.find((c) => c.courtId === "court-1")!;
    expect(court1.blocks).toHaveLength(1);
    expect(court1.blocks[0]).toMatchObject({ startMinute: 17 * 60, endMinute: 18 * 60, type: "MEMBER", label: "Arun", lane: 0 });
  });

  it("puts overlapping blocks in the same court on separate lanes", () => {
    const timeline = buildScheduleTimeline({
      playingAreas: [areas[0]!],
      facilitySports,
      sports,
      facilityOperatingDays: [openDay(1, "06:00", "22:00")],
      bookings: [
        { id: "a", playingAreaId: "court-1", startTime: local(17), endTime: local(19), status: "confirmed", type: "MEMBER", label: "A" },
        { id: "b", playingAreaId: "court-1", startTime: local(18), endTime: local(20), status: "confirmed", type: "GUEST", label: "B" },
      ],
      now: new Date(2026, 7, 24, 10),
    });
    const court1 = timeline.courts[0]!;
    expect(court1.laneCount).toBe(2);
    expect(court1.blocks.map((b) => b.lane).sort()).toEqual([0, 1]);
  });

  it("still renders every court on a default 6am-10pm axis when the facility has no operating hours today", () => {
    const closed = buildScheduleTimeline({
      playingAreas: areas,
      facilitySports,
      sports,
      facilityOperatingDays: [closedDay(1)],
      bookings: [],
      now: new Date(2026, 7, 24, 10),
    });
    expect(closed.courts).toHaveLength(2);
    expect(closed.startHour).toBe(6);
    expect(closed.endHour).toBe(22);
    expect(closed.courts.every((c) => c.blocks.length === 0)).toBe(true);
  });

  it("with no operating hours, still places bookings and fits the axis around them", () => {
    const timeline = buildScheduleTimeline({
      playingAreas: [areas[0]!],
      facilitySports,
      sports,
      facilityOperatingDays: [closedDay(1)],
      bookings: [{ id: "b", playingAreaId: "court-1", startTime: local(19), endTime: local(20), status: "confirmed", type: "GUEST", label: "Guest" }],
      now: new Date(2026, 7, 24, 10),
    });
    expect(timeline.courts[0]!.blocks).toHaveLength(1);
    expect(timeline.startHour).toBeLessThanOrEqual(19);
    expect(timeline.endHour).toBeGreaterThanOrEqual(20);
  });

  it("excludes cancelled bookings", () => {
    const open = buildScheduleTimeline({
      playingAreas: [areas[0]!],
      facilitySports,
      sports,
      facilityOperatingDays: [openDay(1, "06:00", "22:00")],
      bookings: [
        { id: "x", playingAreaId: "court-1", startTime: local(17), endTime: local(18), status: "cancelled", type: "MEMBER", label: "X" },
      ],
      now: new Date(2026, 7, 24, 10),
    });
    expect(open.courts[0]!.blocks).toEqual([]);
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
describe("buildRevenueTrend", () => {
  it("buckets paid revenue by local calendar day and zero-fills empty days", () => {
    const period = { from: new Date(2026, 7, 24).toISOString(), to: new Date(2026, 7, 27).toISOString() };
    const trend = buildRevenueTrend(
      [
        { status: "paid", amount_inr: 500, created_at: new Date(2026, 7, 24, 9).toISOString() },
        { status: "paid", amount_inr: 300, created_at: new Date(2026, 7, 24, 18).toISOString() },
        { status: "created", amount_inr: 999, created_at: new Date(2026, 7, 25, 10).toISOString() },
        { status: "paid", amount_inr: 200, created_at: new Date(2026, 7, 26, 10).toISOString() },
      ],
      period,
    );
    expect(trend).toEqual([
      { date: "2026-08-24", amountInr: 800 },
      { date: "2026-08-25", amountInr: 0 },
      { date: "2026-08-26", amountInr: 200 },
    ]);
  });
});

describe("dashboard KPI helpers (sport + date scoped)", () => {
  it("sumPaidRevenueInr sums only paid payments, and only in-scope ones when a sport is selected", () => {
    const payments = [
      { status: "paid", amount_inr: 500, booking_id: "b1", membership_id: null },
      { status: "paid", amount_inr: 300, booking_id: null, membership_id: "m1" },
      { status: "paid", amount_inr: 200, booking_id: "b2", membership_id: null },
      { status: "created", amount_inr: 999, booking_id: "b1", membership_id: null },
    ];
    expect(sumPaidRevenueInr(payments, null)).toBe(1000);
    expect(
      sumPaidRevenueInr(payments, { bookingIds: new Set(["b1"]), membershipIds: new Set(["m1"]) }),
    ).toBe(800);
  });

  it("countActiveMemberships counts active memberships, restricted to a sport's batch enrolment when given", () => {
    const memberships = [
      { id: "m1", status: "active" },
      { id: "m2", status: "active" },
      { id: "m3", status: "expired" },
    ];
    expect(countActiveMemberships(memberships, null)).toBe(2);
    expect(countActiveMemberships(memberships, new Set(["m1", "m3"]))).toBe(1);
  });

  it("countPaidGuestBookings counts only guest bookings that are paid and not cancelled", () => {
    expect(
      countPaidGuestBookings([
        { customerType: "GUEST", paymentStatus: "PAID", status: "confirmed" },
        { customerType: "GUEST", paymentStatus: "PENDING", status: "confirmed" },
        { customerType: "GUEST", paymentStatus: "PAID", status: "cancelled" },
        { customerType: "MEMBER", paymentStatus: "PAID", status: "confirmed" },
      ]),
    ).toBe(1);
  });
});

describe("buildRevenueOverview", () => {
  const now = new Date(2026, 7, 15); // 15 Aug 2026

  it("totals the selected month, compares to the previous month, and always returns a full day series", () => {
    const payments = [
      { status: "paid", amount_inr: 1000, created_at: new Date(2026, 6, 10).toISOString() }, // July
      { status: "paid", amount_inr: 400, created_at: new Date(2026, 7, 2).toISOString() }, // Aug
      { status: "paid", amount_inr: 600, created_at: new Date(2026, 7, 20).toISOString() }, // Aug
      { status: "created", amount_inr: 999, created_at: new Date(2026, 7, 5).toISOString() },
    ];
    const ov = buildRevenueOverview(payments, now, 0);
    expect(ov.monthLabel).toBe("Aug 2026");
    expect(ov.totalInr).toBe(1000);
    expect(ov.changePercent).toBe(0); // (1000 - 1000) / 1000
    expect(ov.points).toHaveLength(31);
    expect(ov.points.reduce((s, p) => s + p.amountInr, 0)).toBe(1000);
  });

  it("returns a zero-filled month (still non-empty) when there is no revenue", () => {
    const ov = buildRevenueOverview([], now, 1); // July 2026
    expect(ov.monthLabel).toBe("Jul 2026");
    expect(ov.totalInr).toBe(0);
    expect(ov.changePercent).toBeNull();
    expect(ov.points).toHaveLength(31);
    expect(ov.points.every((p) => p.amountInr === 0)).toBe(true);
  });
});

describe("buildRevenueOverview breakdown", () => {
  const now = new Date(2026, 7, 15);
  it("splits the month's paid revenue into bookings / memberships / other, coaching stays unavailable", () => {
    const ov = buildRevenueOverview(
      [
        { status: "paid", amount_inr: 400, created_at: new Date(2026, 7, 2).toISOString(), booking_id: "b1" },
        { status: "paid", amount_inr: 100, created_at: new Date(2026, 7, 3).toISOString(), booking_id: "b2" },
        { status: "paid", amount_inr: 600, created_at: new Date(2026, 7, 10).toISOString(), membership_id: "m1" },
        { status: "paid", amount_inr: 50, created_at: new Date(2026, 7, 12).toISOString() },
      ],
      now,
      0,
    );
    const by = Object.fromEntries(ov.breakdown.map((s) => [s.key, s]));
    expect(by.bookings).toMatchObject({ amountInr: 500, count: 2 });
    expect(by.memberships).toMatchObject({ amountInr: 600, count: 1 });
    expect(by.other).toMatchObject({ amountInr: 50 });
    expect(by.coaching).toMatchObject({ amountInr: 0, unavailable: true });
  });
});
