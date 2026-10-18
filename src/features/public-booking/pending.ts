import type { PublicBookingConfirmation } from "./types";

/**
 * A player who has made bookings that need an online advance leaves the page to pay and comes back. This keeps
 * what is needed to pick up where they left off (and to ask the server whether each booking is confirmed yet).
 * Per browser tab, and only for as long as the holds last, so it never outlives the bookings it refers to.
 */
export interface StoredPending {
  phone: string;
  /** Held bookings still waiting for their advance. */
  advance: PublicBookingConfirmation[];
  /** Bookings made alongside them that need no advance — already confirmed. */
  others: PublicBookingConfirmation[];
  notice: string | null;
}

const keyFor = (facilityId: string) => `public-booking:pending:${facilityId}`;

export function savePending(facilityId: string, value: StoredPending): void {
  try {
    sessionStorage.setItem(keyFor(facilityId), JSON.stringify(value));
  } catch {
    // Without storage the player simply has to stay on the page while paying.
  }
}

export function loadPending(facilityId: string): StoredPending | null {
  try {
    const raw = sessionStorage.getItem(keyFor(facilityId));
    if (!raw) return null;
    const v = JSON.parse(raw) as StoredPending;
    return Array.isArray(v.advance) && v.advance.length > 0 && typeof v.phone === "string" ? v : null;
  } catch {
    return null;
  }
}

export function clearPending(facilityId: string): void {
  try {
    sessionStorage.removeItem(keyFor(facilityId));
  } catch {
    // nothing to clear
  }
}
