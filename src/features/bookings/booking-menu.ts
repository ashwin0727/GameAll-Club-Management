import type { PermissionKey } from "@/features/staff/types";
import type { Booking } from "@/features/bookings/types";

export type BookingActionId =
  | "view"
  | "edit"
  | "reschedule"
  | "change-court"
  | "mark-payment"
  | "cancel"
  | "payment-details"
  | "duplicate"
  | "cancellation-reason"
  | "payment-refund"
  | "view-customer";

export interface BookingMenuInput {
  status: Booking["status"];
  paymentStatus: Booking["paymentStatus"];
  kind: "MEMBER" | "GUEST";
  /** The booking has already finished — it can no longer be moved. */
  ended: boolean;
  can: (key: PermissionKey) => boolean;
}

/** Items in a group sit together; a divider is drawn between groups. */
export type BookingMenuGroup = BookingActionId[];

/**
 * What the row's ⋯ menu offers, from the booking's status, its payment status
 * and the signed-in person's permissions. The shape follows the design:
 *
 *   confirmed  view · edit · reschedule · change court · mark payment | cancel | payment details · duplicate
 *   pending    view · edit · reschedule · change court · mark payment | cancel
 *   cancelled  view · cancellation reason · payment/refund · duplicate
 *   completed  view · payment details · customer
 *
 * Cancel always sits in its own group so it is never next to a harmless item.
 * Items the person can't use — or that make no sense for this booking (marking
 * an already-paid booking as paid, moving one that has finished, editing a
 * member booking) — are left out entirely, and empty groups disappear with them.
 * This is UX only; the database enforces the same rules.
 */
export function buildBookingMenu(b: BookingMenuInput): BookingMenuGroup[] {
  const guest = b.kind === "GUEST";
  const canEdit = guest ? b.can("GUEST_BOOKINGS_EDIT") : b.can("BOOKINGS_EDIT");
  const canCancel = guest ? b.can("GUEST_BOOKINGS_CANCEL") : b.can("BOOKINGS_CANCEL");
  const canCreate = b.can("BOOKINGS_CREATE") || b.can("GUEST_BOOKINGS_CREATE");
  const canPayments = b.can("BOOKINGS_MANAGE_PAYMENTS") || b.can("FINANCE_RECORD_PAYMENT");
  const canSeeMoney = canPayments || b.can("FINANCE_VIEW");

  const movable = canEdit && !b.ended;
  const unpaid = b.paymentStatus === "PENDING";

  const has = (cond: boolean, id: BookingActionId): BookingActionId[] => (cond ? [id] : []);

  let groups: BookingMenuGroup[];
  switch (b.status) {
    case "confirmed":
      groups = [
        [
          "view",
          ...has(guest && canEdit, "edit"),
          ...has(movable, "reschedule"),
          ...has(movable, "change-court"),
          ...has(canPayments && unpaid, "mark-payment"),
        ],
        [...has(canCancel, "cancel")],
        [...has(canSeeMoney, "payment-details"), ...has(guest && canCreate, "duplicate")],
      ];
      break;
    case "pending":
      groups = [
        [
          "view",
          ...has(guest && canEdit, "edit"),
          ...has(movable, "reschedule"),
          ...has(movable, "change-court"),
          ...has(canPayments && unpaid, "mark-payment"),
        ],
        [...has(canCancel, "cancel")],
      ];
      break;
    case "cancelled":
      groups = [["view", "cancellation-reason", ...has(canSeeMoney, "payment-refund"), ...has(guest && canCreate, "duplicate")]];
      break;
    case "completed":
      groups = [["view", ...has(canSeeMoney, "payment-details"), ...has(b.can("BOOKINGS_VIEW_CUSTOMER"), "view-customer")]];
      break;
  }
  return groups.filter((g) => g.length > 0);
}
