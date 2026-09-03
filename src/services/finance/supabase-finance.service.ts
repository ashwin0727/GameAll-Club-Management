"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import type {
  FinanceDateRange,
  FinanceSummary,
  FinanceTransaction,
  ListTransactionsInput,
  RevenueBreakdown,
  RevenueTrendGranularity,
  RevenueTrendPoint,
  TransactionPage,
} from "@/features/finance/types";
import type { FinanceService } from "@/services/finance/finance.service";
import { ServiceError } from "@/services/shared/service-error";
import type { Database } from "@/types/database.types";

type TransactionRow = Database["public"]["Views"]["finance_transactions_view"]["Row"];

function dateRangeArgs(dateRange: FinanceDateRange) {
  return { p_preset: dateRange.preset, p_start_date: dateRange.startDate ?? null, p_end_date: dateRange.endDate ?? null };
}

function toTransaction(row: TransactionRow): FinanceTransaction {
  return {
    id: row.id,
    reference: row.reference,
    facilityId: row.facility_id,
    createdAt: row.created_at,
    paidAt: row.paid_at,
    effectiveAt: row.effective_at,
    sourceType: row.source_type,
    customerName: row.customer_name,
    customerPhone: row.customer_phone,
    bookingId: row.booking_id,
    membershipId: row.membership_id,
    paymentOrderId: row.payment_order_id,
    amountMinor: row.amount_minor,
    currency: row.currency,
    paymentMethod: row.payment_method,
    status: row.status,
    razorpayOrderId: row.razorpay_order_id,
    razorpayPaymentId: row.razorpay_payment_id,
    refundedMinor: row.refunded_minor,
    pendingRefundMinor: row.pending_refund_minor,
    netMinor: row.net_minor,
  };
}

export class SupabaseFinanceService implements FinanceService {
  private readonly supabase: SupabaseClient<Database>;

  constructor(client?: SupabaseClient<Database>) {
    this.supabase = client ?? createClient();
  }

  async getSummary(facilityId: string, dateRange: FinanceDateRange): Promise<FinanceSummary> {
    const { data, error } = await this.supabase.rpc("get_finance_summary", { p_facility_id: facilityId, ...dateRangeArgs(dateRange) });
    if (error || !data?.[0]) throw this.mapError(error);
    const row = data[0];
    return {
      grossRevenueMinor: row.gross_revenue_minor,
      refundsMinor: row.refunds_minor,
      expensesMinor: row.expenses_minor ?? 0,
      netRevenueMinor: row.net_revenue_minor,
      outstandingMinor: row.outstanding_minor ?? 0,
      transactionCount: row.transaction_count,
      successfulPaymentCount: row.successful_payment_count,
      failedPaymentCount: row.failed_payment_count,
      pendingPaymentCount: row.pending_payment_count,
      pendingRefundCount: row.pending_refund_count,
      settlementExceptionCount: row.settlement_exception_count,
    };
  }

  async getRevenueBreakdown(facilityId: string, dateRange: FinanceDateRange): Promise<RevenueBreakdown> {
    const { data, error } = await this.supabase.rpc("get_revenue_breakdown", { p_facility_id: facilityId, ...dateRangeArgs(dateRange) });
    if (error || !data?.[0]) throw this.mapError(error);
    const row = data[0];
    return {
      membershipRevenueMinor: row.membership_revenue_minor,
      memberBookingRevenueMinor: row.member_booking_revenue_minor,
      guestBookingRevenueMinor: row.guest_booking_revenue_minor,
      refundsMinor: row.refunds_minor,
      netRevenueMinor: row.net_revenue_minor,
      membershipIncludedUsageCount: row.membership_included_usage_count,
    };
  }

  async getRevenueTrend(facilityId: string, dateRange: FinanceDateRange, granularity: RevenueTrendGranularity): Promise<RevenueTrendPoint[]> {
    const { data, error } = await this.supabase.rpc("get_revenue_trend", { p_facility_id: facilityId, ...dateRangeArgs(dateRange), p_granularity: granularity });
    if (error) throw this.mapError(error);
    return (data ?? []).map((row) => ({ date: row.bucket_date, grossMinor: row.gross_minor, refundMinor: row.refund_minor, netMinor: row.net_minor }));
  }

  async listTransactions(input: ListTransactionsInput): Promise<TransactionPage> {
    const args = {
      p_facility_id: input.facilityId,
      ...dateRangeArgs(input.dateRange),
      p_source_type: input.sourceType ?? null,
      p_status: input.status ?? null,
      p_search: input.search ?? null,
    };
    const [{ data, error }, { data: countData, error: countError }] = await Promise.all([
      this.supabase.rpc("list_finance_transactions", { ...args, p_limit: input.limit ?? 20, p_offset: input.offset ?? 0 }),
      this.supabase.rpc("count_finance_transactions", args),
    ]);
    if (error || countError) throw this.mapError(error ?? countError);
    return { transactions: (data ?? []).map(toTransaction), totalCount: countData ?? 0 };
  }

  async getTransaction(transactionId: string): Promise<FinanceTransaction> {
    const { data, error } = await this.supabase.rpc("get_finance_transaction", { p_transaction_id: transactionId });
    if (error || !data) throw this.mapError(error);
    return toTransaction(data);
  }

  private mapError(error: unknown): ServiceError {
    console.error("[finance-service] request failed", error);
    const message = (error as { message?: string } | null)?.message;
    if (message?.includes("Not authorized")) return new ServiceError("FINANCE_ACCESS_DENIED");
    if (message?.includes("valid start and end date")) return new ServiceError("INVALID_DATE_RANGE");
    return new ServiceError("FINANCE_DATA_ERROR");
  }
}