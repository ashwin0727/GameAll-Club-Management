import { describe, expect, it, vi } from "vitest";
import { SupabaseRefundService } from "@/services/refunds/supabase-refund.service";
import { ServiceError } from "@/services/shared/service-error";

const bookingRow = {
  id: "booking-1",
  facility_id: "facility-1",
  court_id: "court-1",
  facility_sport_id: "fs-1",
  member_id: null,
  customer_type: "GUEST" as const,
  guest_player_id: null,
  guest_name: "Rahul",
  guest_phone: "9999999999",
  start_time: "2026-08-28T12:00:00Z",
  end_time: "2026-08-28T13:00:00Z",
  status: "cancelled" as const,
  amount_minor: 80000,
  currency: "INR",
  payment_status: "PAID" as const,
  cancellation_reason: "Owner Request",
  notes: null,
  created_by: "user-1",
  created_at: "2026-08-01T00:00:00Z",
  updated_at: "2026-08-27T00:00:00Z",
};

describe("SupabaseRefundService.cancelBooking", () => {
  it("invokes cancel-booking with exactly the cancellation fields and maps the returned booking + refund", async () => {
    const invoke = vi.fn(async () => ({
      data: { booking: bookingRow, refund: { refundId: "r-1", status: "PROCESSING", razorpayRefundId: "rfnd_1" } },
      error: null,
    }));
    const service = new SupabaseRefundService({ functions: { invoke } } as never);

    const result = await service.cancelBooking({ bookingId: "booking-1", reason: "Owner Request" });

    expect(invoke).toHaveBeenCalledWith("cancel-booking", {
      body: { bookingId: "booking-1", reason: "Owner Request", refundOverridePercent: undefined, overrideReason: undefined },
    });
    expect(result.booking.id).toBe("booking-1");
    expect(result.booking.status).toBe("cancelled");
    expect(result.refund).toEqual({ id: "r-1", status: "PROCESSING", razorpayRefundId: "rfnd_1" });
  });

  it("a cancellation with no paid booking returns refund: null, never a fabricated refund", async () => {
    const invoke = vi.fn(async () => ({ data: { booking: bookingRow, refund: null }, error: null }));
    const service = new SupabaseRefundService({ functions: { invoke } } as never);

    const result = await service.cancelBooking({ bookingId: "booking-1" });

    expect(result.refund).toBeNull();
  });

  it("surfaces the Edge Function's own rejection (e.g. already cancelled) as PAYMENT_ORDER_ERROR", async () => {
    const invoke = vi.fn(async () => ({ data: { error: "This booking cannot be cancelled." }, error: null }));
    const service = new SupabaseRefundService({ functions: { invoke } } as never);

    await expect(service.cancelBooking({ bookingId: "booking-1" })).rejects.toMatchObject({
      code: "PAYMENT_ORDER_ERROR",
      message: "This booking cannot be cancelled.",
    });
  });

  it("maps a gateway/network failure to PAYMENT_GATEWAY_ERROR without leaking the raw error", async () => {
    const invoke = vi.fn(async () => ({ data: null, error: { message: "network down" } }));
    const service = new SupabaseRefundService({ functions: { invoke } } as never);

    await expect(service.cancelBooking({ bookingId: "booking-1" })).rejects.toMatchObject({ code: "PAYMENT_GATEWAY_ERROR" });
  });

  it("throws ServiceError (not a raw object) so callers can rely on instanceof", async () => {
    const invoke = vi.fn(async () => ({ data: null, error: { message: "boom" } }));
    const service = new SupabaseRefundService({ functions: { invoke } } as never);

    await expect(service.cancelBooking({ bookingId: "booking-1" })).rejects.toThrow(ServiceError);
  });
});

