import type { BookingService } from "@/services/bookings/booking.service";
import { SupabaseBookingService } from "@/services/bookings/supabase-booking.service";

let instance: BookingService | null = null;

/** Single entry point for the bookings implementation. */
export function getBookingService(): BookingService {
  instance ??= new SupabaseBookingService();
  return instance;
}

/** Test seam: overrides the singleton for the current module instance. */
export function setBookingService(service: BookingService | null): void {
  instance = service;
}

export type { BookingService } from "@/services/bookings/booking.service";