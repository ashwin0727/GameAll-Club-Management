import { describe, expect, it } from "vitest";
import {
  buildGuestProfiles,
  filterPotential,
  potentialMembers,
  segmentStats,
  sortByBookings,
  type PotentialFilters,
} from "@/features/bookings/potential-members";
import type { GuestBookingRow } from "@/features/bookings/types";

const NOW = new Date(2026, 8, 22, 12);
const at = (month: number, day: number, hour = 10) => new Date(2026, month, day, hour).toISOString();

function row(over: Partial<GuestBookingRow>): GuestBookingRow {
  return {
    bookingId: Math.random().toString(36),
    code: "GBK0001",
    guestName: "Guest",
    guestPhone: "+91 98765 43210",
    sportName: "Badminton",
    courtName: "Court 1",
    startTime: at(8, 10),
    endTime: at(8, 10, 11),
    partySize: 2,
    amountMinor: 30000,
    paidMinor: 30000,
    outstandingMinor: 0,
    currency: "INR",
    paymentStatus: "PAID",
    paymentMethod: null,
    status: "completed",
    source: "COURT",
    ...over,
  };
}

const phone = (n: number) => `9000000${String(n).padStart(3, "0")}`;
/** A guest's booking: (guest number, month index, day) */
const bk = (g: number, month: number, day: number, extra: Partial<GuestBookingRow> = {}) =>
  row({ guestPhone: phone(g), guestName: `G${g}`, startTime: at(month, day), endTime: at(month, day, 11), ...extra });

const NO_FILTERS: PotentialFilters = { search: "", court: "", minBookings: 3, lastBooking: "any", minSpentMinor: 0 };

describe("buildGuestProfiles", () => {
  it("makes one profile per phone number, whatever the formatting, and ignores cancelled bookings", () => {
    const rows = [
      row({ guestPhone: "+91 98765 43210", guestName: "Rahul" }),
      row({ guestPhone: "9876543210", guestName: "Rahul S" }),
      row({ guestPhone: "9876543210", status: "cancelled" }),
      row({ guestPhone: null }),
    ];
    const profiles = buildGuestProfiles(rows, new Set(), NOW);
    expect(profiles).toHaveLength(1);
    expect(profiles[0]!.bookings).toBe(2);
  });

  it("takes the name and phone from the latest booking, and the last booking that has started", () => {
    const rows = [bk(1, 8, 1, { guestName: "Old Name" }), bk(1, 8, 20, { guestName: "New Name" }), bk(1, 9, 30)]; // 30 Sep is still to come
    const [p] = buildGuestProfiles(rows, new Set(), NOW);
    expect(p!.name).toBe("G1"); // newest booking (30 Sep) carries the name
    expect(new Date(p!.lastBookingAt).getDate()).toBe(20); // but the last one that has actually happened is 20 Sep
  });

  it("totals what was collected and finds the court they book most", () => {
    const rows = [
      bk(1, 8, 1, { courtName: "Court 2", paidMinor: 20000 }),
      bk(1, 8, 5, { courtName: "Court 2", paidMinor: 20000 }),
      bk(1, 8, 9, { courtName: "Court 1", paidMinor: 0 }),
    ];
    const [p] = buildGuestProfiles(rows, new Set(), NOW);
    expect(p).toMatchObject({ totalSpentMinor: 40000, preferredCourt: "Court 2" });
  });

  it("labels a guest Frequent if they booked in the last 30 days, otherwise Returning", () => {
    const recent = buildGuestProfiles([bk(1, 8, 20)], new Set(), NOW)[0]!;
    const older = buildGuestProfiles([bk(2, 6, 1)], new Set(), NOW)[0]!;
    expect(recent.label).toBe("Frequent");
    expect(older.label).toBe("Returning");
  });

  it("works out monthly spend as total spent over the months since their first booking, at least one", () => {
    // First booking 4 Aug (~1.6 months before 22 Sep), ₹900 spent
    const rows = [bk(1, 7, 4, { paidMinor: 30000 }), bk(1, 8, 4, { paidMinor: 30000 }), bk(1, 8, 20, { paidMinor: 30000 })];
    const [p] = buildGuestProfiles(rows, new Set(), NOW);
    expect(p!.monthlySpendMinor).toBeGreaterThan(50000);
    expect(p!.monthlySpendMinor).toBeLessThan(60000);
    // A guest who started this week counts as one month, not a fraction of one
    const fresh = buildGuestProfiles([bk(2, 8, 20, { paidMinor: 30000 })], new Set(), NOW)[0]!;
    expect(fresh.monthlySpendMinor).toBe(30000);
  });

  it("marks a guest whose phone matches a member", () => {
    const [p] = buildGuestProfiles([bk(1, 8, 20)], new Set(["9000000001"]), NOW);
    expect(p!.isMember).toBe(true);
  });
});

