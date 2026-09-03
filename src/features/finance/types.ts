// ═══════════════════════════════════════════════════════════════════════════
// Finance & Revenue Management — Phase 7.
//
// Every figure here is server-computed (0024_finance.sql) — this module
// only ever describes the SHAPE of what the backend returns, never
// calculates a total itself (spec §"Core Finance Principle" / §"Critical
// Final Rule").
// ═══════════════════════════════════════════════════════════════════════════

import type { PaymentSourceType } from "@/features/payments/types";

/** Every preset the backend's resolve_finance_date_range understands — the frontend only ever picks one of these (or CUSTOM + explicit dates), it never computes "today"/"this week" boundaries itself (spec §"Date Range" / §"Date/Time"). */
export type FinanceDateRangePreset = "TODAY" | "YESTERDAY" | "THIS_WEEK" | "LAST_WEEK" | "THIS_MONTH" | "LAST_MONTH" | "CUSTOM";

export interface FinanceDateRange {
  preset: FinanceDateRangePreset;
  /** Required, and only used, when preset is CUSTOM. */
  startDate?: string;
  endDate?: string;
}

export interface FinanceSummary {
  grossRevenueMinor: number;
  refundsMinor: number;
  /** What the facility spent in the range — recorded expenses, voids excluded. */
  expensesMinor: number;
  /** Gross, less refunds, less expenses. */
  netRevenueMinor: number;
  /** Money owed on bookings that have happened and not been paid for. */
  outstandingMinor: number;
  transactionCount: number;
  successfulPaymentCount: number;
  failedPaymentCount: number;
  pendingPaymentCount: number;
  /** Current open queue, not date-filtered — spec §"Dashboard Metrics". */
  pendingRefundCount: number;
  settlementExceptionCount: number;
}

export interface RevenueBreakdown {
  membershipRevenueMinor: number;
  memberBookingRevenueMinor: number;
  guestBookingRevenueMinor: number;
  refundsMinor: number;
  netRevenueMinor: number;
  /** Volume, never revenue — a member's included session is never paid (spec §"Membership Included Usage"). */
  membershipIncludedUsageCount: number;
}

export type RevenueTrendGranularity = "daily" | "weekly" | "monthly";

export interface RevenueTrendPoint {
  date: string;
  grossMinor: number;
  refundMinor: number;
  netMinor: number;
}

export type TransactionStatus = "created" | "paid" | "failed" | "refunded";

export interface FinanceTransaction {
  id: string;
  reference: string;
  facilityId: string;
  createdAt: string;
  paidAt: string | null;
  effectiveAt: string;
  sourceType: PaymentSourceType;
  customerName: string | null;
  customerPhone: string | null;
  bookingId: string | null;
  membershipId: string | null;
  paymentOrderId: string | null;
  amountMinor: number;
  currency: string;
  paymentMethod: string | null;
  status: TransactionStatus;
  razorpayOrderId: string | null;
  razorpayPaymentId: string | null;
  refundedMinor: number;
  pendingRefundMinor: number;
  netMinor: number;
}

export interface TransactionFilters {
  sourceType?: PaymentSourceType;
  status?: TransactionStatus;
  search?: string;
}

export interface ListTransactionsInput extends TransactionFilters {
  facilityId: string;
  dateRange: FinanceDateRange;
  limit?: number;
  offset?: number;
}

export interface TransactionPage {
  transactions: FinanceTransaction[];
  totalCount: number;
}