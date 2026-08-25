import { describe, expect, it, vi } from "vitest";
import { SupabasePaymentService } from "@/services/payments/supabase-payment.service";
import { ServiceError } from "@/services/shared/service-error";

describe("SupabasePaymentService", () => {
  it("createPaymentOrder invokes create-razorpay-order with exactly the source fields — never an amount", async () => {
    const invoke = vi.fn(async () => ({
      data: { keyId: "rzp_test_abc", razorpayOrderId: "order_1", amount: 50000, currency: "INR", paymentOrderId: "po-1", receipt: "GAMEALL-MEMBERBOOKING-abc" },
      error: null,
    }));
    const service = new SupabasePaymentService({ functions: { invoke } } as never);

    const result = await service.createPaymentOrder({
      facilityId: "facility-1",
      sourceType: "MEMBER_BOOKING",
      bookingId: "booking-1",
    });

    expect(invoke).toHaveBeenCalledWith(
      "create-razorpay-order",
      expect.objectContaining({
        body: expect.not.objectContaining({ amount: expect.anything() }),
      }),
    );
    const call = invoke.mock.calls[0]?.[1] as { body: Record<string, unknown> };
    expect(call.body).toEqual({
      facilityId: "facility-1",
      sourceType: "MEMBER_BOOKING",
      bookingId: "booking-1",
      membershipSessionBookingId: undefined,
      memberId: undefined,
      planId: undefined,
    });
    expect(result.amount).toBe(50000);
    expect(result.keyId).toBe("rzp_test_abc");
  });

  it("maps a network/relay failure to PAYMENT_GATEWAY_ERROR without leaking the raw error", async () => {
    const invoke = vi.fn(async () => ({ data: null, error: { message: "network down" } }));
    const service = new SupabasePaymentService({ functions: { invoke } } as never);

    await expect(
      service.createPaymentOrder({ facilityId: "f", sourceType: "MEMBER_BOOKING", bookingId: "b" }),
    ).rejects.toMatchObject({ code: "PAYMENT_GATEWAY_ERROR" });
  });

  it("surfaces the Edge Function's own error body (e.g. a rejected business rule) as PAYMENT_ORDER_ERROR", async () => {
    const invoke = vi.fn(async () => ({
      data: { error: "No guest slots are currently available for this session." },
      error: null,
    }));
    const service = new SupabasePaymentService({ functions: { invoke } } as never);

    await expect(
      service.createPaymentOrder({ facilityId: "f", sourceType: "GUEST_BOOKING", membershipSessionBookingId: "msb-1" }),
    ).rejects.toMatchObject({ code: "PAYMENT_ORDER_ERROR", message: "No guest slots are currently available for this session." });
  });

  it("throws ServiceError (not a raw object) so callers can rely on instanceof", async () => {
    const invoke = vi.fn(async () => ({ data: null, error: { message: "boom" } }));
    const service = new SupabasePaymentService({ functions: { invoke } } as never);

    await expect(service.createPaymentOrder({ facilityId: "f", sourceType: "MEMBERSHIP", memberId: "m", planId: "p" })).rejects.toThrow(
      ServiceError,
    );
  });
});

describe("SupabasePaymentService.recordPaymentAttempt", () => {
  it("calls record_payment_attempt with the exact RPC arg names", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: null }));
    const service = new SupabasePaymentService({ rpc } as never);

    await service.recordPaymentAttempt({
      paymentOrderId: "po-1",
      status: "PAYMENT_ATTEMPTED",
      razorpayPaymentId: "pay_1",
      razorpaySignature: "sig_1",
    });

    expect(rpc).toHaveBeenCalledWith("record_payment_attempt", {
      p_payment_order_id: "po-1",
      p_status: "PAYMENT_ATTEMPTED",
      p_razorpay_payment_id: "pay_1",
      p_razorpay_signature: "sig_1",
    });
  });

  it("maps an RPC error to PAYMENT_ORDER_ERROR", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { message: "not found" } }));
    const service = new SupabasePaymentService({ rpc } as never);

    await expect(
      service.recordPaymentAttempt({ paymentOrderId: "po-1", status: "FAILED" }),
    ).rejects.toMatchObject({ code: "PAYMENT_ORDER_ERROR" });
  });
});