describe("potential members and their figures", () => {
  // g1: 4 bookings, g2: 3, g3: 3 but a member, g4: 2, g5: 5 but a member
  const rows = [
    ...[1, 5, 9, 12].map((d) => bk(1, 8, d)),
    ...[2, 6, 10].map((d) => bk(2, 8, d)),
    ...[3, 7, 11].map((d) => bk(3, 8, d)),
    ...[4, 8].map((d) => bk(4, 8, d)),
    ...[1, 2, 3, 4, 5].map((d) => bk(5, 8, d)),
  ];
  const guests = buildGuestProfiles(rows, new Set(["9000000003", "9000000005"]), NOW);

  it("needs 3+ bookings and not being a member", () => {
    expect(potentialMembers(guests).map((g) => g.name).sort()).toEqual(["G1", "G2"]);
  });

  it("counts them, averages their bookings and sums their monthly spend", () => {
    const s = segmentStats(guests);
    expect(s.count).toBe(2);
    expect(s.avgBookings).toBeCloseTo(3.5); // (4 + 3) / 2
    expect(s.monthlyRevenueMinor).toBe(potentialMembers(guests).reduce((a, g) => a + g.monthlySpendMinor, 0));
  });

  it("gives the conversion opportunity as potential members over all frequent guests, members included", () => {
    // frequent (3+): g1, g2, g3, g5 = 4; potential = 2 → 50%
    expect(segmentStats(guests).conversionPercent).toBeCloseTo(50);
  });

  it("is all zeros with no frequent guests", () => {
    expect(segmentStats([])).toEqual({ count: 0, monthlyRevenueMinor: 0, conversionPercent: 0, avgBookings: 0 });
  });
});

describe("filterPotential", () => {
  const rows = [
    ...[1, 5, 9, 12, 15].map((d) => bk(1, 8, d, { courtName: "Court 1", paidMinor: 40000, guestName: "Rahul Sharma" })),
    ...[2, 6, 10].map((d) => bk(2, 7, d, { courtName: "Court 2", paidMinor: 10000, guestName: "Anita Patel", guestPhone: "+91 87654 32109" })),
  ];
  const guests = potentialMembers(buildGuestProfiles(rows, new Set(), NOW));
  const run = (over: Partial<PotentialFilters>) => filterPotential(guests, { ...NO_FILTERS, ...over }, NOW).map((g) => g.name);

  it("shows everyone with no filters", () => {
    expect(run({}).sort()).toEqual(["Anita Patel", "Rahul Sharma"]);
  });
  it("filters by booking count, preferred court, and total spent", () => {
    expect(run({ minBookings: 5 })).toEqual(["Rahul Sharma"]);
    expect(run({ court: "Court 2" })).toEqual(["Anita Patel"]);
    expect(run({ minSpentMinor: 100000 })).toEqual(["Rahul Sharma"]);
  });
  it("filters by how recently they last booked", () => {
    expect(run({ lastBooking: "30" })).toEqual(["Rahul Sharma"]); // Anita last booked 10 Aug
    expect(run({ lastBooking: "90" }).sort()).toEqual(["Anita Patel", "Rahul Sharma"]);
  });
  it("searches by name or phone digits", () => {
    expect(run({ search: "anita" })).toEqual(["Anita Patel"]);
    expect(run({ search: "87654" })).toEqual(["Anita Patel"]);
    expect(run({ search: "nobody" })).toEqual([]);
  });
});

describe("sortByBookings", () => {
  const rows = [
    ...[1, 2, 3].map((d) => bk(1, 8, d)),
    ...[4, 5, 6, 7, 8].map((d) => bk(2, 8, d)),
    ...[9, 10, 11].map((d) => bk(3, 8, d)),
  ];
  const guests = potentialMembers(buildGuestProfiles(rows, new Set(), NOW));
  it("puts the most bookings first by default, and reverses", () => {
    expect(sortByBookings(guests, "desc").map((g) => g.name)[0]).toBe("G2");
    expect(sortByBookings(guests, "asc").map((g) => g.name).pop()).toBe("G2");
  });
  it("breaks ties by who booked most recently", () => {
    expect(sortByBookings(guests, "desc").map((g) => g.name)).toEqual(["G2", "G3", "G1"]);
  });
});
