import { assertEquals } from "jsr:@std/assert";
import { linkDescription, linkExpiryUnix, linkStatusFromRazorpay, reusableLink } from "./booking-payment-link.ts";

Deno.test("linkExpiryUnix is 24 hours ahead by default, in seconds", () => {
  assertEquals(linkExpiryUnix(1_700_000_000_000), 1_700_000_000 + 24 * 3600);
  assertEquals(linkExpiryUnix(1_700_000_000_000, 1), 1_700_000_000 + 3600);
});

Deno.test("linkDescription reads court, day and the time range in the facility's zone", () => {
  const text = linkDescription("Court 1", "2026-10-20T12:30:00Z", "2026-10-20T14:30:00Z", "Asia/Kolkata");
  assertEquals(text, "Court 1 · 20 Oct 2026, 6:00 PM – 8:00 PM");
  assertEquals(linkDescription(null, "2026-10-20T12:30:00Z", "2026-10-20T14:30:00Z", "Asia/Kolkata").startsWith("Court booking · "), true);
});

Deno.test("an open, unexpired link is reused; anything else is not", () => {
  const now = Date.parse("2026-10-15T10:00:00Z");
  const open = { razorpayPaymentLinkId: "plink_1", paymentLinkUrl: "https://rzp.io/i/x", paymentLinkStatus: "CREATED", expiresAt: "2026-10-16T10:00:00Z" };
  assertEquals(reusableLink(open, now), true);
  assertEquals(reusableLink({ ...open, expiresAt: "2026-10-15T09:00:00Z" }, now), false);
  assertEquals(reusableLink({ ...open, paymentLinkStatus: "CANCELLED" }, now), false);
  assertEquals(reusableLink({ ...open, paymentLinkStatus: "PAID" }, now), false);
  assertEquals(reusableLink({ ...open, paymentLinkUrl: null }, now), false);
  assertEquals(reusableLink({ ...open, razorpayPaymentLinkId: null }, now), false);
});

Deno.test("Razorpay link statuses map to ours", () => {
  assertEquals(linkStatusFromRazorpay("created"), "CREATED");
  assertEquals(linkStatusFromRazorpay("paid"), "PAID");
  assertEquals(linkStatusFromRazorpay("cancelled"), "CANCELLED");
  assertEquals(linkStatusFromRazorpay("expired"), "EXPIRED");
  assertEquals(linkStatusFromRazorpay("weird"), null);
});
