import { assertEquals } from "jsr:@std/assert@1";
import {
  checkRefundEligibility,
  DEFAULT_CANCELLATION_POLICY,
  nextRefundStatus,
  paymentOrderStatusAfterRefund,
  refundableAmount,
  refundPercentForPolicy,
} from "./refunds.ts";

// ─── refundPercentForPolicy ──────────────────────────────────────────────

Deno.test("refundPercentForPolicy: >= full-refund window returns 100%", () => {
  assertEquals(refundPercentForPolicy(30), 100);
  assertEquals(refundPercentForPolicy(24), 100);
});

Deno.test("refundPercentForPolicy: between windows returns partial %", () => {
  assertEquals(refundPercentForPolicy(10), 50);
  assertEquals(refundPercentForPolicy(2), 50);
});

Deno.test("refundPercentForPolicy: below partial window returns 0%", () => {
  assertEquals(refundPercentForPolicy(1), 0);
  assertEquals(refundPercentForPolicy(0), 0);
});

Deno.test("refundPercentForPolicy: respects a custom facility policy", () => {
  const policy = { fullRefundHours: 48, fullRefundPercent: 90, partialRefundHours: 12, partialRefundPercent: 25 };
  assertEquals(refundPercentForPolicy(50, policy), 90);
  assertEquals(refundPercentForPolicy(20, policy), 25);
  assertEquals(refundPercentForPolicy(5, policy), 0);
});

Deno.test("refundPercentForPolicy: defaults match the spec's own worked example", () => {
  assertEquals(DEFAULT_CANCELLATION_POLICY.fullRefundHours, 24);
  assertEquals(DEFAULT_CANCELLATION_POLICY.partialRefundHours, 2);
});

// ─── refundableAmount ────────────────────────────────────────────────────

Deno.test("refundableAmount: no refunds yet — full amount refundable", () => {
  assertEquals(refundableAmount(80000, []), 80000);
});

Deno.test("refundableAmount: subtracts a processed partial refund (spec §5)", () => {
  assertEquals(refundableAmount(80000, [{ amountMinor: 30000, status: "PROCESSED" }]), 50000);
});

Deno.test("refundableAmount: multiple partials, spec §6 worked example", () => {
  const refunds: { amountMinor: number; status: "PROCESSED" }[] = [
    { amountMinor: 30000, status: "PROCESSED" },
    { amountMinor: 20000, status: "PROCESSED" },
  ];
  assertEquals(refundableAmount(100000, refunds), 50000);
});

Deno.test("refundableAmount: in-flight (REQUESTED/PROCESSING/PENDING) refunds also reduce the refundable amount — concurrent refund protection", () => {
  assertEquals(refundableAmount(80000, [{ amountMinor: 80000, status: "REQUESTED" }]), 0);
  assertEquals(refundableAmount(80000, [{ amountMinor: 80000, status: "PROCESSING" }]), 0);
  assertEquals(refundableAmount(80000, [{ amountMinor: 80000, status: "PENDING" }]), 0);
});

Deno.test("refundableAmount: a FAILED or CANCELLED refund does not consume refundable amount — retry allowed", () => {
  assertEquals(refundableAmount(80000, [{ amountMinor: 80000, status: "FAILED" }]), 80000);
  assertEquals(refundableAmount(80000, [{ amountMinor: 80000, status: "CANCELLED" }]), 80000);
});

// ─── checkRefundEligibility ──────────────────────────────────────────────

Deno.test("checkRefundEligibility: COMPLETED order with a captured payment and room to refund is eligible", () => {
  const result = checkRefundEligibility({ paymentOrderStatus: "COMPLETED", hasRazorpayPaymentId: true, requestedAmountMinor: 80000, refundableAmountMinor: 80000 });
  assertEquals(result, { eligible: true });
});

Deno.test("checkRefundEligibility: SETTLEMENT_EXCEPTION is refund-eligible (spec §16)", () => {
  const result = checkRefundEligibility({ paymentOrderStatus: "SETTLEMENT_EXCEPTION", hasRazorpayPaymentId: true, requestedAmountMinor: 80000, refundableAmountMinor: 80000 });
  assertEquals(result, { eligible: true });
});

