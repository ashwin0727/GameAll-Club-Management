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
  PaymentMethodSlice,
  LedgerEntry,
  LedgerFilters,
  LedgerPage,
  ExpenseCategory,
  ExpensePage,
  ExpenseRow,
  ObligationSource,
  PaymentObligation,
  PendingPaymentFilters,
  PendingPaymentsPage,
  PendingPaymentsSummary,
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

  /** Backend-aggregated split by method — never summed from a paginated list. */
  async getPaymentMethodBreakdown(facilityId: string, dateRange: FinanceDateRange): Promise<PaymentMethodSlice[]> {
    const { data, error } = await this.supabase.rpc('get_payment_method_breakdown', { p_facility_id: facilityId, ...dateRangeArgs(dateRange) });
    if (error) throw this.mapError(error);
    return (data ?? []).map((row) => ({
      paymentMethod: row.payment_method,
      amountMinor: row.amount_minor,
      paymentCount: row.payment_count,
    }));
  }

  async listLedger(input: {
    facilityId: string;
    dateRange: FinanceDateRange;
    filters?: LedgerFilters;
    limit?: number;
    offset?: number;
  }): Promise<LedgerPage> {
    const f = input.filters ?? {};
    const { data, error } = await this.supabase.rpc("list_finance_ledger", {
      p_facility_id: input.facilityId,
      ...dateRangeArgs(input.dateRange),
      p_txn_type: f.txnType ?? null,
      p_category: f.category ?? null,
      p_payment_method: f.paymentMethod ?? null,
      p_status: f.status ?? null,
      p_search: f.search?.trim() || null,
      p_limit: input.limit ?? 10,
      p_offset: input.offset ?? 0,
    });
    if (error) throw this.mapError(error);
    const entries: LedgerEntry[] = (data ?? []).map((row) => ({
      id: row.id,
      reference: row.reference,
      occurredAt: row.occurred_at,
      description: row.description,
      category: row.category,
      txnType: row.txn_type,
      paymentMethod: row.payment_method,
      amountMinor: row.amount_minor,
      currency: row.currency,
      status: row.status,
      sourceType: row.source_type,
      bookingId: row.booking_id,
      membershipId: row.membership_id,
      expenseId: row.expense_id,
    }));
    return { entries, totalCount: data?.[0]?.total_count ?? 0 };
  }

  async listPendingPayments(input: {
    facilityId: string;
    filters?: PendingPaymentFilters;
    limit?: number;
    offset?: number;
    /** One obligation by id, whatever its status — for the Record page. */
    sourceId?: string | null;
  }): Promise<PendingPaymentsPage> {
    const f = input.filters ?? {};
    const { data, error } = await this.supabase.rpc("list_pending_payments", {
      p_facility_id: input.facilityId,
      p_search: f.search?.trim() || null,
      p_source_type: f.sourceType ?? null,
      p_status: f.status ?? "ALL_OUTSTANDING",
      p_from: f.from ?? null,
      p_to: f.to ?? null,
      p_sort: f.sort ?? "DUE_DATE",
      p_limit: input.limit ?? 20,
      p_offset: input.offset ?? 0,
      p_source_id: input.sourceId ?? null,
    });
    if (error) throw this.mapError(error);
    const obligations: PaymentObligation[] = (data ?? []).map((row) => ({
      sourceType: row.source_type,
      sourceId: row.source_id,
      reference: row.reference,
      customerName: row.customer_name,
      customerPhone: row.customer_phone,
      description: row.description,
      facilityName: row.facility_name,
      courtName: row.court_name,
      startsAt: row.starts_at,
      endsAt: row.ends_at,
      totalMinor: row.total_minor,
      paidMinor: row.paid_minor,
      outstandingMinor: row.outstanding_minor,
      status: row.status,
      paymentMethod: row.payment_method,
      dueOn: row.due_on,
    }));
    return { obligations, totalCount: data?.[0]?.total_count ?? 0 };
  }

  /** The single obligation a Record Payment page is collecting against. */
  async getPaymentObligation(facilityId: string, sourceId: string): Promise<PaymentObligation | null> {
    const page = await this.listPendingPayments({ facilityId, sourceId, limit: 1 });
    return page.obligations[0] ?? null;
  }

  async getPendingPaymentsSummary(
    facilityId: string,
    from?: string | null,
    to?: string | null,
  ): Promise<PendingPaymentsSummary> {
    const { data, error } = await this.supabase.rpc("get_pending_payments_summary", {
      p_facility_id: facilityId,
      p_from: from ?? null,
      p_to: to ?? null,
    });
    if (error || !data?.[0]) throw this.mapError(error);
    const row = data[0];
    return {
      outstandingMinor: row.outstanding_minor,
      pendingMinor: row.pending_minor,
      partiallyPaidMinor: row.partially_paid_minor,
      overdueMinor: row.overdue_minor,
      obligationCount: row.obligation_count,
    };
  }

  async recordObligationPayment(input: {
    sourceType: ObligationSource;
    sourceId: string;
    amountMinor: number;
    method: string;
    paidOn?: string | null;
    reference?: string | null;
    notes?: string | null;
    idempotencyKey: string;
  }): Promise<{ duplicate: boolean; outstandingMinor?: number }> {
    const { data, error } = await this.supabase.rpc("record_obligation_payment", {
      p_source_type: input.sourceType,
      p_source_id: input.sourceId,
      p_amount_minor: input.amountMinor,
      p_method: input.method,
      p_paid_on: input.paidOn ?? null,
      p_reference: input.reference ?? null,
      p_notes: input.notes ?? null,
      p_idempotency_key: input.idempotencyKey,
    });
    if (error) throw this.mapError(error);
    return { duplicate: Boolean(data?.duplicate), outstandingMinor: data?.outstandingMinor };
  }

  async listPaymentMethods(facilityId: string): Promise<string[]> {
    const { data, error } = await this.supabase.rpc("list_finance_payment_methods", { p_facility_id: facilityId });
    if (error) throw this.mapError(error);
    return (data ?? []).map((row) => row.payment_method);
  }

  /** Shared defaults plus this facility's own — RLS decides which rows come back. */
  async listExpenseCategories(facilityId: string): Promise<ExpenseCategory[]> {
    const { data, error } = await this.supabase
      .from("expense_categories")
      .select("id, name")
      .eq("is_active", true)
      .or(`facility_id.is.null,facility_id.eq.${facilityId}`)
      .order("sort_order");
    if (error) throw this.mapError(error);
    return (data ?? []).map((row) => ({ id: row.id, name: row.name }));
  }

  async listExpenses(input: {
    facilityId: string;
    dateRange: FinanceDateRange;
    categoryId?: string | null;
    limit?: number;
    offset?: number;
  }): Promise<ExpensePage> {
    const { data, error } = await this.supabase.rpc('list_expenses', {
      p_facility_id: input.facilityId,
      ...dateRangeArgs(input.dateRange),
      p_category_id: input.categoryId ?? null,
      p_limit: input.limit ?? 20,
      p_offset: input.offset ?? 0,
    });
    if (error) throw this.mapError(error);
    const expenses: ExpenseRow[] = (data ?? []).map((row) => ({
      id: row.id,
      categoryId: row.category_id,
      categoryName: row.category_name,
      amountMinor: row.amount_minor,
      currency: row.currency,
      paymentMethod: row.payment_method,
      spentOn: row.spent_on,
      vendor: row.vendor,
      reference: row.reference,
      notes: row.notes,
      status: row.status,
    }));
    return { expenses, totalCount: data?.[0]?.total_count ?? 0 };
  }

  /** Voided, never deleted — books that lose rows cannot be explained. */
  async voidExpense(expenseId: string, reason?: string | null): Promise<void> {
    const { error } = await this.supabase.rpc('void_expense', {
      p_expense_id: expenseId,
      p_reason: reason ?? null,
    });
    if (error) throw this.mapError(error);
  }

  async createExpense(input: {
    facilityId: string;
    categoryId: string;
    amountMinor: number;
    spentOn: string;
    paymentMethod?: string | null;
    vendor?: string | null;
    reference?: string | null;
    notes?: string | null;
  }): Promise<void> {
    const { error } = await this.supabase.rpc("create_expense", {
      p_facility_id: input.facilityId,
      p_category_id: input.categoryId,
      p_amount_minor: input.amountMinor,
      p_spent_on: input.spentOn,
      p_payment_method: input.paymentMethod ?? null,
      p_vendor: input.vendor ?? null,
      p_reference: input.reference ?? null,
      p_notes: input.notes ?? null,
    });
    if (error) throw this.mapError(error);
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