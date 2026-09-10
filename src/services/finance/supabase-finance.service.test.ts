import { describe, expect, it, vi } from "vitest";
import { SupabaseFinanceService } from "@/services/finance/supabase-finance.service";
import { ServiceError } from "@/services/shared/service-error";

const SUMMARY_ROW = {
  gross_revenue_minor: 350000,
  refunds_minor: 80000,
  expenses_minor: 45000,
  net_revenue_minor: 225000,
  outstanding_minor: 12000,
  transaction_count: 4,
  successful_payment_count: 4,
  failed_payment_count: 0,
  pending_payment_count: 0,
  pending_refund_count: 0,
  settlement_exception_count: 0,
};

describe("SupabaseFinanceService.getSummary", () => {
  it("calls get_finance_summary with the resolved date-range args and maps the server's own totals — never recomputed client-side", async () => {
    const rpc = vi.fn(async () => ({ data: [SUMMARY_ROW], error: null }));
    const service = new SupabaseFinanceService({ rpc } as never);

    const result = await service.getSummary("facility-1", { preset: "THIS_MONTH" });

    expect(rpc).toHaveBeenCalledWith("get_finance_summary", { p_facility_id: "facility-1", p_preset: "THIS_MONTH", p_start_date: null, p_end_date: null });
    expect(result).toEqual({
      grossRevenueMinor: 350000,
      refundsMinor: 80000,
      expensesMinor: 45000,
      netRevenueMinor: 225000,
      outstandingMinor: 12000,
      transactionCount: 4,
      successfulPaymentCount: 4,
      failedPaymentCount: 0,
      pendingPaymentCount: 0,
      pendingRefundCount: 0,
      settlementExceptionCount: 0,
    });
  });

  it("passes an explicit start/end date through for a CUSTOM range", async () => {
    const rpc = vi.fn(async () => ({ data: [SUMMARY_ROW], error: null }));
    const service = new SupabaseFinanceService({ rpc } as never);

    await service.getSummary("facility-1", { preset: "CUSTOM", startDate: "2026-08-01", endDate: "2026-08-15" });

    expect(rpc).toHaveBeenCalledWith("get_finance_summary", { p_facility_id: "facility-1", p_preset: "CUSTOM", p_start_date: "2026-08-01", p_end_date: "2026-08-15" });
  });

  it("maps a facility-isolation rejection to FINANCE_ACCESS_DENIED — never a fabricated zero summary", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { message: "Not authorized for this facility." } }));
    const service = new SupabaseFinanceService({ rpc } as never);

    await expect(service.getSummary("facility-2", { preset: "TODAY" })).rejects.toMatchObject({ code: "FINANCE_ACCESS_DENIED" });
  });

  it("maps an invalid custom range to INVALID_DATE_RANGE", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { message: "A custom date range requires a valid start and end date." } }));
    const service = new SupabaseFinanceService({ rpc } as never);

    await expect(service.getSummary("facility-1", { preset: "CUSTOM" })).rejects.toMatchObject({ code: "INVALID_DATE_RANGE" });
  });

  it("throws ServiceError (not a raw object) so callers can rely on instanceof", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { message: "boom" } }));
    const service = new SupabaseFinanceService({ rpc } as never);

    await expect(service.getSummary("facility-1", { preset: "TODAY" })).rejects.toThrow(ServiceError);
  });
});

describe("SupabaseFinanceService.getRevenueBreakdown", () => {
  it("maps every revenue-by-source figure — spec Critical Finance Test", async () => {
    const rpc = vi.fn(async () => ({
      data: [
        {
          membership_revenue_minor: 150000,
          member_booking_revenue_minor: 50000,
          guest_booking_revenue_minor: 150000,
          coaching_revenue_minor: 90000,
          refunds_minor: 80000,
          net_revenue_minor: 270000,
          membership_included_usage_count: 2,
        },
      ],
      error: null,
    }));
    const service = new SupabaseFinanceService({ rpc } as never);

    const result = await service.getRevenueBreakdown("facility-1", { preset: "THIS_MONTH" });

    expect(rpc).toHaveBeenCalledWith("get_revenue_breakdown", { p_facility_id: "facility-1", p_preset: "THIS_MONTH", p_start_date: null, p_end_date: null });
    expect(result).toEqual({
      membershipRevenueMinor: 150000,
      memberBookingRevenueMinor: 50000,
      guestBookingRevenueMinor: 150000,
      coachingRevenueMinor: 90000,
      refundsMinor: 80000,
      netRevenueMinor: 270000,
      membershipIncludedUsageCount: 2,
    });
  });
});

