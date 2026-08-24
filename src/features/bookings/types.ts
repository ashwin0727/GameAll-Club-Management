export type BookingStatus = "pending" | "confirmed" | "cancelled" | "completed";
export type CustomerType = "MEMBER" | "GUEST";
export type PaymentStatus = "PENDING" | "PAID" | "REFUNDED";

export interface Booking {
  id: string;
  facilityId: string;
  courtId: string;
  facilitySportId: string | null;
  memberId: string | null;
  customerType: CustomerType;
  guestPlayerId: string | null;
  guestName: string | null;
  guestPhone: string | null;
  /** ISO timestamp (UTC). */
  startTime: string;
  /** ISO timestamp (UTC). */
  endTime: string;
  status: BookingStatus;
  amountMinor: number | null;
  currency: string;
  paymentStatus: PaymentStatus;
  cancellationReason: string | null;
  notes: string | null;
  createdBy: string;
  createdAt: string;
  updatedAt: string;
}

export interface NewBookingInput {
  facilityId: string;
  courtId: string;
  /** ISO timestamp (UTC). */
  startTime: string;
  /** ISO timestamp (UTC). */
  endTime: string;
  customerType: CustomerType;
  memberId?: string | null;
  guestPlayerId?: string | null;
  guestName?: string | null;
  guestPhone?: string | null;
  notes?: string | null;
  paymentStatus?: PaymentStatus;
}

export interface RescheduleBookingInput {
  bookingId: string;
  courtId: string;
  /** ISO timestamp (UTC). */
  startTime: string;
  /** ISO timestamp (UTC). */
  endTime: string;
}

/** One bookable window on the picked date, for the "pick a slot" UI. */
export interface TimeSlot {
  /** ISO timestamp (UTC). */
  startTime: string;
  /** ISO timestamp (UTC). */
  endTime: string;
  available: boolean;
}