describe("SupabaseRefundService.cancelMembershipSlot", () => {
  it("invokes cancel-membership-slot with the booking id and returns the refund submission", async () => {
    const invoke = vi.fn(async () => ({ data: { booking: {}, refund: { refundId: "r-2", status: "REQUESTED" } }, error: null }));
    const service = new SupabaseRefundService({ functions: { invoke } } as never);

    const result = await service.cancelMembershipSlot({ bookingId: "msb-1" });

    expect(invoke).toHaveBeenCalledWith("cancel-membership-slot", {
      body: { bookingId: "msb-1", reason: undefined, refundOverridePercent: undefined, overrideReason: undefined },
    });
    expect(result.refund).toEqual({ id: "r-2", status: "REQUESTED", razorpayRefundId: undefined });
  });
});

describe("SupabaseRefundService.cancelMembership", () => {
  it("invokes cancel-membership with an explicit refund amount — never policy-derived", async () => {
    const invoke = vi.fn(async () => ({ data: { membership: {}, refund: { refundId: "r-3", status: "PROCESSING" } }, error: null }));
    const service = new SupabaseRefundService({ functions: { invoke } } as never);

    const result = await service.cancelMembership({ membershipId: "m-1", refundAmountMinor: 150000, overrideReason: "Owner discretion" });

    expect(invoke).toHaveBeenCalledWith("cancel-membership", {
      body: { membershipId: "m-1", reason: undefined, refundAmountMinor: 150000, overrideReason: "Owner discretion" },
    });
    expect(result.refund?.status).toBe("PROCESSING");
  });

  it("omitting refundAmountMinor cancels with no refund at all", async () => {
    const invoke = vi.fn(async () => ({ data: { membership: {}, refund: null }, error: null }));
    const service = new SupabaseRefundService({ functions: { invoke } } as never);

    const result = await service.cancelMembership({ membershipId: "m-1" });

    expect(result.refund).toBeNull();
  });
});

describe("SupabaseRefundService.initiateRefund", () => {
  it("invokes create-razorpay-refund for a manual partial refund", async () => {
    const invoke = vi.fn(async () => ({ data: { refundId: "r-4", status: "PROCESSING" }, error: null }));
    const service = new SupabaseRefundService({ functions: { invoke } } as never);

    const result = await service.initiateRefund({ paymentOrderId: "po-1", amountMinor: 30000, reason: "DUPLICATE_PAYMENT" });

    expect(invoke).toHaveBeenCalledWith("create-razorpay-refund", {
      body: { paymentOrderId: "po-1", settlementExceptionId: undefined, amountMinor: 30000, reason: "DUPLICATE_PAYMENT", overrideReason: undefined },
    });
    expect(result).toEqual({ id: "r-4", status: "PROCESSING", razorpayRefundId: undefined });
  });

  it("surfaces an over-refund rejection with the server's own maximum-refundable message", async () => {
    const invoke = vi.fn(async () => ({ data: { error: "The maximum refundable amount is 30000." }, error: null }));
    const service = new SupabaseRefundService({ functions: { invoke } } as never);

    await expect(service.initiateRefund({ paymentOrderId: "po-1", amountMinor: 90000 })).rejects.toMatchObject({
      code: "PAYMENT_ORDER_ERROR",
      message: "The maximum refundable amount is 30000.",
    });
  });

  it("initiates a settlement-exception refund by id, with no client-supplied amount", async () => {
    const invoke = vi.fn(async () => ({ data: { refundId: "r-5", status: "PROCESSING" }, error: null }));
    const service = new SupabaseRefundService({ functions: { invoke } } as never);

    await service.initiateRefund({ settlementExceptionId: "ex-1" });

    expect(invoke).toHaveBeenCalledWith("create-razorpay-refund", {
      body: { paymentOrderId: undefined, settlementExceptionId: "ex-1", amountMinor: undefined, reason: undefined, overrideReason: undefined },
    });
  });
});