describe("SupabaseFinanceService.getRevenueTrend", () => {
  it("passes the granularity through and maps each bucket", async () => {
    const rpc = vi.fn(async () => ({
      data: [
        { bucket_date: "2026-08-01", gross_minor: 850000, refund_minor: 0, net_minor: 850000 },
        { bucket_date: "2026-08-02", gross_minor: 1200000, refund_minor: 30000, net_minor: 1170000 },
      ],
      error: null,
    }));
    const service = new SupabaseFinanceService({ rpc } as never);

    const result = await service.getRevenueTrend("facility-1", { preset: "THIS_MONTH" }, "daily");

    expect(rpc).toHaveBeenCalledWith("get_revenue_trend", { p_facility_id: "facility-1", p_preset: "THIS_MONTH", p_start_date: null, p_end_date: null, p_granularity: "daily" });
    expect(result).toHaveLength(2);
    expect(result[0]).toEqual({ date: "2026-08-01", grossMinor: 850000, refundMinor: 0, netMinor: 850000 });
  });

  it("an empty trend returns an empty array, never fabricated points", async () => {
    const rpc = vi.fn(async () => ({ data: [], error: null }));
    const service = new SupabaseFinanceService({ rpc } as never);

    const result = await service.getRevenueTrend("facility-1", { preset: "TODAY" }, "daily");

    expect(result).toEqual([]);
  });
});

const TRANSACTION_ROW = {
  id: "txn-1",
  reference: "TXN-ABCD1234",
  facility_id: "facility-1",
  created_at: "2026-08-27T10:00:00Z",
  paid_at: "2026-08-27T10:00:05Z",
  effective_at: "2026-08-27T10:00:05Z",
  source_type: "GUEST_BOOKING" as const,
  customer_name: "Rahul",
  customer_phone: "9999999999",
  booking_id: "booking-1",
  membership_id: null,
  payment_order_id: "po-1",
  amount_minor: 80000,
  currency: "INR",
  payment_method: "RAZORPAY",
  status: "paid" as const,
  razorpay_order_id: "order_1",
  razorpay_payment_id: "pay_1",
  refunded_minor: 0,
  pending_refund_minor: 0,
  net_minor: 80000,
};

describe("SupabaseFinanceService.listTransactions", () => {
  it("fetches the page and the total count in parallel with matching filters, never paginating a client-side list", async () => {
    const rpc = vi.fn(async (fn: string) => (fn === "list_finance_transactions" ? { data: [TRANSACTION_ROW], error: null } : { data: 37, error: null }));
    const service = new SupabaseFinanceService({ rpc } as never);

    const result = await service.listTransactions({ facilityId: "facility-1", dateRange: { preset: "THIS_MONTH" }, sourceType: "GUEST_BOOKING", status: "paid", search: "Rahul", limit: 20, offset: 20 });

    expect(rpc).toHaveBeenCalledWith(
      "list_finance_transactions",
      expect.objectContaining({ p_facility_id: "facility-1", p_source_type: "GUEST_BOOKING", p_status: "paid", p_search: "Rahul", p_limit: 20, p_offset: 20 }),
    );
    expect(rpc).toHaveBeenCalledWith("count_finance_transactions", expect.objectContaining({ p_facility_id: "facility-1", p_source_type: "GUEST_BOOKING", p_status: "paid", p_search: "Rahul" }));
    expect(result.totalCount).toBe(37);
    expect(result.transactions[0]).toMatchObject({ id: "txn-1", reference: "TXN-ABCD1234", amountMinor: 80000, sourceType: "GUEST_BOOKING" });
  });

  it("defaults limit/offset to page 1 of 20 when not specified", async () => {
    const rpc = vi.fn(async (fn: string) => (fn === "list_finance_transactions" ? { data: [], error: null } : { data: 0, error: null }));
    const service = new SupabaseFinanceService({ rpc } as never);

    await service.listTransactions({ facilityId: "facility-1", dateRange: { preset: "TODAY" } });

    expect(rpc).toHaveBeenCalledWith("list_finance_transactions", expect.objectContaining({ p_limit: 20, p_offset: 0 }));
  });
});

