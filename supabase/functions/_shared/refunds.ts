// ═══════════════════════════════════════════════════════════════════════════
// Shared cancellation/refund decision logic — Phase 6.
//
// Pure mirrors of the SQL functions in 0023_cancellation_refunds.sql
// (refund_percent_for_policy, refundable_amount, apply_refund_webhook's
// state machine) — pure functions only, no Supabase client, no Razorpay
// HTTP call, so this module can be unit tested with plain `deno test`
// without a live DB, matching the razorpay.ts / settlement.ts convention.
// ═══════════════════════════════════════════════════════════════════════════

export interface CancellationPolicy {
  fullRefundHours: number;
  fullRefundPercent: number;
  partialRefundHours: number;
  partialRefundPercent: number;
}

export const DEFAULT_CANCELLATION_POLICY: CancellationPolicy = {
  fullRefundHours: 24,
  fullRefundPercent: 100,
  partialRefundHours: 2,
  partialRefundPercent: 50,
};

/** Mirrors refund_percent_for_policy — how much of the refundable amount a cancellation this many hours before start should get back. */
export function refundPercentForPolicy(hoursUntilStart: number, policy: CancellationPolicy = DEFAULT_CANCELLATION_POLICY): number {
  if (hoursUntilStart >= policy.fullRefundHours) return policy.fullRefundPercent;
  if (hoursUntilStart >= policy.partialRefundHours) return policy.partialRefundPercent;
  return 0;
}

export type RefundStatus = "REQUESTED" | "PROCESSING" | "PENDING" | "PROCESSED" | "FAILED" | "CANCELLED";

/** Mirrors refundable_amount — captured amount minus processed refunds minus in-flight refunds. Never trusts a client-claimed amount. */
export function refundableAmount(capturedAmountMinor: number, refunds: { amountMinor: number; status: RefundStatus }[]): number {
  const processed = refunds.filter((r) => r.status === "PROCESSED").reduce((sum, r) => sum + r.amountMinor, 0);
  const inFlight = refunds.filter((r) => r.status === "REQUESTED" || r.status === "PROCESSING" || r.status === "PENDING").reduce((sum, r) => sum + r.amountMinor, 0);
  return capturedAmountMinor - processed - inFlight;
}

export interface RefundEligibilityInput {
  paymentOrderStatus: "CREATED" | "ORDER_CREATED" | "PAYMENT_ATTEMPTED" | "PAYMENT_VERIFICATION_PENDING" | "PAYMENT_VERIFIED" | "AUTHORIZED" | "CAPTURED" | "COMPLETED" | "SETTLEMENT_EXCEPTION" | "FAILED" | "CANCELLED" | "REFUND_REQUESTED" | "PARTIALLY_REFUNDED" | "REFUNDED";
  hasRazorpayPaymentId: boolean;
  requestedAmountMinor: number;
  refundableAmountMinor: number;
}

export type RefundEligibilityResult = { eligible: true } | { eligible: false; reason: "NOT_CAPTURED" | "NO_PAYMENT" | "INVALID_AMOUNT" | "OVER_REFUND" };

/** Mirrors request_refund's own validation gate, ahead of the DB round-trip — spec §7 "canRefund". */
export function checkRefundEligibility(input: RefundEligibilityInput): RefundEligibilityResult {
  if (!["COMPLETED", "SETTLEMENT_EXCEPTION", "PARTIALLY_REFUNDED"].includes(input.paymentOrderStatus)) {
    return { eligible: false, reason: "NOT_CAPTURED" };
  }
  if (!input.hasRazorpayPaymentId) {
    return { eligible: false, reason: "NO_PAYMENT" };
  }
  if (input.requestedAmountMinor <= 0) {
    return { eligible: false, reason: "INVALID_AMOUNT" };
  }
  if (input.requestedAmountMinor > input.refundableAmountMinor) {
    return { eligible: false, reason: "OVER_REFUND" };
  }
  return { eligible: true };
}

const REFUND_RANK: Partial<Record<RefundStatus, number>> = {
  REQUESTED: 0,
  PROCESSING: 1,
  PENDING: 2,
  PROCESSED: 3,
};

/** Mirrors apply_refund_webhook's forward-only, idempotent decision — given the refund's current status and a webhook-derived target, returns the status that should be written, or `null` for a no-op (duplicate/out-of-order delivery, or already terminal). */
export function nextRefundStatus(current: RefundStatus, target: "created" | "processed" | "failed"): RefundStatus | null {
  if (target === "failed") {
    return current === "REQUESTED" || current === "PROCESSING" || current === "PENDING" ? "FAILED" : null;
  }
  const targetStatus: RefundStatus = target === "processed" ? "PROCESSED" : "PROCESSING";
  const currentRank = REFUND_RANK[current];
  const targetRank = REFUND_RANK[targetStatus];
  if (currentRank === undefined || targetRank === undefined) return null;
  return targetRank > currentRank ? targetStatus : null;
}

/** Mirrors apply_refund_webhook's payment_orders.status update once a refund reaches PROCESSED — full vs. partial, driven by the running total, never by this one refund's amount alone. */
export function paymentOrderStatusAfterRefund(capturedAmountMinor: number, totalProcessedMinor: number): "REFUNDED" | "PARTIALLY_REFUNDED" {
  return totalProcessedMinor >= capturedAmountMinor ? "REFUNDED" : "PARTIALLY_REFUNDED";
}