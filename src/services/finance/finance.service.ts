import type {
  FinanceDateRange,
  FinanceSummary,
  FinanceTransaction,
  ListTransactionsInput,
  RevenueBreakdown,
  RevenueTrendGranularity,
  RevenueTrendPoint,
  TransactionPage,
  PaymentMethodSlice,
  LedgerFilters,
  LedgerPage,
  ExpenseCategory,
  ExpensePage,
  ObligationSource,
  PendingPaymentFilters,
  PaymentObligation,
  PendingPaymentsPage,
  PendingPaymentsSummary,
  TransactionDetails,
} from "@/features/finance/types";

export interface FinanceService {
  /** The dashboard's headline numbers — backend-aggregated, never summed from a paginated list (spec §"Backend Aggregation"). */
  getSummary(facilityId: string, dateRange: FinanceDateRange): Promise<FinanceSummary>;
  getRevenueBreakdown(facilityId: string, dateRange: FinanceDateRange): Promise<RevenueBreakdown>;
  getRevenueTrend(facilityId: string, dateRange: FinanceDateRange, granularity: RevenueTrendGranularity): Promise<RevenueTrendPoint[]>;
  getPaymentMethodBreakdown(facilityId: string, dateRange: FinanceDateRange): Promise<PaymentMethodSlice[]>;
  /** Payments, refunds and expenses in one server-filtered, server-paged list. */
  listLedger(input: {
    facilityId: string;
    dateRange: FinanceDateRange;
    filters?: LedgerFilters;
    limit?: number;
    offset?: number;
  }): Promise<LedgerPage>;
  listPaymentMethods(facilityId: string): Promise<string[]>;
  /** Everything still owed, from every source, filtered and paged server-side. */
  listPendingPayments(input: {
    facilityId: string;
    filters?: PendingPaymentFilters;
    limit?: number;
    offset?: number;
    sourceId?: string | null;
  }): Promise<PendingPaymentsPage>;
  getPaymentObligation(facilityId: string, sourceId: string): Promise<PaymentObligation | null>;
  getPendingPaymentsSummary(facilityId: string, from?: string | null, to?: string | null): Promise<PendingPaymentsSummary>;
  /** Collect against any obligation. The server revalidates the balance. */
  recordObligationPayment(input: {
    sourceType: ObligationSource;
    sourceId: string;
    amountMinor: number;
    method: string;
    paidOn?: string | null;
    reference?: string | null;
    notes?: string | null;
    idempotencyKey: string;
  }): Promise<{ duplicate: boolean; outstandingMinor?: number }>;
  listExpenseCategories(facilityId: string): Promise<ExpenseCategory[]>;
  listExpenses(input: { facilityId: string; dateRange: FinanceDateRange; categoryId?: string | null; limit?: number; offset?: number }): Promise<ExpensePage>;
  voidExpense(expenseId: string, reason?: string | null): Promise<void>;
  createExpense(input: {
    facilityId: string;
    categoryId: string;
    amountMinor: number;
    spentOn: string;
    paymentMethod?: string | null;
    vendor?: string | null;
    reference?: string | null;
    notes?: string | null;
  }): Promise<void>;
  /** Server-side filtered, searched, and paginated (spec §"Transaction Pagination"). */
  listTransactions(input: ListTransactionsInput): Promise<TransactionPage>;
  getTransaction(transactionId: string): Promise<FinanceTransaction>;
  /** The full detail view, including the other payments against the same source. */
  getTransactionDetails(transactionId: string): Promise<TransactionDetails>;
  /** Receipt PDF bytes, built server-side. */
  downloadTransactionReceipt(transactionId: string): Promise<Blob>;
}