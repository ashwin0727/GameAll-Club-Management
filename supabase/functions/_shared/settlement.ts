// ═══════════════════════════════════════════════════════════════════════════
// Shared settlement decision logic — Phase 5.
//
// Pure mirror of settle_payment's branching (0021_payment_settlement.sql) —
// used only for unit testing that decision logic without a live database.
// The SQL function is the actual source of truth at runtime (this module is
// not imported by settle-payment/index.ts, which only calls the RPC); this
// exists purely so "which source type routes to which validation, and what
// exception reason each rejection maps to" has a fast, no-DB-required test
// surface, following the same mirror-and-test convention as
// _shared/razorpay.ts's `nextPaymentOrderStatus`.
// ═══════════════════════════════════════════════════════════════════════════

export type SettlementSourceType = "MEMBERSHIP" | "MEMBER_BOOKING" | "GUEST_BOOKING";

export type SettlementExceptionReason =
  | "BOOKING_NO_LONGER_AVAILABLE"
  | "GUEST_CAPACITY_EXHAUSTED"
  | "MEMBERSHIP_INVALID"
  | "BUSINESS_VALIDATION_FAILED"
  | "DATABASE_SETTLEMENT_FAILURE";

export interface SettlementInput {
  paymentOrderStatus: "CREATED" | "ORDER_CREATED" | "PAYMENT_ATTEMPTED" | "PAYMENT_VERIFICATION_PENDING" | "PAYMENT_VERIFIED" | "AUTHORIZED" | "CAPTURED" | "COMPLETED" | "FAILED" | "CANCELLED" | "SETTLEMENT_EXCEPTION" | "REFUND_REQUESTED" | "REFUNDED";
  sourceType: SettlementSourceType;
  bookingId: string | null;
  membershipSessionBookingId: string | null;
  /** Only relevant for MEMBERSHIP: does the referenced plan still exist, belong to this facility, and remain active? */
  planStillValid?: boolean;
  /** Only relevant for MEMBER_BOOKING / GUEST_BOOKING-via-booking: does the booking row still exist and is it not cancelled? */
  bookingStillConfirmable?: boolean;
  /** Only relevant for GUEST_BOOKING via a released membership slot: is the row still CONFIRMED (not cancelled since)? */
  guestSlotStillConfirmed?: boolean;
}

export type SettlementOutcome =
  | { kind: "ALREADY_SETTLED" }
  | { kind: "NOT_READY" }
  | { kind: "SETTLED" }
  | { kind: "EXCEPTION"; reason: SettlementExceptionReason };

/**
 * Mirrors settle_payment's full decision tree: idempotency guard → status
 * gate → source-type routing → per-source revalidation → settle or record
 * an exception. Never mutates anything — purely "what WOULD settle_payment
 * decide", for unit testing the routing/reason-mapping logic in isolation.
 */
export function decideSettlement(input: SettlementInput): SettlementOutcome {
  if (input.paymentOrderStatus === "COMPLETED" || input.paymentOrderStatus === "SETTLEMENT_EXCEPTION") {
    return { kind: "ALREADY_SETTLED" };
  }
  if (input.paymentOrderStatus !== "CAPTURED") {
    return { kind: "NOT_READY" };
  }

  if (input.sourceType === "MEMBERSHIP") {
    return input.planStillValid ? { kind: "SETTLED" } : { kind: "EXCEPTION", reason: "MEMBERSHIP_INVALID" };
  }

  if (input.membershipSessionBookingId != null) {
    return input.guestSlotStillConfirmed ? { kind: "SETTLED" } : { kind: "EXCEPTION", reason: "BOOKING_NO_LONGER_AVAILABLE" };
  }

  if (input.bookingId != null) {
    return input.bookingStillConfirmable ? { kind: "SETTLED" } : { kind: "EXCEPTION", reason: "BOOKING_NO_LONGER_AVAILABLE" };
  }

  return { kind: "EXCEPTION", reason: "BUSINESS_VALIDATION_FAILED" };
}