Deno.test("checkRefundEligibility: PARTIALLY_REFUNDED order can still take another refund", () => {
  const result = checkRefundEligibility({ paymentOrderStatus: "PARTIALLY_REFUNDED", hasRazorpayPaymentId: true, requestedAmountMinor: 20000, refundableAmountMinor: 50000 });
  assertEquals(result, { eligible: true });
});

Deno.test("checkRefundEligibility: a merely CAPTURED (not yet settled) order is not eligible", () => {
  const result = checkRefundEligibility({ paymentOrderStatus: "CAPTURED", hasRazorpayPaymentId: true, requestedAmountMinor: 80000, refundableAmountMinor: 80000 });
  assertEquals(result, { eligible: false, reason: "NOT_CAPTURED" });
});

Deno.test("checkRefundEligibility: no razorpay_payment_id at all is never refundable", () => {
  const result = checkRefundEligibility({ paymentOrderStatus: "COMPLETED", hasRazorpayPaymentId: false, requestedAmountMinor: 80000, refundableAmountMinor: 80000 });
  assertEquals(result, { eligible: false, reason: "NO_PAYMENT" });
});

Deno.test("checkRefundEligibility: zero/negative requested amount is rejected", () => {
  assertEquals(checkRefundEligibility({ paymentOrderStatus: "COMPLETED", hasRazorpayPaymentId: true, requestedAmountMinor: 0, refundableAmountMinor: 80000 }), { eligible: false, reason: "INVALID_AMOUNT" });
  assertEquals(checkRefundEligibility({ paymentOrderStatus: "COMPLETED", hasRazorpayPaymentId: true, requestedAmountMinor: -100, refundableAmountMinor: 80000 }), { eligible: false, reason: "INVALID_AMOUNT" });
});

Deno.test("checkRefundEligibility: over-refund attempt is blocked (spec §3/§58)", () => {
  // Original ₹800, already refunded ₹500 → refundable ₹300; requesting ₹400 must BLOCK.
  const result = checkRefundEligibility({ paymentOrderStatus: "PARTIALLY_REFUNDED", hasRazorpayPaymentId: true, requestedAmountMinor: 40000, refundableAmountMinor: 30000 });
  assertEquals(result, { eligible: false, reason: "OVER_REFUND" });
});

// ─── nextRefundStatus (webhook state machine) ────────────────────────────

Deno.test("nextRefundStatus: REQUESTED -> created webhook -> PROCESSING", () => {
  assertEquals(nextRefundStatus("REQUESTED", "created"), "PROCESSING");
});

Deno.test("nextRefundStatus: PROCESSING -> processed webhook -> PROCESSED", () => {
  assertEquals(nextRefundStatus("PROCESSING", "processed"), "PROCESSED");
});

Deno.test("nextRefundStatus: REQUESTED -> processed webhook (skips straight to processed) -> PROCESSED", () => {
  assertEquals(nextRefundStatus("REQUESTED", "processed"), "PROCESSED");
});

Deno.test("nextRefundStatus: duplicate webhook (already PROCESSED) is a no-op (spec §21/§62)", () => {
  assertEquals(nextRefundStatus("PROCESSED", "processed"), null);
  assertEquals(nextRefundStatus("PROCESSED", "created"), null);
});

Deno.test("nextRefundStatus: out-of-order webhook (processed already applied, a stale 'created' arrives late) is a no-op", () => {
  assertEquals(nextRefundStatus("PROCESSED", "created"), null);
});

Deno.test("nextRefundStatus: failed webhook only applies from a still-open state", () => {
  assertEquals(nextRefundStatus("REQUESTED", "failed"), "FAILED");
  assertEquals(nextRefundStatus("PROCESSING", "failed"), "FAILED");
  assertEquals(nextRefundStatus("PROCESSED", "failed"), null);
});

// ─── paymentOrderStatusAfterRefund ───────────────────────────────────────

Deno.test("paymentOrderStatusAfterRefund: full refund -> REFUNDED", () => {
  assertEquals(paymentOrderStatusAfterRefund(80000, 80000), "REFUNDED");
});

Deno.test("paymentOrderStatusAfterRefund: partial refund -> PARTIALLY_REFUNDED", () => {
  assertEquals(paymentOrderStatusAfterRefund(80000, 30000), "PARTIALLY_REFUNDED");
});

Deno.test("paymentOrderStatusAfterRefund: cumulative partials reaching the full amount -> REFUNDED", () => {
  assertEquals(paymentOrderStatusAfterRefund(100000, 100000), "REFUNDED");
});