import { describe, expect, it } from "vitest";
import { courtsNow } from "@/features/dashboard/court-activity";
import type { ScheduleBlock, ScheduleCourtRow } from "@/features/dashboard/types";

const block = (id: string, startHour: number, endHour: number): ScheduleBlock => ({
  id,
  label: id,
  startMinute: startHour * 60,
  endMinute: endHour * 60,
  timeLabel: "",
  type: "GUEST",
  lane: 0,
});

const court = (id: string, ...blocks: ScheduleBlock[]): ScheduleCourtRow => ({
  courtId: id,
  courtName: id,
  sportName: "Badminton",
  laneCount: 1,
  blocks,
});

const status = (rows: ReturnType<typeof courtsNow>) => Object.fromEntries(rows.map((r) => [r.court.courtId, r.status]));

describe("courtsNow", () => {
  it("marks every court with a booking still to come as Booked — no matter which starts first", () => {
    const rows = courtsNow([court("c1", block("late", 22, 23)), court("c2", block("early", 20, 21))], 9 * 60, true);
    expect(status(rows)).toEqual({ c1: "booked", c2: "booked" });
  });

  it("shows the court's next booking, not a later one", () => {
    const rows = courtsNow([court("c1", block("second", 15, 16), block("first", 12, 13))], 9 * 60, true);
    expect(rows[0]!.block!.id).toBe("first");
  });

  it("shows a court in use right now as Live, with when it frees up", () => {
    const rows = courtsNow([court("c1", block("now", 9, 10), block("later", 15, 16)), court("c2", block("b", 12, 13))], 9 * 60 + 30, true);
    expect(rows[0]).toMatchObject({ status: "live", busyUntil: 10 * 60 });
    expect(rows[1]!.status).toBe("booked");
  });

  it("shows a court with nothing left as Available; bookings already over don't count", () => {
    const rows = courtsNow([court("c1", block("done", 8, 9)), court("c2")], 12 * 60, true);
    expect(status(rows)).toEqual({ c1: "available", c2: "available" });
  });

  it("only ever produces Live, Booked or Available", () => {
    const rows = courtsNow(
      [court("c1", block("a", 9, 10)), court("c2", block("b", 12, 13)), court("c3"), court("c4", block("c", 6, 7))],
      9 * 60 + 15,
      true,
    );
    for (const r of rows) expect(["live", "booked", "available"]).toContain(r.status);
  });

  it("on another day, every booking is still to come", () => {
    const rows = courtsNow([court("c1", block("a", 18, 19)), court("c2")], 12 * 60, false);
    expect(status(rows)).toEqual({ c1: "booked", c2: "available" });
  });
});
