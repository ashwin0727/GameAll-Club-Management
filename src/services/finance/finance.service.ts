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
  listExpenseCategories(facilityId: string): Promise<ExpenseCategory[]>;
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
}