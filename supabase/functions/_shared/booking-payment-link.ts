// ═══════════════════════════════════════════════════════════════════════════
// Guest booking payment links — pure helpers shared by create-booking-payment-link and unit-tested on
// their own (booking-payment-link.test.ts): link lifetime, the text on the link, and whether an existing
// link can simply be handed back instead of creating a second one.
// ═══════════════════════════════════════════════════════════════════════════

/** How long the player has to pay. Razorpay needs expire_by to be at least 15 minutes ahead. */
export const LINK_LIFETIME_HOURS = 24;

/** `expire_by` as a unix timestamp (seconds), `hours` after `nowMs`. */
export function linkExpiryUnix(nowMs: number, hours = LINK_LIFETIME_HOURS): number {
  return Math.floor(nowMs / 1000) + Math.round(hours * 3600);
}

/** What the player sees on the Razorpay page, e.g. "Badminton Court 1 · 20 Oct 2026, 6:00 PM – 8:00 PM". */
export function linkDescription(courtName: string | null, startIso: string, endIso: string, timeZone: string): string {
  const day = new Intl.DateTimeFormat("en-IN", { timeZone, day: "numeric", month: "short", year: "numeric" }).format(new Date(startIso));
  const time = (iso: string) =>
    new Intl.DateTimeFormat("en-IN", { timeZone, hour: "numeric", minute: "2-digit", hour12: true }).format(new Date(iso)).toUpperCase();
  return `${courtName?.trim() || "Court booking"} · ${day}, ${time(startIso)} – ${time(endIso)}`;
}

export interface ExistingLink {
  razorpayPaymentLinkId: string | null;
  paymentLinkUrl: string | null;
  paymentLinkStatus: string | null;
  expiresAt: string | null;
}

/** A link we already made is reused only while it is open, has a URL, and has not run out. */
export function reusableLink(row: ExistingLink, nowMs: number): boolean {
  if (!row.razorpayPaymentLinkId || !row.paymentLinkUrl) return false;
  if (row.paymentLinkStatus !== "CREATED") return false;
  return row.expiresAt != null && new Date(row.expiresAt).getTime() > nowMs;
}

/** Razorpay's own status for a payment link, mapped to ours. Null for anything we don't act on. */
export function linkStatusFromRazorpay(status: string | null | undefined): "CREATED" | "PAID" | "CANCELLED" | "EXPIRED" | null {
  switch (status) {
    case "created":
    case "partially_paid":
      return "CREATED";
    case "paid":
      return "PAID";
    case "cancelled":
      return "CANCELLED";
    case "expired":
      return "EXPIRED";
    default:
      return null;
  }
}
