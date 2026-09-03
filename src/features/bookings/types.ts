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
  partySize: number;
  paymentMethod: string | null;
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
  partySize?: number;
  paymentMethod?: string | null;
}

export interface GuestBookingsSummary {
  total: number;
  confirmed: number;
  completed: number;
  cancelled: number;
  pending: number;
  totalRevenueMinor: number;
  avgPerBookingMinor: number;
  highestBookingMinor: number;
  totalChangePct: number | null;
  revenueChangePct: number | null;
  trend: { date: string; amountMinor: number }[];
}

export interface GuestBookingRow {
  bookingId: string;
  code: string;
  guestName: string;
  guestPhone: string | null;
  sportName: string | null;
  courtName: string;
  startTime: string;
  endTime: string;
  partySize: number;
  amountMinor: number | null;
  currency: string;
  paymentStatus: PaymentStatus;
  paymentMethod: string | null;
  status: BookingStatus;
  /** COURT = a bookings row. SESSION = a seat the owner released from a
   *  membership session, which has no court booking behind it. */
  source: GuestBookingSource;
}

export type GuestBookingSource = 'COURT' | 'SESSION';

export interface GuestBookingListParams {
  search?: string;
  facilitySportId?: string;
  courtId?: string;
  status?: BookingStatus;
  paymentStatus?: PaymentStatus;
  from?: string;
  to?: string;
  page: number;
  perPage: number;
}

export interface GuestBookingListResult {
  rows: GuestBookingRow[];
  totalCount: number;
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