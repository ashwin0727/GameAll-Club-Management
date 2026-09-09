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
  ExpenseFilters,
  ExpenseSummary,
  ExpenseDetail,
  CreateExpenseInput,
  DailyClosingSummary,
  DailyClosingHistoryPage,
  ProfitAndLoss,
  PnlTrendPoint,
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
  listExpenses(input: {
    facilityId: string;
    dateRange: FinanceDateRange;
    categoryId?: string | null;
    filters?: ExpenseFilters;
    limit?: number;
    offset?: number;
  }): Promise<ExpensePage>;
  getExpenseSummary(facilityId: string, dateRange: FinanceDateRange): Promise<ExpenseSummary>;
  getExpense(expenseId: string): Promise<ExpenseDetail | null>;
  voidExpense(expenseId: string, reason?: string | null): Promise<void>;
  createExpense(input: CreateExpenseInput): Promise<void>;
  updateExpense(input: {
    expenseId: string;
    categoryId?: string | null;
    amountMinor?: number | null;
    spentOn?: string | null;
    paymentMethod?: string | null;
    vendor?: string | null;
    reference?: string | null;
    notes?: string | null;
    taxMinor?: number | null;
    dueOn?: string | null;
    receiptPath?: string | null;
  }): Promise<void>;
  recordExpensePayment(input: {
    expenseId: string;
    amountMinor?: number | null;
    paidOn?: string | null;
    paymentMethod?: string | null;
    reference?: string | null;
    note?: string | null;
    idempotencyKey?: string | null;
  }): Promise<void>;
  // Daily Closing
  getDailyClosingSummary(facilityId: string, date?: string | null): Promise<DailyClosingSummary>;
  openDailyClosing(facilityId: string, date: string | null, openingCashMinor?: number | null): Promise<void>;
  setDailyClosingOpeningCash(closingId: string, openingCashMinor: number): Promise<void>;
  closeDailyClosing(closingId: string, actualCashMinor: number, varianceReason?: string | null): Promise<void>;
  reopenDailyClosing(closingId: string, reason: string): Promise<void>;
  listDailyClosings(input: { facilityId: string; dateRange: FinanceDateRange; limit?: number; offset?: number }): Promise<DailyClosingHistoryPage>;
  // Profit & Loss
  getProfitAndLoss(facilityId: string, dateRange: FinanceDateRange, categoryId?: string | null): Promise<ProfitAndLoss>;
  getPnlTrend(facilityId: string, dateRange: FinanceDateRange, granularity: RevenueTrendGranularity): Promise<PnlTrendPoint[]>;
  /** Server-side filtered, searched, and paginated (spec §"Transaction Pagination"). */
  listTransactions(input: ListTransactionsInput): Promise<TransactionPage>;
  getTransaction(transactionId: string): Promise<FinanceTransaction>;
  /** The full detail view, including the other payments against the same source. */
  getTransactionDetails(transactionId: string): Promise<TransactionDetails>;
  /** Receipt PDF bytes, built server-side. */
  downloadTransactionReceipt(transactionId: string): Promise<Blob>;
}