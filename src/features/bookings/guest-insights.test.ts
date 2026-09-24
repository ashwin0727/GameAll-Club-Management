import { describe, expect, it } from "vitest";
import { computeInsights, periodRange, phoneKey, recentGuests } from "@/features/bookings/guest-insights";
import type { GuestBookingRow } from "@/features/bookings/types";

const at = (day: number, hour = 10) => new Date(2026, 8, day, hour).toISOString();

function row(over: Partial<GuestBookingRow>): GuestBookingRow {
  return {
    bookingId: Math.random().toString(36),
    code: "GBK0001",
    guestName: "Guest",
    guestPhone: "+91 98765 43210",
    sportName: "Badminton",
    courtName: "Court 1",
    startTime: at(15),
    endTime: at(15, 11),
    partySize: 2,
    amountMinor: 30000,
    paidMinor: 0,
    outstandingMinor: 0,
    currency: "INR",
    paymentStatus: "PENDING",
    paymentMethod: null,
    status: "completed",
    source: "COURT",
    ...over,
  };
}

const phone = (n: number) => `9000000${String(n).padStart(3, "0")}`;
const b = (guest: number, day: number, extra: Partial<GuestBookingRow> = {}) => row({ guestPhone: phone(guest), guestName: `G${guest}`, startTime: at(day), endTime: at(day, 11), ...extra });

describe("phoneKey", () => {
  it("makes the same guest of a number with and without a country code", () => {
    expect(phoneKey("+91 98765 43210")).toBe("9876543210");
    expect(phoneKey("9876543210")).toBe("9876543210");
  });
  it("has no key for a missing or unusable number", () => {
    expect(phoneKey(null)).toBeNull();
    expect(phoneKey("123")).toBeNull();
  });
});

describe("periodRange", () => {
  const now = new Date(2026, 8, 22, 15);
  it("is the last N days ending today, inclusive", () => {
    const r = periodRange("7", null, now);
    expect(r.from).toEqual(new Date(2026, 8, 16));
    expect(r.to).toEqual(new Date(2026, 8, 23));
    expect(periodRange("30", null, now).from).toEqual(new Date(2026, 7, 24));
  });
  it("takes a custom pair of dates, the last day included", () => {
    const r = periodRange("custom", { from: "2026-09-01", to: "2026-09-10" }, now);
    expect(r.from).toEqual(new Date(2026, 8, 1));
    expect(r.to).toEqual(new Date(2026, 8, 11));
  });
});

describe("computeInsights", () => {
  // Period: 15–21 Sep. Guest 1 booked 3 times ever, 2 in the period. Guest 2: 1 ever, in the period.
  // Guest 3: 2 ever, only before the period. Guest 4: 1 in the period, but their first booking was earlier.
  const from = new Date(2026, 8, 15);
  const to = new Date(2026, 8, 22);
  const rows = [
    b(1, 5), b(1, 16, { paidMinor: 60000 }), b(1, 18, { paidMinor: 30000 }),
    b(2, 17, { paidMinor: 90000 }),
    b(3, 2), b(3, 3),
    b(4, 1), b(4, 20),
    b(5, 19, { status: "cancelled" }), // never counts
  ];
  const ins = computeInsights(rows, from, to);

  it("counts the different guests who booked in the period", () => {
    expect(ins.current.unique).toBe(3); // guests 1, 2, 4
  });

  it("counts Repeat (2+) and Frequent (3+) over each guest's whole history, not just the period", () => {
    expect(ins.repeat).toBe(3); // guests 1 (3), 3 (2), 4 (2)
    expect(ins.frequent).toBe(1); // guest 1
  });

  it("works out how many there were when the period began, for the arrows", () => {
    expect(ins.repeatAtStart).toBe(1); // only guest 3 had 2+ before 15 Sep
    expect(ins.frequentAtStart).toBe(0);
  });

  it("averages bookings over the guests who booked in the period", () => {
    // 4 bookings in the period (g1 x2, g2, g4) over 3 guests
    expect(ins.current.bookings).toBe(4);
    expect(ins.current.avgBookings).toBeCloseTo(4 / 3);
  });

  it("averages money collected over the period's non-cancelled bookings", () => {
    expect(ins.current.avgValueMinor).toBe(45000); // (60000 + 30000 + 90000 + 0) / 4
  });

  it("gives New Guests as a share of that period's guests whose first booking ever fell in it", () => {
    // Guests in the period: 1 (first booked 5 Sep), 2 (first booked 17 Sep), 4 (first booked 1 Sep). Only guest 2 is new.
    expect(ins.current.newPercent).toBeCloseTo((1 / 3) * 100);
  });

  it("measures the previous period the same way", () => {
    // 8–14 Sep: guest 3 has none (2, 3 Sep are earlier), nobody booked → zeros
    expect(ins.previous.unique).toBe(0);
    expect(ins.previous.avgBookings).toBe(0);
    expect(ins.previous.avgValueMinor).toBe(0);
    expect(ins.previous.newPercent).toBe(0);
  });

  it("is all zeros for no bookings", () => {
    const empty = computeInsights([], from, to);
    expect(empty).toMatchObject({ repeat: 0, frequent: 0, current: { unique: 0, avgBookings: 0, avgValueMinor: 0, newPercent: 0 } });
  });

  it("leaves bookings with no usable phone out of the guest figures but not out of booking value", () => {
    const r = computeInsights([b(1, 16, { paidMinor: 100 }), row({ guestPhone: null, startTime: at(17), endTime: at(17, 11), paidMinor: 300 })], from, to);
    expect(r.current.unique).toBe(1);
    expect(r.current.bookings).toBe(2);
    expect(r.current.avgValueMinor).toBe(200);
  });
});

describe("recentGuests", () => {
  const now = new Date(2026, 8, 22, 12);
  const rows = [
    b(1, 21), b(2, 20), b(3, 19), b(4, 18), b(5, 17), b(6, 10),
    b(1, 5), // guest 1 again, earlier — still one guest
    b(7, 25), // upcoming: not a recent guest
    b(8, 21, { status: "cancelled" }),
    row({ guestPhone: phone(9), guestName: "G9", startTime: new Date(2026, 7, 20, 10).toISOString(), endTime: new Date(2026, 7, 20, 11).toISOString() }), // 33 days ago
  ];
  const r = recentGuests(rows, now);

  it("shows the four guests who booked most recently, newest first, each once", () => {
    expect(r.shown.map((g) => g.name)).toEqual(["G1", "G2", "G3", "G4"]);
  });

  it("counts the other guests who booked in the last 30 days", () => {
    expect(r.more).toBe(2); // G5 and G6 — not G7 (upcoming), G8 (cancelled) or G9 (over 30 days ago)
  });

  it("copes with no guests", () => {
    expect(recentGuests([], now)).toEqual({ shown: [], more: 0 });
  });
});
