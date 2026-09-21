import { describe, expect, it } from "vitest";
import type { CalEvent } from "@/features/bookings/calendar-events";
import { computeUtilization } from "@/features/bookings/calendar-events";
import {
  collectedMinor,
  countGuestBookings,
  countGuestEvents,
  daysBetween,
  formatUtilization,
  listKindToEventKind,
  percentChange,
  percentDelta,
  pointsDelta,
} from "@/features/bookings/booking-stats";
import type { BookingRow } from "@/features/bookings/list-utils";

const r = (over: Partial<BookingRow>): BookingRow => ({ kind: "GUEST", status: "confirmed", collectedMinor: 0, ...over }) as BookingRow;

describe("countGuestBookings", () => {
  const rows = [r({}), r({}), r({ status: "cancelled" }), r({ kind: "COACHING" }), r({ kind: "MEMBERSHIP" })];
  it("counts guest bookings only, leaving cancelled ones out", () => {
    expect(countGuestBookings(rows, false)).toBe(2);
  });
  it("counts the cancelled ones when the status filter asks for them", () => {
    expect(countGuestBookings(rows, true)).toBe(3);
  });
});

describe("collectedMinor", () => {
  it("adds up what was actually collected across bookings, memberships and coaching", () => {
    expect(collectedMinor([r({ collectedMinor: 60000 }), r({ kind: "COACHING", collectedMinor: 200000 }), r({ collectedMinor: 0 })])).toBe(260000);
  });
  it("is zero for nothing", () => {
    expect(collectedMinor([])).toBe(0);
  });
});

describe("countGuestEvents", () => {
  const ev = (kind: CalEvent["kind"], day: number) => ({ kind, start: new Date(2026, 8, day, 9) }) as CalEvent;
  it("counts guest events that start inside the period", () => {
    const events = [ev("GUEST", 21), ev("GUEST", 27), ev("GUEST", 28), ev("COACHING", 22), ev("SESSION", 22)];
    expect(countGuestEvents(events, new Date(2026, 8, 21), new Date(2026, 8, 28))).toBe(2);
  });
});

describe("listKindToEventKind", () => {
  it("maps a membership to its calendar kind and passes the others through", () => {
    expect(listKindToEventKind("MEMBERSHIP")).toBe("SESSION");
    expect(listKindToEventKind("GUEST")).toBe("GUEST");
    expect(listKindToEventKind("")).toBe("");
    expect(listKindToEventKind("EVENT")).toBe("EVENT");
  });
});

describe("change versus the previous period", () => {
  it("is relative, and null when there was nothing before to compare with", () => {
    expect(percentChange(112, 100)).toBeCloseTo(12);
    expect(percentChange(50, 100)).toBe(-50);
    expect(percentChange(5, 0)).toBeNull();
  });

  it("words a change with an arrow that points the way it went", () => {
    expect(percentDelta(112, 100, "vs last month")).toEqual({ text: "↑ 12% vs last month", tone: "up" });
    expect(percentDelta(78, 100, "vs last week")).toEqual({ text: "↓ 22% vs last week", tone: "down" });
    expect(percentDelta(100, 100, "vs last month")).toEqual({ text: "→ 0% vs last month", tone: "flat" });
    expect(percentDelta(3, 0, "vs last month")).toBeNull();
  });

  it("reports a percentage figure as points, not a percentage of a percentage", () => {
    expect(pointsDelta(78, 72, "vs last month")).toEqual({ text: "↑ 6 pts vs last month", tone: "up" });
    expect(pointsDelta(0.5, 1.2, "vs last month")).toEqual({ text: "↓ 0.7 pts vs last month", tone: "down" });
    expect(pointsDelta(0, 0, "vs last month")).toBeNull();
  });
});

describe("formatUtilization", () => {
  it("shows a decimal for small figures so light use isn't rounded away", () => {
    expect(formatUtilization(0.486)).toBe("0.5%");
    expect(formatUtilization(3.04)).toBe("3%");
    expect(formatUtilization(3.26)).toBe("3.3%");
  });
  it("uses whole numbers from 10% up", () => {
    expect(formatUtilization(10)).toBe("10%");
    expect(formatUtilization(79.6)).toBe("80%");
    expect(formatUtilization(100)).toBe("100%");
  });
  it("says <0.1% for a trace, and 0% only for nothing", () => {
    expect(formatUtilization(0.04)).toBe("<0.1%");
    expect(formatUtilization(0)).toBe("0%");
  });
});

describe("utilization over a chosen range", () => {
  const day24 = { dayOfWeek: 1, isClosed: false, is24Hours: true, slots: [] } as never;
  const week = daysBetween(new Date(2026, 8, 21), new Date(2026, 8, 27));

  it("spans exactly the selected days", () => {
    expect(week).toHaveLength(7);
    expect(daysBetween(new Date(2026, 8, 21), new Date(2026, 8, 21))).toHaveLength(1);
  });

  it("uses 24 hours per court per day when the facility is open round the clock: 2 courts x 7 days x 24 h", () => {
    const u = computeUtilization([], ["c1", "c2"], week, () => day24);
    expect(u.openMinutes).toBe(2 * 7 * 24 * 60);
  });

  it("scales with how many days are picked", () => {
    const three = daysBetween(new Date(2026, 8, 21), new Date(2026, 8, 23));
    expect(computeUtilization([], ["c1"], three, () => day24).openMinutes).toBe(3 * 24 * 60);
  });

  it("divides booked time by that open time", () => {
    const events = [{ courtId: "c1", kind: "GUEST", start: new Date(2026, 8, 22, 9), end: new Date(2026, 8, 22, 12) }] as CalEvent[];
    const u = computeUtilization(events, ["c1"], week, () => day24);
    expect(u.bookedMinutes).toBe(180);
    expect(u.percent).toBe(Math.round((180 / (7 * 1440)) * 100));
    expect(u.exactPercent).toBeCloseTo((180 / (7 * 1440)) * 100, 5);
  });
});
