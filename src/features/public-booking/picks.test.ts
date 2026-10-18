import { describe, expect, it } from "vitest";
import { buildRequests, summarise, togglePick, type Pick } from "@/features/public-booking/picks";

const at = (h: number) => new Date(2026, 9, 20, h).toISOString();
const pick = (courtId: string, h: number, price = 30000): Pick => ({
  courtId,
  courtName: courtId.toUpperCase(),
  startTime: at(h),
  endTime: at(h + 1),
  priceMinor: price,
});

describe("togglePick", () => {
  it("adds, and removes on a second tap — per court", () => {
    let p = togglePick([], pick("c1", 18));
    p = togglePick(p, pick("c2", 18));
    expect(p).toHaveLength(2);
    expect(togglePick(p, pick("c1", 18)).map((x) => x.courtId)).toEqual(["c2"]);
  });
});

describe("buildRequests", () => {
  it("joins hours that touch on a court into one booking and keeps courts apart", () => {
    const r = buildRequests([pick("c1", 19), pick("c1", 18), pick("c2", 18), pick("c1", 21)]);
    expect(r.map((x) => [x.courtId, x.startTime, x.endTime, x.totalMinor])).toEqual([
      ["c1", at(18), at(20), 60000],
      ["c1", at(21), at(22), 30000],
      ["c2", at(18), at(19), 30000],
    ]);
  });
  it("flags only bookings longer than an hour for the 50% advance", () => {
    const r = buildRequests([pick("c1", 18), pick("c1", 19), pick("c2", 7)]);
    expect(r[0]).toMatchObject({ needsAdvance: true, advanceMinor: 30000 });
    expect(r[1]).toMatchObject({ needsAdvance: false, advanceMinor: 0 });
  });
});

describe("summarise", () => {
  it("4 hours at 300 → 1200 total, 600 online now, 600 at the venue", () => {
    const s = summarise([pick("c1", 18), pick("c1", 19), pick("c1", 20), pick("c1", 21)]);
    expect(s).toMatchObject({ totalMinor: 120000, advanceDueMinor: 60000, balanceMinor: 60000, advanceRequired: true, hours: 4 });
  });
  it("a single hour needs no advance", () => {
    expect(summarise([pick("c1", 18)])).toMatchObject({ advanceRequired: false, advanceDueMinor: 0, balanceMinor: 30000 });
  });
  it("several courts add up: two 1-hour bookings are not 'longer than an hour'", () => {
    expect(summarise([pick("c1", 18), pick("c2", 18)]).advanceRequired).toBe(false);
  });
});