describe("SupabaseFinanceService.getTransaction", () => {
  it("reads a single transaction's full detail", async () => {
    const rpc = vi.fn(async () => ({ data: TRANSACTION_ROW, error: null }));
    const service = new SupabaseFinanceService({ rpc } as never);

    const result = await service.getTransaction("txn-1");

    expect(rpc).toHaveBeenCalledWith("get_finance_transaction", { p_transaction_id: "txn-1" });
    expect(result.razorpayPaymentId).toBe("pay_1");
    expect(result.customerName).toBe("Rahul");
  });

  it("maps a not-found/cross-facility lookup to FINANCE_DATA_ERROR rather than leaking the raw error", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { message: "Transaction not found." } }));
    const service = new SupabaseFinanceService({ rpc } as never);

    await expect(service.getTransaction("txn-missing")).rejects.toMatchObject({ code: "FINANCE_DATA_ERROR" });
  });
});
describe("SupabaseFinanceService — Expenses / Daily Closing / P&L (0069-0071)", () => {
  it("getExpenseSummary maps the server KPI row", async () => {
    const row = {
      total_minor: 50000,
      this_month_minor: 30000,
      this_week_minor: 10000,
      pending_minor: 8000,
      pending_count: 2,
      maintenance_minor: 12000,
      other_minor: 38000,
    };
    const rpc = vi.fn(async () => ({ data: [row], error: null }));
    const service = new SupabaseFinanceService({ rpc } as never);
    const result = await service.getExpenseSummary("f1", { preset: "THIS_MONTH" });
    expect(rpc).toHaveBeenCalledWith("get_expense_summary", {
      p_facility_id: "f1",
      p_preset: "THIS_MONTH",
      p_start_date: null,
      p_end_date: null,
    });
    expect(result.pendingCount).toBe(2);
    expect(result.maintenanceMinor).toBe(12000);
  });

  it("recordExpensePayment forwards the idempotency key", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: null }));
    const service = new SupabaseFinanceService({ rpc } as never);
    await service.recordExpensePayment({ expenseId: "e1", amountMinor: 5000, idempotencyKey: "k-1" });
    expect(rpc).toHaveBeenCalledWith("record_expense_payment", {
      p_expense_id: "e1",
      p_amount_minor: 5000,
      p_paid_on: null,
      p_payment_method: null,
      p_reference: null,
      p_note: null,
      p_idempotency_key: "k-1",
    });
  });

  it("getDailyClosingSummary maps every collection bucket + status", async () => {
    const row = {
      closing_date: "2026-09-09",
      opening_cash_minor: 5000,
      cash_collected_minor: 10000,
      upi_collected_minor: 8500,
      card_collected_minor: 0,
      online_collected_minor: 0,
      bank_transfer_collected_minor: 0,
      other_collected_minor: 0,
      total_collected_minor: 18500,
      cash_expense_minor: 2000,
      other_expense_minor: 0,
      total_expense_minor: 2000,
      expected_cash_minor: 13000,
      payment_count: 3,
      expense_count: 1,
      pending_payment_count: 0,
      closing_id: "c1",
      status: "OPEN",
      actual_cash_minor: null,
      variance_minor: null,
      variance_reason: null,
      closed_at: null,
    };
    const rpc = vi.fn(async () => ({ data: [row], error: null }));
    const service = new SupabaseFinanceService({ rpc } as never);
    const result = await service.getDailyClosingSummary("f1", "2026-09-09");
    expect(result.expectedCashMinor).toBe(13000);
    expect(result.status).toBe("OPEN");
  });

  it("closeDailyClosing sends actual cash + reason", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: null }));
    const service = new SupabaseFinanceService({ rpc } as never);
    await service.closeDailyClosing("c1", 12500, "Cash shortage");
    expect(rpc).toHaveBeenCalledWith("close_daily_closing", {
      p_closing_id: "c1",
      p_actual_cash_minor: 12500,
      p_variance_reason: "Cash shortage",
    });
  });

  it("getProfitAndLoss maps revenue split, totals and category breakdown", async () => {
    const row = {
      booking_revenue_minor: 60000,
      membership_revenue_minor: 30000,
      guest_booking_revenue_minor: 10000,
      other_revenue_minor: 0,
      gross_revenue_minor: 100000,
      refunds_minor: 5000,
      total_revenue_minor: 95000,
      total_expense_minor: 15000,
      net_profit_minor: 80000,
      profit_margin_pct: 84.2,
      expense_by_category: [{ categoryId: "cat1", category: "Rent", amountMinor: 15000 }],
    };
    const rpc = vi.fn(async () => ({ data: [row], error: null }));
    const service = new SupabaseFinanceService({ rpc } as never);
    const result = await service.getProfitAndLoss("f1", { preset: "THIS_MONTH" });
    expect(result.netProfitMinor).toBe(80000);
    expect(result.profitMarginPct).toBe(84.2);
    expect(result.expenseByCategory[0]?.category).toBe("Rent");
  });

  it("maps a facility-isolation rejection on P&L to FINANCE_ACCESS_DENIED", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { message: "Not authorized for this facility." } }));
    const service = new SupabaseFinanceService({ rpc } as never);
    await expect(service.getProfitAndLoss("f2", { preset: "TODAY" })).rejects.toMatchObject({
      code: "FINANCE_ACCESS_DENIED",
    });
  });
});
