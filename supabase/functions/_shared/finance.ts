// ═══════════════════════════════════════════════════════════════════════════
// Finance & Revenue Management — Phase 7.
//
// Pure mirrors of the SQL aggregation in 0024_finance.sql
// (get_finance_summary / get_revenue_breakdown's classification and math) —
// pure functions only, no Supabase client, no database — so this module can
// be unit tested with plain `deno test`, matching the razorpay.ts/
// settlement.ts/refunds.ts convention. The database is still the
// authoritative source for the real app; this module exists only to let
// the arithmetic/classification rules themselves be verified without a
// live DB (spec §"Critical Finance Test" and friends).
// ═══════════════════════════════════════════════════════════════════════════

export type RevenueSourceType = "MEMBERSHIP" | "MEMBER_BOOKING" | "GUEST_BOOKING";
export type PaymentRowStatus = "created" | "paid" | "failed" | "refunded";
export type RefundRowStatus = "REQUESTED" | "PROCESSING" | "PENDING" | "PROCESSED" | "FAILED" | "CANCELLED";

/** Mirrors finance_transactions_view's source_type expression exactly: payment_orders.source_type when present, else classified off payments.membership_id. */
export function classifyTransactionSource(paymentOrderSourceType: RevenueSourceType | null, hasMembershipId: boolean): RevenueSourceType {
  if (paymentOrderSourceType) return paymentOrderSourceType;
  return hasMembershipId ? "MEMBERSHIP" : "MEMBER_BOOKING";
}

export interface FinancePayment {
  amountMinor: number;
  status: PaymentRowStatus;
  sourceType: RevenueSourceType;
}

export interface FinanceRefund {
  amountMinor: number;
  status: RefundRowStatus;
}

/** Mirrors get_finance_summary's gross-revenue sum: only status = 'paid' payments count — a payment_order that never reached CAPTURED never produced a payments row at all, so no extra filtering for pending/failed is needed here (spec §"Gross Revenue"). */
export function computeGrossRevenue(payments: FinancePayment[]): number {
  return payments.filter((p) => p.status === "paid").reduce((sum, p) => sum + p.amountMinor, 0);
}

/** Mirrors the refund sum: only PROCESSED refunds count — PENDING/PROCESSING/REQUESTED/FAILED/CANCELLED never reduce finalized revenue (spec §"Refunds" / §"Critical Failed Refund Test" / §"Critical Pending Refund Test"). */
export function computeProcessedRefunds(refunds: FinanceRefund[]): number {
  return refunds.filter((r) => r.status === "PROCESSED").reduce((sum, r) => sum + r.amountMinor, 0);
}

export function computeNetRevenue(grossMinor: number, refundsMinor: number): number {
  return grossMinor - refundsMinor;
}

export interface RevenueBreakdown {
  membershipRevenueMinor: number;
  memberBookingRevenueMinor: number;
  guestBookingRevenueMinor: number;
  refundsMinor: number;
  netRevenueMinor: number;
}

/** Mirrors get_revenue_breakdown's per-source sums plus the shared refund/net figures — spec §"Revenue By Source". */
export function computeRevenueBreakdown(payments: FinancePayment[], refunds: FinanceRefund[]): RevenueBreakdown {
  const paid = payments.filter((p) => p.status === "paid");
  const sumBySource = (source: RevenueSourceType) => paid.filter((p) => p.sourceType === source).reduce((sum, p) => sum + p.amountMinor, 0);
  const gross = computeGrossRevenue(payments);
  const refundsMinor = computeProcessedRefunds(refunds);
  return {
    membershipRevenueMinor: sumBySource("MEMBERSHIP"),
    memberBookingRevenueMinor: sumBySource("MEMBER_BOOKING"),
    guestBookingRevenueMinor: sumBySource("GUEST_BOOKING"),
    refundsMinor,
    netRevenueMinor: gross - refundsMinor,
  };
}

/** Mirrors membership_included_usage_count: a member's included session (book_membership_slot) never produces a `payments` row — it's a pure count, never revenue (spec §"Membership Included Usage" / §"Critical Included Membership Test"). */
export function countMembershipIncludedUsage(confirmedMemberSlotBookings: number): { count: number; paidRevenueMinor: 0 } {
  return { count: confirmedMemberSlotBookings, paidRevenueMinor: 0 };
}

export type PaymentOrderStatusForCounts = "CREATED" | "ORDER_CREATED" | "PAYMENT_ATTEMPTED" | "PAYMENT_VERIFICATION_PENDING" | "PAYMENT_VERIFIED" | "AUTHORIZED" | "FAILED";

/** Mirrors get_finance_summary's failed/pending payment_orders counts — these never became a `payments` row, so they're counted straight off payment_orders.status, never off `payments` (spec §"Dashboard Metrics"). */
export function countPaymentOrdersByOutcome(statuses: PaymentOrderStatusForCounts[]): { failed: number; pending: number } {
  const pendingStatuses = new Set<PaymentOrderStatusForCounts>(["CREATED", "ORDER_CREATED", "PAYMENT_ATTEMPTED", "PAYMENT_VERIFICATION_PENDING", "PAYMENT_VERIFIED", "AUTHORIZED"]);
  let failed = 0;
  let pending = 0;
  for (const status of statuses) {
    if (status === "FAILED") failed++;
    else if (pendingStatuses.has(status)) pending++;
  }
  return { failed, pending };
}

/** Mirrors the double-counting protection this phase depends on (spec §"Revenue Double-Counting Protection" / §"Duplicate Transaction Test"): the same razorpay_payment_id must resolve to exactly one `payments` row — verified here as a pure invariant check over a candidate list, standing in for the DB's own unique index (payments_razorpay_payment_id_idx, 0016). */
export function hasDuplicatePaymentId(razorpayPaymentIds: string[]): boolean {
  return new Set(razorpayPaymentIds).size !== razorpayPaymentIds.length;
}

/** Mirrors refund double-counting protection (spec §"Refund Double-Counting Protection" / §"Critical Duplicate Refund Test") — the DB enforces this via refunds_razorpay_refund_id_idx (0023) + apply_refund_webhook's idempotent forward-only transition; this is the same invariant expressed as a pure check. */
export function hasDuplicateRefundId(razorpayRefundIds: string[]): boolean {
  return new Set(razorpayRefundIds).size !== razorpayRefundIds.length;
}