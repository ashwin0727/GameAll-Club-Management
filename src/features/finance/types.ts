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
/** One payment method's share of captured revenue in the selected range. */
export interface PaymentMethodSlice {
  paymentMethod: string;
  amountMinor: number;
  paymentCount: number;
}

export type LedgerTxnType = "INCOME" | "EXPENSE" | "REFUND";

/** One line of financial activity — a payment, a refund, or an expense. */
export interface LedgerEntry {
  id: string;
  reference: string;
  occurredAt: string;
  description: string;
  category: string;
  txnType: LedgerTxnType;
  paymentMethod: string | null;
  amountMinor: number;
  currency: string;
  status: string;
  sourceType: string;
  bookingId: string | null;
  membershipId: string | null;
  expenseId: string | null;
}

export interface LedgerFilters {
  txnType?: LedgerTxnType | null;
  category?: string | null;
  paymentMethod?: string | null;
  status?: string | null;
  search?: string | null;
}

export interface LedgerPage {
  entries: LedgerEntry[];
  totalCount: number;
}

export interface ExpenseCategory {
  id: string;
  name: string;
}

export type ObligationSource = "GUEST_BOOKING" | "BOOKING" | "MEMBERSHIP";
export type ObligationStatus = "PENDING" | "PARTIALLY_PAID" | "OVERDUE" | "PAID";

/**
 * Money still owed on one booking or membership. Derived in the database
 * from what the thing costs and what has been collected against it — never
 * stored, so it cannot drift from the payments it is computed from.
 */
export interface PaymentObligation {
  sourceType: ObligationSource;
  sourceId: string;
  reference: string;
  customerName: string;
  customerPhone: string | null;
  description: string;
  facilityName: string | null;
  courtName: string | null;
  startsAt: string | null;
  endsAt: string | null;
  totalMinor: number;
  paidMinor: number;
  outstandingMinor: number;
  status: ObligationStatus;
  paymentMethod: string | null;
  /** Booking date, or membership start date. One meaning per source. */
  dueOn: string;
}

export interface PendingPaymentsPage {
  obligations: PaymentObligation[];
  totalCount: number;
}

export interface PendingPaymentsSummary {
  outstandingMinor: number;
  pendingMinor: number;
  partiallyPaidMinor: number;
  overdueMinor: number;
  obligationCount: number;
}

export type ObligationSort = "DUE_DATE" | "AMOUNT" | "CUSTOMER" | "NEWEST";

export interface PendingPaymentFilters {
  search?: string | null;
  sourceType?: ObligationSource | null;
  status?: ObligationStatus | "ALL_OUTSTANDING" | null;
  from?: string | null;
  to?: string | null;
  sort?: ObligationSort;
}

export interface ExpenseRow {
  id: string;
  categoryId: string;
  categoryName: string;
  amountMinor: number;
  currency: string;
  paymentMethod: string | null;
  spentOn: string;
  vendor: string | null;
  reference: string | null;
  notes: string | null;
  status: string;
}

export interface ExpensePage {
  expenses: ExpenseRow[];
  totalCount: number;
}

export interface TransactionPaymentHistoryRow {
  id: string;
  paidAt: string;
  amountMinor: number;
  paymentMethod: string | null;
  reference: string | null;
  status: string;
  /** The payment this page is about, among its siblings. */
  isThisOne: boolean;
}

/** Everything the Transaction Details page and its receipt render. */
export interface TransactionDetails {
  id: string;
  reference: string;
  sourceType: string;
  category: string;
  type: "INCOME";
  amountMinor: number;
  currency: string;
  status: string;
  paymentMethod: string | null;
  occurredAt: string;
  createdAt: string;
  recordedBy: string | null;
  description: string;
  sourceReference: string | null;
  customerName: string | null;
  customerPhone: string | null;
  facilityName: string | null;
  facilityId: string;
  bookingId: string | null;
  membershipId: string | null;
  refundedMinor: number;
  netMinor: number;
  history: TransactionPaymentHistoryRow[];
}