describe("SupabasePaymentService.verifyPaymentOrder", () => {
  it("invokes verify-razorpay-payment with exactly the four required fields and returns the server's status", async () => {
    const invoke = vi.fn(async () => ({ data: { paymentOrderId: "po-1", status: "CAPTURED" }, error: null }));
    const service = new SupabasePaymentService({ functions: { invoke } } as never);

    const result = await service.verifyPaymentOrder({
      paymentOrderId: "po-1",
      razorpayOrderId: "order_1",
      razorpayPaymentId: "pay_1",
      razorpaySignature: "sig_1",
    });

    expect(invoke).toHaveBeenCalledWith("verify-razorpay-payment", {
      body: { paymentOrderId: "po-1", razorpayOrderId: "order_1", razorpayPaymentId: "pay_1", razorpaySignature: "sig_1" },
    });
    expect(result).toEqual({ paymentOrderId: "po-1", status: "CAPTURED" });
  });

  it("never reports a client-claimed success on its own — a gateway failure throws instead of returning a fabricated status", async () => {
    const invoke = vi.fn(async () => ({ data: null, error: { message: "network down" } }));
    const service = new SupabasePaymentService({ functions: { invoke } } as never);

    await expect(
      service.verifyPaymentOrder({ paymentOrderId: "po-1", razorpayOrderId: "order_1", razorpayPaymentId: "pay_1", razorpaySignature: "sig_1" }),
    ).rejects.toMatchObject({ code: "PAYMENT_GATEWAY_ERROR" });
  });

  it("surfaces a rejected verification (e.g. amount mismatch) as PAYMENT_ORDER_ERROR, never as a success", async () => {
    const invoke = vi.fn(async () => ({ data: { error: "Payment could not be verified. Please contact the facility." }, error: null }));
    const service = new SupabasePaymentService({ functions: { invoke } } as never);

    await expect(
      service.verifyPaymentOrder({ paymentOrderId: "po-1", razorpayOrderId: "order_1", razorpayPaymentId: "pay_1", razorpaySignature: "sig_1" }),
    ).rejects.toMatchObject({ code: "PAYMENT_ORDER_ERROR" });
  });
});

describe("SupabasePaymentService.reconcilePaymentOrder", () => {
  it("invokes reconcile-razorpay-payment with just the payment order id", async () => {
    const invoke = vi.fn(async () => ({ data: { paymentOrderId: "po-1", status: "PAYMENT_VERIFIED" }, error: null }));
    const service = new SupabasePaymentService({ functions: { invoke } } as never);

    const result = await service.reconcilePaymentOrder({ paymentOrderId: "po-1" });

    expect(invoke).toHaveBeenCalledWith("reconcile-razorpay-payment", { body: { paymentOrderId: "po-1" } });
    expect(result).toEqual({ paymentOrderId: "po-1", status: "PAYMENT_VERIFIED" });
  });
});

describe("SupabasePaymentService.getPaymentOrderStatus", () => {
  it("reads status via the existing RLS-scoped get_payment_order RPC — never a new privileged read path", async () => {
    const rpc = vi.fn(async () => ({ data: { id: "po-1", status: "AUTHORIZED" }, error: null }));
    const service = new SupabasePaymentService({ rpc } as never);

    const result = await service.getPaymentOrderStatus("po-1");

    expect(rpc).toHaveBeenCalledWith("get_payment_order", { p_payment_order_id: "po-1" });
    expect(result).toEqual({ paymentOrderId: "po-1", status: "AUTHORIZED" });
  });

  it("throws rather than returning a stale/empty status when the order isn't found or isn't visible to this caller", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: null }));
    const service = new SupabasePaymentService({ rpc } as never);

    await expect(service.getPaymentOrderStatus("po-missing")).rejects.toMatchObject({ code: "PAYMENT_ORDER_ERROR" });
  });
});