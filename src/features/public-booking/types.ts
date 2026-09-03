/**
 * Types for the public (unauthenticated) court booking flow at
 * /book/<facilityId>.
 *
 * Everything here is what an anonymous player is allowed to see. There is
 * deliberately no session id, batch id, capacity, member count or release
 * count anywhere in these shapes — the server-side RPCs never return them,
 * and the guest never needs them to pick a time.
 */

export interface PublicBookingSport {
  facilitySportId: string;
  name: string;
}

export interface PublicBookingFacility {
  facilityId: string;
  facilityName: string;
  city: string;
  currency: string;
  sports: PublicBookingSport[];
}

/** One bookable hour on one court. `available` already accounts for
 *  existing bookings, operating hours and membership protection. */
export interface PublicBookingSlot {
  startTime: string;
  endTime: string;
  available: boolean;
  priceMinor: number;
}

export interface PublicBookingCourt {
  courtId: string;
  courtName: string;
  slots: PublicBookingSlot[];
}

export const BOOKING_PURPOSES = [
  "Practice",
  "Friendly Match",
  "Tournament",
  "Training",
  "Other",
] as const;

export type BookingPurpose = (typeof BOOKING_PURPOSES)[number];

export interface PublicGuestDetails {
  fullName: string;
  phone: string;
  email: string;
  altPhone: string;
  address: string;
  purpose: string;
  specialRequest: string;
}

export interface PublicBookingConfirmation {
  bookingId: string;
  code: string;
  facilityName: string;
  sportName: string;
  courtName: string;
  startTime: string;
  endTime: string;
  guestName: string;
  guestPhone: string;
  amountMinor: number;
  currency: string;
  paymentStatus: string;
  bookingStatus: string;
}
