import { describe, expect, it } from "vitest";
import { displayPhone, formatBookingDate, formatBookingTime, sortGuestRows } from "@/features/bookings/guest-booking-table";
import type { GuestBookingRow } from "@/features/bookings/types";

function row(over: Partial<GuestBookingRow>): GuestBookingRow {
  return {
    bookingId: "b",
    code: "GBK0001",
    guestName: "Guest",
    guestPhone: "+91 98765 43210",
    sportName: "Badminton",
    courtName: "Court 1",
    startTime: new Date(2026, 8, 15, 15).toISOString(),
    endTime: new Date(2026, 8, 15, 16).toISOString(),
    partySize: 2,
    amountMinor: 70000,
    paidMinor: 0,
    outstandingMinor: 0,
    currency: "INR",
    paymentStatus: "PENDING",
    paymentMethod: null,
    status: "confirmed",
    source: "COURT",
    ...over,
  };
}

const at = (day: number, hour = 9) => new Date(2026, 8, day, hour).toISOString();
const ids = (rows: GuestBookingRow[]) => rows.map((r) => r.bookingId);

describe("sortGuestRows", () => {
  const rows = [
    row({ bookingId: "a", guestName: "Rahul", guestPhone: "+91 98765 43210", startTime: at(15), status: "confirmed" }),
    row({ bookingId: "b", guestName: "anita", guestPhone: "+91 87654 32109", startTime: at(12), status: "cancelled" }),
    row({ bookingId: "c", guestName: "Vikram", guestPhone: "91234 56789", startTime: at(14), status: "completed" }),
  ];

  it("sorts by guest name, ignoring case, both ways", () => {
    expect(ids(sortGuestRows(rows, "guest", "asc"))).toEqual(["b", "a", "c"]);
    expect(ids(sortGuestRows(rows, "guest", "desc"))).toEqual(["c", "a", "b"]);
  });

  it("sorts by time, newest first when descending", () => {
    expect(ids(sortGuestRows(rows, "date", "desc"))).toEqual(["a", "c", "b"]);
    expect(ids(sortGuestRows(rows, "date", "asc"))).toEqual(["b", "c", "a"]);
  });

  it("sorts phone numbers by their digits, whatever the formatting", () => {
    // 8765… then 9123… (written without a country code) then 9876… — the +91 doesn't push a number out of place.
    expect(ids(sortGuestRows(rows, "phone", "asc"))).toEqual(["b", "c", "a"]);
  });

  it("sorts status confirmed, pending, completed, cancelled", () => {
    expect(ids(sortGuestRows(rows, "status", "asc"))).toEqual(["a", "c", "b"]);
  });

  it("doesn't change the list it was given", () => {
    const copy = [...rows];
    sortGuestRows(rows, "guest", "asc");
    expect(rows).toEqual(copy);
  });

  it("keeps equal values in time order", () => {
    const same = [row({ bookingId: "x", startTime: at(10) }), row({ bookingId: "y", startTime: at(12) })];
    expect(ids(sortGuestRows(same, "guest", "asc"))).toEqual(["y", "x"]);
  });
});

describe("displayPhone", () => {
  it("shows the number alone, without a country code", () => {
    expect(displayPhone("+91 98765 43210")).toBe("98765 43210");
    expect(displayPhone("+919876543210")).toBe("98765 43210");
    expect(displayPhone("9876543210")).toBe("98765 43210");
    expect(displayPhone("098765-43210")).toBe("98765 43210");
  });
  it("leaves a short number as it is and shows a dash for none", () => {
    expect(displayPhone("12345")).toBe("12345");
    expect(displayPhone(null)).toBe("—");
    expect(displayPhone("")).toBe("—");
  });
});

describe("formatting", () => {
  it("writes dates as in the design", () => {
    expect(formatBookingDate(new Date(2026, 8, 5, 9).toISOString())).toBe("5 Sep 2026");
    expect(formatBookingDate(new Date(2026, 11, 25, 9).toISOString())).toBe("25 Dec 2026");
  });
  it("writes times with an upper-case AM / PM", () => {
    expect(formatBookingTime(new Date(2026, 8, 15, 15).toISOString())).toBe("3:00 PM");
    expect(formatBookingTime(new Date(2026, 8, 15, 0, 5).toISOString())).toBe("12:05 AM");
    expect(formatBookingTime(new Date(2026, 8, 15, 12).toISOString())).toBe("12:00 PM");
  });
});
