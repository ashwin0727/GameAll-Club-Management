"use client";

import { ArrowDown, ArrowUp, ChevronsUpDown } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { CustomerAvatar } from "@/features/bookings/components/customer-avatar";
import { GuestBookingActions } from "@/features/bookings/components/guest-booking-actions";
import {
  displayPhone,
  formatBookingDate,
  formatBookingTime,
  type GuestSortDir,
  type GuestSortKey,
} from "@/features/bookings/guest-booking-table";
import type { BookingStatus, GuestBookingRow, GuestPaymentStatus } from "@/features/bookings/types";
import { formatCurrency } from "@/features/pricing/money";
import { cn } from "@/lib/utils";

const COLUMNS: { label: string; sort?: GuestSortKey }[] = [
  { label: "Booking ID" },
  { label: "Guest Name", sort: "guest" },
  { label: "Phone", sort: "phone" },
  { label: "Sport" },
  { label: "Court" },
  { label: "Date & Time", sort: "date" },
  { label: "Amount" },
  { label: "Payment" },
  { label: "Status", sort: "status" },
];

/**
 * A booking's status as a small pill with a dot. A booking that is waiting on payment
 * reads "Upcoming", in amber.
 */
function StatusPill({ status }: { status: BookingStatus }) {
  const look: Record<BookingStatus, { label: string; cls: string; dot: string }> = {
    confirmed: { label: "Confirmed", cls: "bg-success/10 text-success", dot: "bg-success" },
    completed: { label: "Completed", cls: "bg-secondary text-muted-foreground", dot: "bg-muted-foreground" },
    cancelled: { label: "Cancelled", cls: "bg-destructive/10 text-destructive", dot: "bg-destructive" },
    pending: { label: "Upcoming", cls: "bg-warning/10 text-warning", dot: "bg-warning" },
  };
  const { label, cls, dot } = look[status];
  return (
    <span className={cn("inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs font-medium", cls)}>
      <span className={cn("h-1.5 w-1.5 rounded-full", dot)} />
      {label}
    </span>
  );
}

/** How the money side stands. Just the state — not how it was paid. */
function PaymentBadge({ status }: { status: GuestPaymentStatus }) {
  if (status === "PAID") return <Badge variant="success">Paid</Badge>;
  if (status === "REFUNDED") return <Badge variant="destructive">Refunded</Badge>;
  // Part-paid reads as its own thing: "Pending" hid the fact that money had already been taken.
  if (status === "PARTIALLY_PAID") return <Badge variant="warning">Partly paid</Badge>;
  return <Badge variant="warning">Pending</Badge>;
}

/**
 * The Guest Bookings table: booking ID, guest (initials avatar and name), phone (the number
 * alone), sport with its icon, court, date over time, amount, payment state, status pill
 * and the row's actions. The Guest Name, Phone, Date & Time and Status headings sort the
 * rows on screen.
 */
export function GuestBookingsTable({
  rows,
  sortKey,
  sortDir,
  onSort,
  sportIcon,
  facilityId,
  facilityName,
  onChanged,
}: {
  /** The rows to show (already in the order to show them); null while loading. */
  rows: GuestBookingRow[] | null;
  sortKey: GuestSortKey | null;
  sortDir: GuestSortDir;
  onSort: (key: GuestSortKey) => void;
  /** The active sport's icon — the whole page is one sport. */
  sportIcon: string;
  facilityId: string;
  facilityName: string;
  onChanged: () => void;
}) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead className="border-b border-border text-left text-xs text-muted-foreground">
          <tr>
            {COLUMNS.map((c) => {
              const active = c.sort !== undefined && sortKey === c.sort;
              const Icon = !active ? ChevronsUpDown : sortDir === "asc" ? ArrowUp : ArrowDown;
              return (
                <th
                  key={c.label}
                  aria-sort={c.sort ? (active ? (sortDir === "asc" ? "ascending" : "descending") : "none") : undefined}
                  className="px-4 py-3 font-medium"
                >
                  {c.sort ? (
                    <button
                      type="button"
                      onClick={() => onSort(c.sort!)}
                      className={cn("flex items-center gap-1 whitespace-nowrap transition-colors hover:text-foreground", active && "text-foreground")}
                    >
                      {c.label}
                      <Icon className="h-3 w-3" aria-hidden />
                    </button>
                  ) : (
                    <span className="whitespace-nowrap">{c.label}</span>
                  )}
                </th>
              );
            })}
            <th className="px-4 py-3 text-right font-medium">Actions</th>
          </tr>
        </thead>
        <tbody>
          {rows === null ? (
            Array.from({ length: 6 }).map((_, i) => (
              <tr key={i} className="border-b border-border/60">
                <td colSpan={10} className="px-4 py-3">
                  <Skeleton className="h-9 w-full" />
                </td>
              </tr>
            ))
          ) : rows.length === 0 ? (
            <tr>
              <td colSpan={10} className="px-4 py-10 text-center text-sm text-muted-foreground">
                No guest bookings match these filters.
              </td>
            </tr>
          ) : (
            rows.map((r) => (
              <tr key={r.bookingId} className="border-b border-border/60 transition-colors last:border-b-0 hover:bg-accent/40">
                <td className="whitespace-nowrap px-4 py-3 text-muted-foreground">{r.code}</td>
                <td className="px-4 py-3">
                  <div className="flex items-center gap-3">
                    <CustomerAvatar name={r.guestName} />
                    <span className="max-w-[10rem] truncate font-medium text-foreground">{r.guestName}</span>
                  </div>
                </td>
                <td className="whitespace-nowrap px-4 py-3 tabular-nums text-foreground/80">{displayPhone(r.guestPhone)}</td>
                <td className="px-4 py-3">
                  <span className="flex items-center gap-2 whitespace-nowrap">
                    <span aria-hidden className="text-lg leading-none">
                      {sportIcon}
                    </span>
                    {r.sportName ?? "—"}
                  </span>
                </td>
                <td className="whitespace-nowrap px-4 py-3 text-foreground/80">{r.courtName}</td>
                <td className="whitespace-nowrap px-4 py-3">
                  <p className="text-foreground">{formatBookingDate(r.startTime)}</p>
                  <p className="text-xs tabular-nums text-muted-foreground">
                    {formatBookingTime(r.startTime)} - {formatBookingTime(r.endTime)}
                  </p>
                </td>
                <td className="whitespace-nowrap px-4 py-3 font-medium tabular-nums text-foreground">
                  {r.amountMinor == null ? "—" : formatCurrency(r.amountMinor, r.currency)}
                </td>
                <td className="px-4 py-3">
                  <PaymentBadge status={r.paymentStatus} />
                </td>
                <td className="px-4 py-3">
                  <StatusPill status={r.status} />
                </td>
                <td className="px-4 py-3 text-right">
                  <GuestBookingActions row={r} facilityId={facilityId} facilityName={facilityName} onChanged={onChanged} />
                </td>
              </tr>
            ))
          )}
        </tbody>
      </table>
    </div>
  );
}
