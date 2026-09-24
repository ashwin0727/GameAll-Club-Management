import { describe, expect, it } from "vitest";
import { buildBookingMenu, type BookingMenuInput } from "@/features/bookings/booking-menu";

const everything = () => true;
const base: BookingMenuInput = {
  status: "confirmed",
  paymentStatus: "PENDING",
  kind: "GUEST",
  ended: false,
  can: everything,
};

describe("buildBookingMenu", () => {
  it("confirmed, unpaid guest booking: the full menu, cancel on its own", () => {
    expect(buildBookingMenu(base)).toEqual([
      ["view", "edit", "reschedule", "change-court", "mark-payment"],
      ["cancel"],
      ["payment-details", "duplicate"],
    ]);
  });

  it("pending booking has no payment-details or duplicate group", () => {
    expect(buildBookingMenu({ ...base, status: "pending" })).toEqual([
      ["view", "edit", "reschedule", "change-court", "mark-payment"],
      ["cancel"],
    ]);
  });

  it("cancelled booking: view, reason, refund, duplicate — nothing that changes it", () => {
    expect(buildBookingMenu({ ...base, status: "cancelled" })).toEqual([
      ["view", "cancellation-reason", "payment-refund", "duplicate"],
    ]);
  });

  it("completed booking: view, payment details, customer", () => {
    expect(buildBookingMenu({ ...base, status: "completed" })).toEqual([["view", "payment-details", "view-customer"]]);
  });

  it("hides mark-payment once the booking is paid", () => {
    const menu = buildBookingMenu({ ...base, paymentStatus: "PAID" }).flat();
    expect(menu).not.toContain("mark-payment");
  });

  it("member bookings can't be edited or duplicated through the guest tools", () => {
    const menu = buildBookingMenu({ ...base, kind: "MEMBER" }).flat();
    expect(menu).not.toContain("edit");
    expect(menu).not.toContain("duplicate");
    expect(menu).toContain("reschedule");
  });

  it("a finished booking can't be moved", () => {
    const menu = buildBookingMenu({ ...base, ended: true }).flat();
    expect(menu).not.toContain("reschedule");
    expect(menu).not.toContain("change-court");
    expect(menu).toContain("cancel");
  });

  it("follows permissions: no cancel right, no cancel item, and no empty divider left behind", () => {
    const menu = buildBookingMenu({ ...base, can: (k) => k !== "GUEST_BOOKINGS_CANCEL" });
    expect(menu.flat()).not.toContain("cancel");
    expect(menu.every((g) => g.length > 0)).toBe(true);
    expect(menu).toHaveLength(2);
  });

  it("with no permissions at all, a viewer still gets View Booking", () => {
    expect(buildBookingMenu({ ...base, can: () => false })).toEqual([["view"]]);
  });

  it("uses booking permissions for member bookings and guest ones for guests", () => {
    const onlyBookings = (k: string) => k.startsWith("BOOKINGS_");
    const member = buildBookingMenu({ ...base, kind: "MEMBER", can: onlyBookings }).flat();
    expect(member).toContain("cancel");
    const guest = buildBookingMenu({ ...base, kind: "GUEST", can: onlyBookings }).flat();
    expect(guest).not.toContain("cancel");
  });

  it("payment details need money permissions", () => {
    const menu = buildBookingMenu({ ...base, can: (k) => k === "GUEST_BOOKINGS_EDIT" }).flat();
    expect(menu).not.toContain("payment-details");
    expect(menu).not.toContain("mark-payment");
  });
});
