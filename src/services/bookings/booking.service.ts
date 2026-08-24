import type { Booking, NewBookingInput, RescheduleBookingInput } from "@/features/bookings/types";

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
  /** Name/email search over registered members, for the "Member" customer picker. */
  searchMembers(query: string): Promise<{ id: string; fullName: string; email: string }[]>;
}