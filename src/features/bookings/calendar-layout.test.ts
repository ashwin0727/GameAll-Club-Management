import { describe, expect, it } from "vitest";
import type { CalEvent } from "@/features/bookings/calendar-events";
import {
  agendaDays,
  computeUtilization,
  dataRange,
  daysInRange,
  monthGridDays,
  rangeFor,
  rangeLabel,
  shiftAnchor,
  startOfWeek,
} from "@/features/bookings/calendar-events";
import { closedSpans, computeGridHours, layoutEvents, layoutWithOverflow } from "@/features/bookings/calendar-layout";

const DAY = new Date(2026, 8, 21); // Mon 21 Sep 2026

function ev(id: string, sh: number, sm: number, eh: number, em: number, courtId = "c1", kind: CalEvent["kind"] = "GUEST"): CalEvent {
  return {
    id,
    courtId,
    kind,
    title: id,
    subtitle: "",
    start: new Date(2026, 8, 21, sh, sm),
    end: new Date(2026, 8, 21, eh, em),
  };
}

const OPTS = { startMin: 6 * 60, endMin: 22 * 60, pxPerMin: 1, minHeightPx: 30 };

describe("layoutEvents", () => {
  it("places a block by its start and length within the grid window", () => {
    const [p] = layoutEvents([ev("a", 9, 0, 10, 0)], DAY, OPTS);
    expect(p).toMatchObject({ top: 180, height: 60, lane: 0, lanes: 1 });
  });

  it("splits overlapping bookings into side-by-side lanes", () => {
    const out = layoutEvents([ev("a", 9, 0, 10, 0), ev("b", 9, 30, 10, 30)], DAY, OPTS);
    expect(out.map((p) => [p.lane, p.lanes])).toEqual([
      [0, 2],
      [1, 2],
    ]);
  });

  it("gives back-to-back bookings a full lane each", () => {
    const out = layoutEvents([ev("a", 9, 0, 10, 0), ev("b", 10, 0, 11, 0)], DAY, OPTS);
    expect(out.map((p) => [p.lane, p.lanes])).toEqual([
      [0, 1],
      [0, 1],
    ]);
  });

  it("enforces a minimum height and lanes against the stretched block, not the raw one", () => {
    // 10:00-10:10 is drawn 30px (30 min) tall, so a 10:15 booking would overlap it visually.
    const out = layoutEvents([ev("a", 10, 0, 10, 10), ev("b", 10, 15, 11, 0)], DAY, OPTS);
    expect(out[0]!.height).toBe(30);
    expect(out.map((p) => p.lanes)).toEqual([2, 2]);
  });

  it("clips events to the grid window and drops ones fully outside it", () => {
    const out = layoutEvents([ev("early", 4, 0, 7, 0), ev("gone", 1, 0, 2, 0)], DAY, OPTS);
    expect(out).toHaveLength(1);
    expect(out[0]).toMatchObject({ top: 0, height: 60 });
  });
});

describe("court order and overflow", () => {
  const order = (id: string) => Number(id.slice(1)); // c1 -> 1, c2 -> 2 ...

  it("gives Court 1 the first lane and Court 2 the next, whatever order they arrive in", () => {
    const out = layoutEvents([ev("second", 9, 0, 10, 0, "c2"), ev("first", 9, 0, 10, 0, "c1")], DAY, { ...OPTS, courtOrder: order });
    const lane = Object.fromEntries(out.map((p) => [p.event.id, p.lane]));
    expect(lane).toEqual({ first: 0, second: 1 });
  });

  it("draws at most maxLanes blocks side by side and counts the rest", () => {
    const events = ["c1", "c2", "c3", "c4", "c5", "c6"].map((c) => ev(c, 9, 0, 10, 0, c));
    const { blocks, overflow } = layoutWithOverflow(events, DAY, { ...OPTS, courtOrder: order, maxLanes: 2 });
    expect(blocks.map((b) => b.event.id)).toEqual(["c1", "c2"]);
    expect(blocks.every((b) => b.lanes === 2)).toBe(true);
    expect(overflow).toHaveLength(1);
    expect(overflow[0]).toMatchObject({ count: 4, top: 180, bottom: 240 });
  });

  it("reports no overflow when everything fits", () => {
    const { overflow } = layoutWithOverflow([ev("a", 9, 0, 10, 0, "c1"), ev("b", 9, 0, 10, 0, "c2")], DAY, { ...OPTS, maxLanes: 2 });
    expect(overflow).toEqual([]);
  });
});

describe("computeGridHours", () => {
  it("spans the open windows", () => {
    expect(computeGridHours([{ startMin: 360, endMin: 1320 }], [], [DAY])).toEqual({ startHour: 6, endHour: 22 });
  });

  it("widens to fit an event outside opening hours", () => {
    const r = computeGridHours([{ startMin: 480, endMin: 1200 }], [ev("late", 21, 0, 23, 0)], [DAY]);
    expect(r).toEqual({ startHour: 8, endHour: 23 });
  });

  it("falls back when there is nothing to go on", () => {
    expect(computeGridHours([], [], [DAY])).toEqual({ startHour: 6, endHour: 22 });
  });
});

