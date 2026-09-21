import { describe, expect, it } from "vitest";
import type { Booking } from "@/features/bookings/types";
import {
  bookingReference,
  bookingsToCsv,
  filterRows,
  formatDuration,
  maskPhone,
  pageWindow,
  paginate,
  sortRows,
  type BookingRow,
} from "@/features/bookings/list-utils";

function row(over: Partial<BookingRow> & { id: string }): BookingRow {
  const start = over.start ?? new Date(2026, 8, 15, 9, 0);
  const courtId = over.courtId ?? "c1";
  return {
    booking: {} as Booking,
    kind: "GUEST",
    customerName: "Rahul Mehta",
    customerPhone: "+91 98765 43210",
    courtId,
    courtIds: courtId ? [courtId] : [],
    courtLabel: null,
    start,
    end: over.end ?? new Date(start.getTime() + 3_600_000),
    timeLabel: null,
    durationMin: 60,
    durationLabel: "1 Hour",
    durationSub: null,
    amountMinor: 60000,
    amountSub: null,
    collectedMinor: 60000,
    currency: "INR",
    status: "confirmed",
    statusLabel: "Confirmed",
    reference: bookingReference(over.id, over.kind ?? "GUEST"),
    href: null,
    ...over,
  };
}

const courtName = (id: string) => ({ c1: "Court 1", c2: "Court 2", c10: "Court 10" })[id] ?? id;

describe("maskPhone", () => {
  it("hides the middle of a number, keeping the country code and last three digits", () => {
    expect(maskPhone("+91 98765 43210")).toBe("+91 98••• ••210");
    expect(maskPhone("9876543210")).toBe("98••• ••210");
  });
  it("never reveals a too-short value and handles missing numbers", () => {
    expect(maskPhone("12345")).toBe("••••••");
    expect(maskPhone(null)).toBe("—");
  });
});

describe("formatDuration", () => {
  it("reads naturally", () => {
    expect(formatDuration(30)).toBe("30 Min");
    expect(formatDuration(60)).toBe("1 Hour");
    expect(formatDuration(90)).toBe("1.5 Hours");
    expect(formatDuration(120)).toBe("2 Hours");
  });
});

describe("bookingReference", () => {
  it("is a stable short code, prefixed by what the row is", () => {
    expect(bookingReference("7f3a1b2c-0000-0000-0000-000000000000", "GUEST")).toBe("GBK7F3A");
    expect(bookingReference("7f3a1b2c-0000-0000-0000-000000000000", "MEMBERSHIP")).toBe("MEM7F3A");
    expect(bookingReference("7f3a1b2c-0000-0000-0000-000000000000", "COACHING")).toBe("COA7F3A");
  });
});

describe("filterRows", () => {
  const rows = [
    row({ id: "aaaa1111", kind: "MEMBERSHIP", customerName: "Rahul Mehta", customerPhone: "+91 98765 43210" }),
    row({ id: "bbbb2222", kind: "GUEST", customerName: "Priya Sharma", customerPhone: "+91 91234 56789", courtId: "c2", status: "pending" }),
  ];
  const none = { courtId: "", kind: "" as const, status: "" as const, search: "" };

  it("filters by court, type and status", () => {
    expect(filterRows(rows, { ...none, courtId: "c2" }).map((r) => r.id)).toEqual(["bbbb2222"]);
    expect(filterRows(rows, { ...none, kind: "MEMBERSHIP" }).map((r) => r.id)).toEqual(["aaaa1111"]);
    expect(filterRows(rows, { ...none, status: "pending" }).map((r) => r.id)).toEqual(["bbbb2222"]);
  });

  it("matches a court against every court a row uses, and filters memberships and coaching by type", () => {
    const multi = [
      row({ id: "cccc3333", kind: "COACHING", courtId: "c1", courtIds: ["c1", "c2"] }),
      row({ id: "dddd4444", kind: "MEMBERSHIP", courtId: "", courtIds: [] }),
    ];
    expect(filterRows(multi, { ...none, courtId: "c2" }).map((r) => r.id)).toEqual(["cccc3333"]);
    expect(filterRows(multi, { ...none, kind: "MEMBERSHIP" }).map((r) => r.id)).toEqual(["dddd4444"]);
    expect(filterRows(multi, { ...none, kind: "COACHING" })).toHaveLength(1);
  });

  it("searches by name, reference and phone digits (the real number, not the masked one)", () => {
    expect(filterRows(rows, { ...none, search: "priya" })).toHaveLength(1);
    expect(filterRows(rows, { ...none, search: "gbkbbbb" })).toHaveLength(1);
    expect(filterRows(rows, { ...none, search: "98765 43210" })).toHaveLength(1);
    expect(filterRows(rows, { ...none, search: "nobody" })).toHaveLength(0);
  });
});

describe("sortRows", () => {
  const rows = [
    row({ id: "a", start: new Date(2026, 8, 15, 11, 0), courtId: "c10", amountMinor: 100 }),
    row({ id: "b", start: new Date(2026, 8, 15, 9, 0), courtId: "c2", amountMinor: null }),
    row({ id: "c", start: new Date(2026, 8, 15, 10, 0), courtId: "c1", amountMinor: 500 }),
  ];
  it("sorts by time, both ways", () => {
    expect(sortRows(rows, "date", "asc", courtName).map((r) => r.id)).toEqual(["b", "c", "a"]);
    expect(sortRows(rows, "date", "desc", courtName).map((r) => r.id)).toEqual(["a", "c", "b"]);
  });
  it("sorts courts numerically, so Court 2 comes before Court 10", () => {
    expect(sortRows(rows, "court", "asc", courtName).map((r) => r.courtId)).toEqual(["c1", "c2", "c10"]);
  });
  it("puts bookings without an amount below the smallest", () => {
    expect(sortRows(rows, "amount", "asc", courtName).map((r) => r.id)).toEqual(["b", "a", "c"]);
  });
});

describe("pagination", () => {
  it("slices a page and clamps an out-of-range one", () => {
    const items = Array.from({ length: 30 }, (_, i) => i);
    expect(paginate(items, 2, 12).rows).toHaveLength(12);
    expect(paginate(items, 3, 12).rows).toHaveLength(6);
    expect(paginate(items, 99, 12).page).toBe(3);
    expect(paginate([], 1, 12)).toMatchObject({ pages: 1, rows: [] });
  });
  it("collapses long page lists", () => {
    expect(pageWindow(1, 5)).toEqual([1, 2, 3, 4, 5]);
    expect(pageWindow(6, 12)).toEqual([1, "…", 5, 6, 7, "…", 12]);
    expect(pageWindow(1, 12)).toEqual([1, 2, "…", 12]);
  });
});

describe("bookingsToCsv", () => {
  it("writes a header, escapes commas and quotes, and keeps phones masked", () => {
    const csv = bookingsToCsv(
      [row({ id: "aaaa1111", customerName: 'Corporate, "TCS"', durationSub: "Mon · Wed", amountSub: "₹1,500 / month", statusLabel: "Active" })],
      courtName,
      () => "₹600",
    );
    const [header, line] = csv.split("\n");
    expect(header).toContain("Reference,Date");
    expect(header).toContain("Duration details");
    expect(line).toContain("Mon · Wed");
    expect(line).toContain("₹1,500 / month");
    expect(line).toContain("Active");
    expect(line).toContain('"Corporate, ""TCS"""');
    expect(line).toContain("+91 98••• ••210");
    expect(line).not.toContain("98765 43210");
  });
});
