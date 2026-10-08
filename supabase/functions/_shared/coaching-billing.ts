// ═══════════════════════════════════════════════════════════════════════════
// Coaching enrollment billing — pure helpers shared by the
// create/cancel-coaching-enrollment-billing functions and razorpay-webhook, so
// the event → status mapping and the amount maths live in one unit-tested place.
// ═══════════════════════════════════════════════════════════════════════════

import type { MembershipSubscriptionStatus } from "./razorpay.ts";

export type CoachingBillingStatus =
  | "CREATED"
  | "AUTHENTICATED"
  | "ACTIVE"
  | "PENDING"
  | "HALTED"
  | "PAID"
  | "CANCELLED"
  | "COMPLETED"
  | "EXPIRED";

/** The subscription status vocabulary is lower-case on the membership side, upper-case on coaching. */
export function subscriptionStatusToCoaching(status: MembershipSubscriptionStatus): CoachingBillingStatus {
  return status.toUpperCase() as CoachingBillingStatus;
}

/** `payment_link.*` webhook event → billing status, or null for events we don't act on. */
export function mapPaymentLinkEventToStatus(eventType: string): CoachingBillingStatus | null {
  switch (eventType) {
    case "payment_link.paid":
      return "PAID";
    case "payment_link.cancelled":
      return "CANCELLED";
    case "payment_link.expired":
      return "EXPIRED";
    default:
      return null;
  }
}

/**
 * Splits an enrollment's total obligation into the amount of ONE monthly
 * charge. Returns null when the total does not divide evenly — the client
 * always builds the total as (cycle fee × cycles), so a remainder means the
 * two sides disagree about the cycle count and billing must not start.
 */
export function cycleAmountMinor(totalMinor: number, cycles: number): number | null {
  if (!Number.isInteger(totalMinor) || !Number.isInteger(cycles) || totalMinor <= 0 || cycles < 1) return null;
  if (totalMinor % cycles !== 0) return null;
  return totalMinor / cycles;
}

/** Razorpay wants a country code; the app stores bare 10-digit Indian mobiles. */
export function toRazorpayContact(phone: string | null | undefined): string | null {
  const digits = (phone ?? "").replace(/\D/g, "");
  if (digits.length === 10) return `+91${digits}`;
  if (digits.length === 12 && digits.startsWith("91")) return `+${digits}`;
  return null;
}

/** Razorpay's own subscription status string → the billing row's status, or null for one we don't know. */
export function razorpaySubscriptionStatusToCoaching(status: string | undefined | null): CoachingBillingStatus | null {
  switch (status) {
    case "created":
      return "CREATED";
    case "authenticated":
      return "AUTHENTICATED";
    case "active":
      return "ACTIVE";
    case "pending":
      return "PENDING";
    case "halted":
      return "HALTED";
    case "cancelled":
      return "CANCELLED";
    case "completed":
      return "COMPLETED";
    case "expired":
      return "EXPIRED";
    default:
      return null;
  }
}

/**
 * A fetched Razorpay payment link lists its payments either as an array or a single object depending on
 * account/API version; returns the first captured payment's id and amount, or null if none is visible yet.
 */
export function extractLinkPayment(
  link: { payments?: unknown; amount_paid?: number },
): { paymentId: string; amountMinor: number } | null {
  const raw = link.payments;
  const list = Array.isArray(raw) ? raw : raw && typeof raw === "object" ? [raw] : [];
  for (const p of list as { payment_id?: string; id?: string; amount?: number; status?: string }[]) {
    const id = p.payment_id ?? p.id;
    if (!id) continue;
    if (p.status && !["captured", "authorized", "paid"].includes(p.status)) continue;
    const amount = p.amount ?? link.amount_paid ?? 0;
    if (amount > 0) return { paymentId: id, amountMinor: amount };
  }
  return null;
}
