import type { PublicGuestDetails } from "./types";

export type GuestFieldErrors = Partial<Record<keyof PublicGuestDetails, string>>;

export const EMPTY_GUEST: PublicGuestDetails = {
  fullName: "",
  phone: "",
  email: "",
  altPhone: "",
  address: "",
  purpose: "",
  specialRequest: "",
};

/**
 * Mirrors the server's own checks in `public_create_guest_booking` so the
 * player gets the correction inline instead of a round-trip. The server
 * stays authoritative — this never replaces it.
 */
export function validateGuest(guest: PublicGuestDetails): GuestFieldErrors {
  const errors: GuestFieldErrors = {};

  if (!guest.fullName.trim()) {
    errors.fullName = "Please enter your name.";
  }

  const digits = guest.phone.replace(/\D/g, "");
  if (!digits) {
    errors.phone = "Please enter your mobile number.";
  } else if (digits.length < 10 || digits.length > 15) {
    errors.phone = "Please enter a valid mobile number.";
  }

  if (guest.email.trim() && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(guest.email.trim())) {
    errors.email = "Please enter a valid email address.";
  }

  if (guest.altPhone.trim()) {
    const alt = guest.altPhone.replace(/\D/g, "");
    if (alt.length < 10 || alt.length > 15) {
      errors.altPhone = "Please enter a valid phone number.";
    }
  }

  return errors;
}

/** Money arrives in minor units everywhere in this app. */
export function formatMoney(amountMinor: number, currency = "INR"): string {
  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency,
    maximumFractionDigits: 0,
  }).format((amountMinor ?? 0) / 100);
}

export function formatSlotTime(iso: string): string {
  return new Date(iso).toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit", hour12: true });
}

export function formatSlotRange(startIso: string, endIso: string): string {
  return `${formatSlotTime(startIso)} – ${formatSlotTime(endIso)}`;
}

export function formatBookingDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", { day: "numeric", month: "long", year: "numeric" });
}

/** Whole hours, which is the only granularity the slot grid offers. */
export function durationLabel(startIso: string, endIso: string): string {
  const minutes = Math.round((new Date(endIso).getTime() - new Date(startIso).getTime()) / 60000);
  if (minutes % 60 === 0) {
    const hours = minutes / 60;
    return `${hours} hour${hours === 1 ? "" : "s"}`;
  }
  return `${minutes} minutes`;
}

/** `YYYY-MM-DD` in the browser's local calendar, which the slot RPC expects. */
export function toDateParam(date: Date): string {
  const y = date.getFullYear();
  const m = `${date.getMonth() + 1}`.padStart(2, "0");
  const d = `${date.getDate()}`.padStart(2, "0");
  return `${y}-${m}-${d}`;
}
