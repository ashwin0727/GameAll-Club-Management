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
} from "@/features/finance/types";

export interface FinanceService {
  /** The dashboard's headline numbers — backend-aggregated, never summed from a paginated list (spec §"Backend Aggregation"). */
  getSummary(facilityId: string, dateRange: FinanceDateRange): Promise<FinanceSummary>;
  getRevenueBreakdown(facilityId: string, dateRange: FinanceDateRange): Promise<RevenueBreakdown>;
  getRevenueTrend(facilityId: string, dateRange: FinanceDateRange, granularity: RevenueTrendGranularity): Promise<RevenueTrendPoint[]>;
  getPaymentMethodBreakdown(facilityId: string, dateRange: FinanceDateRange): Promise<PaymentMethodSlice[]>;
  /** Server-side filtered, searched, and paginated (spec §"Transaction Pagination"). */
  listTransactions(input: ListTransactionsInput): Promise<TransactionPage>;
  getTransaction(transactionId: string): Promise<FinanceTransaction>;
}