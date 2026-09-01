import type {
  Booking,
  GuestBookingListParams,
  GuestBookingListResult,
  GuestBookingsSummary,
  NewBookingInput,
  RescheduleBookingInput,
} from "@/features/bookings/types";

export interface BookingService {
  /** Bookings for a court on one calendar day (any status), earliest first. */
  getBookingsForCourtOnDate(courtId: string, date: Date): Promise<Booking[]>;
  /** Bookings for a facility within [from, to), across all courts. */
  getBookingsForFacility(facilityId: string, from: Date, to: Date): Promise<Booking[]>;
  /**
   * The single write path — validates operating hours and captures the
   * price server-side, and relies on the bookings table's own exclusion
   * constraint to reject a double-booked slot atomically (see
   * create_booking in 0007_bookings.sql).
   */
  createBooking(input: NewBookingInput): Promise<Booking>;
  /** Moves an existing booking to a new time/court, revalidating exactly as creation does. */
  rescheduleBooking(input: RescheduleBookingInput): Promise<Booking>;
  cancelBooking(bookingId: string, reason?: string): Promise<void>;
  /**
   * Name/phone/email search over this facility's member records, for the
   * "Member" customer picker — facility-scoped (members are a per-facility
   * customer record, not a platform-wide account) and requires no
   * membership plan to be searchable/bookable.
   */
  searchMembers(facilityId: string, query: string): Promise<{ id: string; fullName: string; phone: string; email: string | null }[]>;
  /** Guest Bookings dashboard — KPI tiles, status donut and revenue trend for GUEST bookings in [from, to] (YYYY-MM-DD). */
  getGuestBookingsSummary(facilityId: string, from: string, to: string): Promise<GuestBookingsSummary>;
  /** Guest Bookings dashboard — the filterable, paginated table of GUEST bookings. */
  listGuestBookings(facilityId: string, params: GuestBookingListParams): Promise<GuestBookingListResult>;
  /** A single booking row (any type) — used by the Guest Booking edit page. */
  getBooking(bookingId: string): Promise<Booking | null>;
  /** Edit a guest booking's guest fields. Reschedule stays on rescheduleBooking. */
  updateGuestBooking(
    bookingId: string,
    patch: { guestName: string; guestPhone?: string | null; partySize: number; notes?: string | null },
  ): Promise<Booking>;
  /** Mark a guest booking completed. */
  completeGuestBooking(bookingId: string): Promise<Booking>;
  /** Record an offline-collected payment and flip the booking to PAID. */
  recordGuestBookingPayment(bookingId: string, method: string, amountMinor: number): Promise<Booking>;
  /** Clone a guest booking into a new PENDING booking at newStart/newEnd (ISO). */
  duplicateGuestBooking(bookingId: string, newStart: string, newEnd: string): Promise<Booking>;
  /** Permanently delete a guest booking (blocked when it has a settled/refunded payment). */
  deleteGuestBooking(bookingId: string): Promise<void>;
  /** Email a PDF receipt for a guest booking (send-booking-receipt edge fn). */
  sendBookingReceipt(bookingId: string, email: string): Promise<void>;
}