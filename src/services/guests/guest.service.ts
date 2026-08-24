import type { Booking } from "@/features/bookings/types";
import type { GuestInput, GuestPlayer, GuestStats } from "@/features/guests/types";

export interface GuestService {
  /** Backend-filtered search by name or phone — never loads the full guest list client-side. */
  searchGuests(facilityId: string, query: string): Promise<GuestPlayer[]>;
  listGuests(facilityId: string, opts?: { status?: "ACTIVE" | "INACTIVE"; limit?: number; offset?: number }): Promise<GuestPlayer[]>;
  getGuest(guestId: string): Promise<GuestPlayer | null>;
  /**
   * The single write path for both "search existing" and "create new" in
   * the Booking → Guest flow — matches by normalized phone within the
   * facility and returns the existing profile untouched if found.
   */
  findOrCreateGuest(input: GuestInput): Promise<GuestPlayer>;
  updateGuest(guestId: string, patch: Partial<GuestInput> & { status?: "ACTIVE" | "INACTIVE" }): Promise<GuestPlayer>;
  getGuestStats(guestId: string): Promise<GuestStats>;
  /** Paginated, most recent first — never loads unlimited history. */
  getGuestBookings(guestId: string, opts?: { limit?: number; offset?: number }): Promise<Booking[]>;
}