describe("SupabaseRefundService.refundableAmount", () => {
  it("reads the server-computed refundable ceiling via the refundable_amount RPC", async () => {
    const rpc = vi.fn(async () => ({ data: 50000, error: null }));
    const service = new SupabaseRefundService({ rpc } as never);

    const result = await service.refundableAmount("po-1");

    expect(rpc).toHaveBeenCalledWith("refundable_amount", { p_payment_order_id: "po-1" });
    expect(result).toBe(50000);
  });
});

describe("SupabaseRefundService.listRefunds / listSettlementExceptions", () => {
  it("maps refund rows from snake_case to the feature's camelCase shape", async () => {
    const rpc = vi.fn(async () => ({
      data: [
        {
          id: "r-1",
          facility_id: "facility-1",
          payment_order_id: "po-1",
          transaction_id: "txn-1",
          source_type: "GUEST_BOOKING",
          source_id: "booking-1",
          razorpay_payment_id: "pay_1",
          razorpay_refund_id: "rfnd_1",
          amount_minor: 80000,
          currency: "INR",
          reason: "CUSTOMER_CANCELLATION",
          status: "PROCESSED",
          is_override: false,
          override_reason: null,
          policy_percent_applied: 100,
          failure_reason: null,
          initiated_by: "user-1",
          created_at: "2026-08-27T00:00:00Z",
          updated_at: "2026-08-27T00:05:00Z",
          processed_at: "2026-08-27T00:05:00Z",
        },
      ],
      error: null,
    }));
    const service = new SupabaseRefundService({ rpc } as never);

    const [refund] = await service.listRefunds("facility-1");

    expect(rpc).toHaveBeenCalledWith("list_refunds", { p_facility_id: "facility-1" });
    expect(refund).toMatchObject({ id: "r-1", policyPercentApplied: 100, razorpayRefundId: "rfnd_1", status: "PROCESSED" });
  });

  it("defaults listSettlementExceptions to OPEN only", async () => {
    const rpc = vi.fn(async () => ({ data: [], error: null }));
    const service = new SupabaseRefundService({ rpc } as never);

    await service.listSettlementExceptions("facility-1");

    expect(rpc).toHaveBeenCalledWith("list_settlement_exceptions", { p_facility_id: "facility-1", p_status: "OPEN" });
  });
});

describe("SupabaseRefundService cancellation policy", () => {
  it("reads the effective (configured-or-default) policy", async () => {
    const rpc = vi.fn(async () => ({
      data: { id: "cp-1", facility_id: "facility-1", full_refund_hours: 24, full_refund_percent: 100, partial_refund_hours: 2, partial_refund_percent: 50, created_at: "x", updated_at: "x" },
      error: null,
    }));
    const service = new SupabaseRefundService({ rpc } as never);

    const policy = await service.getCancellationPolicy("facility-1");

    expect(rpc).toHaveBeenCalledWith("get_effective_cancellation_policy", { p_facility_id: "facility-1" });
    expect(policy).toEqual({ facilityId: "facility-1", fullRefundHours: 24, fullRefundPercent: 100, partialRefundHours: 2, partialRefundPercent: 50 });
  });

  it("upserts a facility's configured policy", async () => {
    const rpc = vi.fn(async () => ({
      data: { id: "cp-1", facility_id: "facility-1", full_refund_hours: 48, full_refund_percent: 90, partial_refund_hours: 12, partial_refund_percent: 25, created_at: "x", updated_at: "x" },
      error: null,
    }));
    const service = new SupabaseRefundService({ rpc } as never);

    const policy = await service.upsertCancellationPolicy({ facilityId: "facility-1", fullRefundHours: 48, fullRefundPercent: 90, partialRefundHours: 12, partialRefundPercent: 25 });

    expect(rpc).toHaveBeenCalledWith("upsert_cancellation_policy", {
      p_facility_id: "facility-1",
      p_full_refund_hours: 48,
      p_full_refund_percent: 90,
      p_partial_refund_hours: 12,
      p_partial_refund_percent: 25,
    });
    expect(policy.fullRefundPercent).toBe(90);
  });
});