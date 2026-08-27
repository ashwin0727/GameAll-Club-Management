import { assertEquals } from "jsr:@std/assert@1";
import { decideSettlement } from "./settlement.ts";

const base = {
  paymentOrderStatus: "CAPTURED" as const,
  bookingId: null,
  membershipSessionBookingId: null,
};

Deno.test("settlement routing: MEMBER_BOOKING settles when the booking is still confirmable", () => {
  const outcome = decideSettlement({ ...base, sourceType: "MEMBER_BOOKING", bookingId: "b-1", bookingStillConfirmable: true });
  assertEquals(outcome, { kind: "SETTLED" });
});

Deno.test("settlement routing: MEMBER_BOOKING/GUEST_BOOKING-via-booking becomes an exception when the booking is no longer confirmable (e.g. cancelled)", () => {
  const outcome = decideSettlement({ ...base, sourceType: "MEMBER_BOOKING", bookingId: "b-1", bookingStillConfirmable: false });
  assertEquals(outcome, { kind: "EXCEPTION", reason: "BOOKING_NO_LONGER_AVAILABLE" });
});

Deno.test("settlement routing: GUEST_BOOKING via a released membership slot settles when the slot booking is still CONFIRMED", () => {
  const outcome = decideSettlement({ ...base, sourceType: "GUEST_BOOKING", membershipSessionBookingId: "msb-1", guestSlotStillConfirmed: true });
  assertEquals(outcome, { kind: "SETTLED" });
});

Deno.test("settlement routing: GUEST_BOOKING via a released membership slot becomes an exception when the slot was cancelled since", () => {
  const outcome = decideSettlement({ ...base, sourceType: "GUEST_BOOKING", membershipSessionBookingId: "msb-1", guestSlotStillConfirmed: false });
  assertEquals(outcome, { kind: "EXCEPTION", reason: "BOOKING_NO_LONGER_AVAILABLE" });
});

Deno.test("settlement routing: MEMBERSHIP activates when the plan is still valid", () => {
  const outcome = decideSettlement({ ...base, sourceType: "MEMBERSHIP", planStillValid: true });
  assertEquals(outcome, { kind: "SETTLED" });
});

Deno.test("settlement routing: MEMBERSHIP becomes MEMBERSHIP_INVALID exception when the plan is no longer valid (e.g. deactivated)", () => {
  const outcome = decideSettlement({ ...base, sourceType: "MEMBERSHIP", planStillValid: false });
  assertEquals(outcome, { kind: "EXCEPTION", reason: "MEMBERSHIP_INVALID" });
});

Deno.test("settlement routing: GUEST_BOOKING with neither a booking id nor a membership slot id is a BUSINESS_VALIDATION_FAILED exception, never silently settled", () => {
  const outcome = decideSettlement({ ...base, sourceType: "GUEST_BOOKING" });
  assertEquals(outcome, { kind: "EXCEPTION", reason: "BUSINESS_VALIDATION_FAILED" });
});

Deno.test("idempotency: an order already COMPLETED is never re-settled", () => {
  const outcome = decideSettlement({ ...base, paymentOrderStatus: "COMPLETED", sourceType: "MEMBER_BOOKING", bookingId: "b-1", bookingStillConfirmable: true });
  assertEquals(outcome, { kind: "ALREADY_SETTLED" });
});

Deno.test("idempotency: an order already at SETTLEMENT_EXCEPTION is never re-settled or re-flagged", () => {
  const outcome = decideSettlement({ ...base, paymentOrderStatus: "SETTLEMENT_EXCEPTION", sourceType: "MEMBER_BOOKING", bookingId: "b-1", bookingStillConfirmable: true });
  assertEquals(outcome, { kind: "ALREADY_SETTLED" });
});

Deno.test("settlement never runs before CAPTURED — an AUTHORIZED (or any pre-capture) order is NOT_READY, not settled", () => {
  const outcome = decideSettlement({ ...base, paymentOrderStatus: "AUTHORIZED", sourceType: "MEMBER_BOOKING", bookingId: "b-1", bookingStillConfirmable: true });
  assertEquals(outcome, { kind: "NOT_READY" });
});

Deno.test("settlement never runs on a FAILED payment", () => {
  const outcome = decideSettlement({ ...base, paymentOrderStatus: "FAILED", sourceType: "MEMBER_BOOKING", bookingId: "b-1", bookingStillConfirmable: true });
  assertEquals(outcome, { kind: "NOT_READY" });
});