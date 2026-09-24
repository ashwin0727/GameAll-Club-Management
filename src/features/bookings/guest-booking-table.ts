import type { BookingStatus, GuestBookingRow } from "@/features/bookings/types";

export type GuestSortKey = "guest" | "phone" | "date" | "status";
export type GuestSortDir = "asc" | "desc";

const STATUS_RANK: Record<BookingStatus, number> = { confirmed: 0, pending: 1, completed: 2, cancelled: 3 };

/**
 * Orders the whole filtered set (not just the visible page) by the clicked column.
 * Ties fall back to the booking time, so equal values keep a steady order.
 */
export function sortGuestRows(rows: GuestBookingRow[], key: GuestSortKey, dir: GuestSortDir): GuestBookingRow[] {
  const cmp = (a: GuestBookingRow, b: GuestBookingRow): number => {
    switch (key) {
      case "guest":
        return a.guestName.localeCompare(b.guestName, undefined, { sensitivity: "base" });
      case "phone":
        // The last ten digits — the number itself — so "+91 98765 43210" and "98765 43210" sort together.
        return (a.guestPhone ?? "").replace(/\D/g, "").slice(-10).localeCompare((b.guestPhone ?? "").replace(/\D/g, "").slice(-10));
      case "date":
        return a.startTime.localeCompare(b.startTime);
      case "status":
        return STATUS_RANK[a.status] - STATUS_RANK[b.status];
    }
  };
  const sign = dir === "asc" ? 1 : -1;
  return [...rows].sort((a, b) => sign * cmp(a, b) || b.startTime.localeCompare(a.startTime));
}

/** "+91 98765 43210" → "98765 43210": the number alone, without the country code. */
export function displayPhone(phone: string | null | undefined): string {
  if (!phone) return "—";
  const national = phone.replace(/\D/g, "").slice(-10);
  if (national.length === 0) return "—";
  return national.length === 10 ? `${national.slice(0, 5)} ${national.slice(5)}` : national;
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** "15 Sep 2026" */
export function formatBookingDate(iso: string): string {
  const d = new Date(iso);
  return `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
}

/** "3:00 PM" */
export function formatBookingTime(iso: string): string {
  const d = new Date(iso);
  const h = d.getHours();
  return `${h % 12 === 0 ? 12 : h % 12}:${String(d.getMinutes()).padStart(2, "0")} ${h < 12 ? "AM" : "PM"}`;
}
