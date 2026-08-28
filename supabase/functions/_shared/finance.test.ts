import { assertEquals } from "jsr:@std/assert@1";
import {
  classifyTransactionSource,
  computeGrossRevenue,
  computeNetRevenue,
  computeProcessedRefunds,
  computeRevenueBreakdown,
  countMembershipIncludedUsage,
  countPaymentOrdersByOutcome,
  hasDuplicatePaymentId,
  hasDuplicateRefundId,
  type FinancePayment,
  type FinanceRefund,
} from "./finance.ts";

// ─── classifyTransactionSource ───────────────────────────────────────────

Deno.test("classifyTransactionSource: uses payment_orders.source_type when present", () => {
  assertEquals(classifyTransactionSource("GUEST_BOOKING", false), "GUEST_BOOKING");
});

Deno.test("classifyTransactionSource: falls back to MEMBERSHIP for a manual/cash membership payment with no payment_order", () => {
  assertEquals(classifyTransactionSource(null, true), "MEMBERSHIP");
});

Deno.test("classifyTransactionSource: never classifies a membership payment as booking revenue", () => {
  assertEquals(classifyTransactionSource("MEMBERSHIP", true), "MEMBERSHIP");
});

// ─── computeGrossRevenue / computeProcessedRefunds / computeNetRevenue ───

function payment(amountMinor: number, status: FinancePayment["status"] = "paid", sourceType: FinancePayment["sourceType"] = "MEMBER_BOOKING"): FinancePayment {
  return { amountMinor, status, sourceType };
}

function refund(amountMinor: number, status: FinanceRefund["status"]): FinanceRefund {
  return { amountMinor, status };
}

Deno.test("computeGrossRevenue: only 'paid' payments count", () => {
  const payments = [payment(80000, "paid"), payment(50000, "created"), payment(30000, "failed")];
  assertEquals(computeGrossRevenue(payments), 80000);
});

Deno.test("computeProcessedRefunds: only PROCESSED refunds count — spec §Critical Failed/Pending Refund Test", () => {
  const refunds = [refund(80000, "PROCESSED"), refund(80000, "FAILED"), refund(80000, "PENDING"), refund(80000, "REQUESTED"), refund(80000, "PROCESSING")];
  assertEquals(computeProcessedRefunds(refunds), 80000);
});

Deno.test("computeNetRevenue: full refund test — spec §Full Refunds", () => {
  assertEquals(computeNetRevenue(80000, 80000), 0);
});

Deno.test("computeNetRevenue: partial refund test — spec §Partial Refunds", () => {
  assertEquals(computeNetRevenue(80000, 30000), 50000);
});

Deno.test("computeNetRevenue: failed refund never reduces net revenue — spec §Critical Failed Refund Test", () => {
  const gross = computeGrossRevenue([payment(80000)]);
  const refunded = computeProcessedRefunds([refund(80000, "FAILED")]);
  assertEquals(refunded, 0);
  assertEquals(computeNetRevenue(gross, refunded), 80000);
});

Deno.test("computeNetRevenue: pending refund never reduces net revenue yet — spec §Critical Pending Refund Test", () => {
  const gross = computeGrossRevenue([payment(80000)]);
  const refunded = computeProcessedRefunds([refund(80000, "PENDING")]);
  assertEquals(refunded, 0);
  assertEquals(computeNetRevenue(gross, refunded), 80000);
});

// ─── computeRevenueBreakdown — spec §Critical Finance Test ───────────────

Deno.test("computeRevenueBreakdown: the spec's own worked example (§Critical Finance Test)", () => {
  const payments: FinancePayment[] = [
    payment(150000, "paid", "MEMBERSHIP"), // ₹1,500 membership
    payment(50000, "paid", "MEMBER_BOOKING"), // ₹500 member booking
    payment(80000, "paid", "GUEST_BOOKING"), // ₹800 guest booking
    payment(70000, "paid", "GUEST_BOOKING"), // ₹700 guest booking
  ];
  const refunds: FinanceRefund[] = [refund(80000, "PROCESSED")];

  const result = computeRevenueBreakdown(payments, refunds);

  assertEquals(result.membershipRevenueMinor, 150000);
  assertEquals(result.memberBookingRevenueMinor, 50000);
  assertEquals(result.guestBookingRevenueMinor, 150000); // 80000 + 70000
  assertEquals(computeGrossRevenue(payments), 350000);
  assertEquals(result.refundsMinor, 80000);
  assertEquals(result.netRevenueMinor, 270000);
});

Deno.test("computeRevenueBreakdown: membership revenue + refund — spec §Membership Revenue + Refund", () => {
  const result = computeRevenueBreakdown([payment(150000, "paid", "MEMBERSHIP")], [refund(50000, "PROCESSED")]);
  assertEquals(result.membershipRevenueMinor, 150000);
  assertEquals(result.refundsMinor, 50000);
  assertEquals(result.netRevenueMinor, 100000);
});

Deno.test("computeRevenueBreakdown: guest revenue + full refund — spec §Guest Revenue + Refund", () => {
  const result = computeRevenueBreakdown([payment(80000, "paid", "GUEST_BOOKING")], [refund(80000, "PROCESSED")]);
  assertEquals(result.guestBookingRevenueMinor, 80000);
  assertEquals(result.netRevenueMinor, 0);
});

Deno.test("computeRevenueBreakdown: non-paid payments are excluded from every source bucket", () => {
  const result = computeRevenueBreakdown([payment(80000, "created", "GUEST_BOOKING")], []);
  assertEquals(result.guestBookingRevenueMinor, 0);
});

// ─── countMembershipIncludedUsage — spec §Critical Included Membership Test

Deno.test("countMembershipIncludedUsage: counts usage without ever adding to paid revenue", () => {
  const result = countMembershipIncludedUsage(3);
  assertEquals(result.count, 3);
  assertEquals(result.paidRevenueMinor, 0);
});

// ─── countPaymentOrdersByOutcome ──────────────────────────────────────────

Deno.test("countPaymentOrdersByOutcome: splits FAILED vs. still-in-flight statuses", () => {
  const result = countPaymentOrdersByOutcome(["FAILED", "FAILED", "CREATED", "AUTHORIZED", "PAYMENT_VERIFIED"]);
  assertEquals(result.failed, 2);
  assertEquals(result.pending, 3);
});

Deno.test("countPaymentOrdersByOutcome: empty input is all zeros", () => {
  assertEquals(countPaymentOrdersByOutcome([]), { failed: 0, pending: 0 });
});

// ─── Duplicate protection ─────────────────────────────────────────────────

Deno.test("hasDuplicatePaymentId: a repeated razorpay_payment_id is flagged — spec §Critical Duplicate Transaction Test", () => {
  assertEquals(hasDuplicatePaymentId(["pay_123", "pay_456"]), false);
  assertEquals(hasDuplicatePaymentId(["pay_123", "pay_123"]), true);
});

Deno.test("hasDuplicateRefundId: a repeated razorpay_refund_id is flagged — spec §Critical Duplicate Refund Test", () => {
  assertEquals(hasDuplicateRefundId(["rfnd_123", "rfnd_456"]), false);
  assertEquals(hasDuplicateRefundId(["rfnd_123", "rfnd_123"]), true);
});