describe("closedSpans", () => {
  it("returns the gaps outside open windows", () => {
    expect(closedSpans([{ startMin: 480, endMin: 1200 }], 360, 1320)).toEqual([
      { startMin: 360, endMin: 480 },
      { startMin: 1200, endMin: 1320 },
    ]);
  });
});

describe("ranges", () => {
  it("weeks start on Monday", () => {
    expect(startOfWeek(new Date(2026, 8, 20)).getDate()).toBe(14); // Sun 20 -> Mon 14
    expect(startOfWeek(DAY).getDate()).toBe(21);
  });

  it("covers day, week and month as [from, to)", () => {
    expect(rangeFor("day", DAY).to.getDate()).toBe(22);
    expect(daysInRange("week", DAY)).toHaveLength(7);
    expect(daysInRange("month", DAY)).toHaveLength(30);
  });

  it("shifts by the view's own unit and clamps month-end days", () => {
    expect(shiftAnchor("week", DAY, 1).getDate()).toBe(28);
    expect(shiftAnchor("month", new Date(2026, 0, 31), 1).getDate()).toBe(28); // Jan 31 -> Feb 28
  });

  it("labels each view", () => {
    expect(rangeLabel("day", DAY)).toBe("Mon, 21 Sep 2026");
    expect(rangeLabel("week", DAY)).toBe("21 – 27 Sep 2026");
    expect(rangeLabel("month", DAY)).toBe("September 2026");
  });

  it("loads the whole month grid, so neighbouring-month days have their items", () => {
    const r = dataRange("month", DAY);
    expect(r.from.getDay()).toBe(1);
    expect(r.from.getTime()).toBeLessThanOrEqual(new Date(2026, 8, 1).getTime());
    expect(r.to.getTime()).toBeGreaterThanOrEqual(new Date(2026, 9, 1).getTime());
    expect(dataRange("week", DAY)).toEqual(rangeFor("week", DAY));
  });

  it("pads the month grid to whole Monday-first weeks", () => {
    const days = monthGridDays(DAY);
    expect(days.length % 7).toBe(0);
    expect(days[0]!.getDay()).toBe(1);
  });
});

describe("agenda", () => {
  it("covers the same period as Month, but exactly the month rather than the whole grid", () => {
    expect(rangeFor("agenda", DAY)).toEqual(rangeFor("month", DAY));
    expect(dataRange("agenda", DAY)).toEqual(rangeFor("month", DAY));
    expect(daysInRange("agenda", DAY)).toHaveLength(30);
    expect(rangeLabel("agenda", DAY)).toBe("September 2026");
    expect(shiftAnchor("agenda", DAY, 1).getMonth()).toBe(9);
  });

  it("lists only the days that have something, by time then court", () => {
    const order = (id: string) => (id === "c1" ? 0 : 1);
    const d = (day: number, h: number) => new Date(2026, 8, day, h);
    const events = [
      { id: "late", courtId: "c1", start: d(22, 18), end: d(22, 19) },
      { id: "c2", courtId: "c2", start: d(22, 9), end: d(22, 10) },
      { id: "c1", courtId: "c1", start: d(22, 9), end: d(22, 10) },
      { id: "other", courtId: "c1", start: d(25, 9), end: d(25, 10) },
    ] as CalEvent[];
    const groups = agendaDays(events, daysInRange("agenda", DAY), order);
    expect(groups.map((g) => g.day.getDate())).toEqual([22, 25]);
    expect(groups[0]!.events.map((e) => e.id)).toEqual(["c1", "c2", "late"]);
  });
});

describe("computeUtilization", () => {
  const openDay = { dayOfWeek: 1 as const, isClosed: false, is24Hours: false, slots: [{ startTime: "08:00", endTime: "12:00" }] } as never;

  it("is booked minutes over open minutes, merging overlaps and ignoring maintenance", () => {
    const events = [
      ev("a", 8, 0, 9, 0),
      ev("b", 8, 30, 9, 30), // overlaps a -> union 8:00-9:30
      ev("m", 10, 0, 12, 0, "c1", "MAINTENANCE"),
    ];
    const r = computeUtilization(events, ["c1", "c2"], [DAY], () => openDay);
    expect(r.openMinutes).toBe(480); // 2 courts x 4h
    expect(r.bookedMinutes).toBe(90);
    expect(r.percent).toBe(19);
    expect(r.activeCourts).toBe(1);
  });

  it("counts nothing outside operating windows", () => {
    const r = computeUtilization([ev("late", 14, 0, 15, 0)], ["c1"], [DAY], () => openDay);
    expect(r.bookedMinutes).toBe(0);
  });
});
