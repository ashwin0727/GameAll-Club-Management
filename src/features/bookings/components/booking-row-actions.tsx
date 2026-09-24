"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import {
  ArrowLeftRight,
  CalendarClock,
  Copy,
  CreditCard,
  Eye,
  FileText,
  MoreHorizontal,
  Pencil,
  Receipt,
  User,
  Wallet,
  XCircle,
  type LucideIcon,
} from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { PermissionKey } from "@/features/staff/types";
import { buildBookingMenu, type BookingActionId } from "@/features/bookings/booking-menu";
import {
  CancelBookingDialog,
  CancellationReasonDialog,
  ChangeCourtDialog,
  CustomerDialog,
  DuplicateBookingDialog,
  MarkPaymentDialog,
  PaymentDetailsDialog,
} from "@/features/bookings/components/booking-row-dialogs";
import type { BookingRow } from "@/features/bookings/list-utils";
import type { Booking } from "@/features/bookings/types";
import { cn } from "@/lib/utils";

const ITEMS: Record<BookingActionId, { label: string; icon: LucideIcon }> = {
  view: { label: "View Booking", icon: Eye },
  edit: { label: "Edit Booking", icon: Pencil },
  reschedule: { label: "Reschedule", icon: CalendarClock },
  "change-court": { label: "Change Court", icon: ArrowLeftRight },
  "mark-payment": { label: "Mark Payment", icon: CreditCard },
  cancel: { label: "Cancel Booking", icon: XCircle },
  "payment-details": { label: "View Payment Details", icon: Receipt },
  duplicate: { label: "Duplicate Booking", icon: Copy },
  "cancellation-reason": { label: "View Cancellation Reason", icon: FileText },
  "payment-refund": { label: "View Payment/Refund", icon: Wallet },
  "view-customer": { label: "View Customer", icon: User },
};

type Dialog = Exclude<BookingActionId, "view" | "edit" | "reschedule"> | null;

/**
 * The ⋯ menu on a booking row. What it lists depends on the booking's status,
 * its payment status and the person's permissions (see buildBookingMenu).
 * Cancel sits alone below a divider in the destructive colour; everything else
 * is neutral, so it is hard to hit by accident.
 */
export function BookingRowActions({
  row,
  courts,
  onOpenBooking,
  onChanged,
}: {
  row: BookingRow;
  /** Courts of the same sport — the candidates for Change Court. */
  courts: { id: string; name: string }[];
  onOpenBooking: (booking: Booking, mode?: "view" | "reschedule") => void;
  /** Something about the booking changed — refresh the page's data. */
  onChanged: () => void;
}) {
  const router = useRouter();
  const perms = usePermissionContext();
  const [dialog, setDialog] = useState<Dialog>(null);

  // Memberships and coaching have no court booking behind them; they open their own page.
  const booking = row.booking;
  if (!booking) return <LinkedRowMenu row={row} />;

  // Without a permission context (e.g. mid-onboarding) fall back to the role gate the page already applied.
  const can = (key: PermissionKey) => (perms ? perms.can(key) : true);
  const groups = buildBookingMenu({
    status: row.status,
    paymentStatus: booking.paymentStatus,
    // Which tools apply (guest edit / duplicate / payments) follows how the booking was actually saved,
    // not the Guest label every court booking shares.
    kind: booking.customerType,
    ended: row.end.getTime() < Date.now(),
    can,
  });
  const canOpenFinance = can("FINANCE_VIEW");

  // An arrow, not a declaration: only arrows keep the `booking` null check from above.
  const run = (id: BookingActionId) => {
    switch (id) {
      case "view":
        return onOpenBooking(booking, "view");
      case "reschedule":
        return onOpenBooking(booking, "reschedule");
      case "edit":
        return router.push(`/guest-bookings/${row.id}/edit`);
      case "mark-payment":
        // Guest payments are recorded here; a member's goes through the details dialog's Pay Now.
        return booking.customerType === "GUEST" ? setDialog("mark-payment") : onOpenBooking(booking, "view");
      default:
        return setDialog(id);
    }
  };

  const close = () => setDialog(null);

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button
            type="button"
            aria-label={`Actions for ${row.reference}`}
            className="inline-flex h-8 w-8 items-center justify-center rounded-md text-muted-foreground outline-none hover:bg-accent hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring"
          >
            <MoreHorizontal className="h-4 w-4" />
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-60">
          {groups.map((group, i) => (
            <div key={i}>
              {i > 0 && <DropdownMenuSeparator />}
              {group.map((id) => {
                const { label, icon: Icon } = ITEMS[id];
                const danger = id === "cancel";
                return (
                  <DropdownMenuItem
                    key={id}
                    onClick={() => run(id)}
                    className={cn("gap-2.5 py-2", danger && "text-destructive focus:bg-destructive/10 focus:text-destructive")}
                  >
                    <Icon className="h-4 w-4 shrink-0" />
                    {label}
                  </DropdownMenuItem>
                );
              })}
            </div>
          ))}
        </DropdownMenuContent>
      </DropdownMenu>

      {dialog === "cancel" && <CancelBookingDialog booking={booking} onClose={close} onDone={onChanged} />}
      {dialog === "change-court" && <ChangeCourtDialog booking={booking} courts={courts} onClose={close} onDone={onChanged} />}
      {dialog === "mark-payment" && <MarkPaymentDialog booking={booking} onClose={close} onDone={onChanged} />}
      {dialog === "duplicate" && <DuplicateBookingDialog booking={booking} onClose={close} onDone={onChanged} />}
      {dialog === "payment-details" && (
        <PaymentDetailsDialog booking={booking} refundView={false} canOpenFinance={canOpenFinance} onClose={close} />
      )}
      {dialog === "payment-refund" && (
        <PaymentDetailsDialog booking={booking} refundView canOpenFinance={canOpenFinance} onClose={close} />
      )}
      {dialog === "cancellation-reason" && <CancellationReasonDialog booking={booking} onClose={close} />}
      {dialog === "view-customer" && <CustomerDialog row={row} onClose={close} />}
    </>
  );
}

/**
 * A membership or coaching row has no court booking to reschedule or cancel —
 * those are managed on their own page, so the menu is just a way there.
 */
function LinkedRowMenu({ row }: { row: BookingRow }) {
  const router = useRouter();
  const label = row.kind === "MEMBERSHIP" ? "View Membership" : "View Coaching Enrollment";
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button
          type="button"
          aria-label={`Actions for ${row.reference}`}
          className="inline-flex h-8 w-8 items-center justify-center rounded-md text-muted-foreground outline-none hover:bg-accent hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring"
        >
          <MoreHorizontal className="h-4 w-4" />
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-60">
        <DropdownMenuItem className="gap-2.5 py-2" disabled={!row.href} onClick={() => row.href && router.push(row.href)}>
          <Eye className="h-4 w-4 shrink-0" />
          {label}
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
