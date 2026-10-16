"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import type {
  BookingPaymentLink,
  BookingPaymentLinkInput,
  BookingPaymentLinkStatus,
  CreatePaymentOrderInput,
  PaymentOrderCheckoutInfo,
  PaymentOrderStatus,
  PaymentVerificationResult,
  ReconcilePaymentInput,
  RecordPaymentAttemptInput,
  SettlePaymentInput,
  VerifyPaymentInput,
} from "@/features/payments/types";
import type { PaymentService } from "@/services/payments/payment.service";
import { ServiceError } from "@/services/shared/service-error";
import type { Database } from "@/types/database.types";

interface EdgeFunctionSuccess {
  keyId: string;
  razorpayOrderId: string;
  amount: number;
  currency: string;
  paymentOrderId: string;
  receipt: string;
}

interface BookingLinkResponse {
  paymentOrderId?: string;
  bookingId?: string;
  shortUrl?: string | null;
  amountMinor?: number;
  currency?: string;
  status?: string;
  paid?: boolean;
  expiresAt?: string;
  reused?: boolean;
}

interface EdgeFunctionError {
  error: string;
}

interface VerifyFunctionResponse {
  paymentOrderId: string;
  status: PaymentOrderStatus;
}

export class SupabasePaymentService implements PaymentService {
  private readonly supabase: SupabaseClient<Database>;

  constructor(client?: SupabaseClient<Database>) {
    this.supabase = client ?? createClient();
  }

  createBookingPaymentLink(input: BookingPaymentLinkInput): Promise<BookingPaymentLink> {
    return this.callBookingPaymentLink("create", input);
  }

  checkBookingPaymentLink(input: BookingPaymentLinkInput): Promise<BookingPaymentLink> {
    return this.callBookingPaymentLink("status", input);
  }

  cancelBookingPaymentLink(input: BookingPaymentLinkInput): Promise<BookingPaymentLink> {
    return this.callBookingPaymentLink("cancel", input);
  }

  private async callBookingPaymentLink(action: "create" | "status" | "cancel", input: BookingPaymentLinkInput): Promise<BookingPaymentLink> {
    const { data, error } = await this.supabase.functions.invoke<BookingLinkResponse | EdgeFunctionError>("create-booking-payment-link", {
      body: { action, facilityId: input.facilityId, bookingId: input.bookingId },
    });
    if (error) {
      // The function answers a business problem (not found, not payable, Razorpay down) with a non-2xx and a
      // readable { error } body — surface that text rather than a generic failure.
      let message: string | undefined;
      try {
        const body = (await (error as { context?: Response }).context?.json()) as { error?: string } | undefined;
        message = body?.error;
      } catch {
        // not a JSON body
      }
      console.error("[payment-service] create-booking-payment-link failed", error);
      throw new ServiceError(message ? "PAYMENT_ORDER_ERROR" : "PAYMENT_GATEWAY_ERROR", message);
    }
    if (!data || "error" in data) {
      throw new ServiceError("PAYMENT_ORDER_ERROR", data && "error" in data ? data.error : undefined);
    }
    const paid = data.paid === true || data.status === "PAID";
    return {
      paymentOrderId: data.paymentOrderId ?? null,
      bookingId: data.bookingId ?? input.bookingId,
      shortUrl: data.shortUrl ?? null,
      amountMinor: data.amountMinor ?? null,
      currency: data.currency ?? null,
      status: paid ? "PAID" : ((data.status as BookingPaymentLinkStatus | undefined) ?? "CREATED"),
      paid,
      expiresAt: data.expiresAt ?? null,
      reused: data.reused === true,
    };
  }

  async createPaymentOrder(input: CreatePaymentOrderInput): Promise<PaymentOrderCheckoutInfo> {
    const { data, error } = await this.supabase.functions.invoke<EdgeFunctionSuccess | EdgeFunctionError>("create-razorpay-order", {
      body: {
        facilityId: input.facilityId,
        sourceType: input.sourceType,
        bookingId: input.bookingId,
        membershipSessionBookingId: input.membershipSessionBookingId,
        memberId: input.memberId,
        planId: input.planId,
      },
    });

    if (error) {
      console.error("[payment-service] create-razorpay-order failed", error);
      throw new ServiceError("PAYMENT_GATEWAY_ERROR");
    }
    if (!data || "error" in data) {
      throw new ServiceError("PAYMENT_ORDER_ERROR", data && "error" in data ? data.error : undefined);
    }

    return {
      keyId: data.keyId,
      razorpayOrderId: data.razorpayOrderId,
      amount: data.amount,
      currency: data.currency,
      paymentOrderId: data.paymentOrderId,
      receipt: data.receipt,
    };
  }

  async recordPaymentAttempt(input: RecordPaymentAttemptInput): Promise<void> {
    const { error } = await this.supabase.rpc("record_payment_attempt", {
      p_payment_order_id: input.paymentOrderId,
      p_status: input.status,
      p_razorpay_payment_id: input.razorpayPaymentId,
      p_razorpay_signature: input.razorpaySignature,
    });

    if (error) {
      console.error("[payment-service] record_payment_attempt failed", error);
      throw new ServiceError("PAYMENT_ORDER_ERROR", error.message);
    }
  }

  async verifyPaymentOrder(input: VerifyPaymentInput): Promise<PaymentVerificationResult> {
    const { data, error } = await this.supabase.functions.invoke<VerifyFunctionResponse>("verify-razorpay-payment", {
      body: {
        paymentOrderId: input.paymentOrderId,
        razorpayOrderId: input.razorpayOrderId,
        razorpayPaymentId: input.razorpayPaymentId,
        razorpaySignature: input.razorpaySignature,
      },
    });
    return this.mapVerificationResponse("verify-razorpay-payment", data, error);
  }

  async reconcilePaymentOrder(input: ReconcilePaymentInput): Promise<PaymentVerificationResult> {
    const { data, error } = await this.supabase.functions.invoke<VerifyFunctionResponse>("reconcile-razorpay-payment", {
      body: { paymentOrderId: input.paymentOrderId },
    });
    return this.mapVerificationResponse("reconcile-razorpay-payment", data, error);
  }

  async settlePaymentOrder(input: SettlePaymentInput): Promise<PaymentVerificationResult> {
    const { data, error } = await this.supabase.functions.invoke<VerifyFunctionResponse>("settle-payment", {
      body: { paymentOrderId: input.paymentOrderId },
    });
    return this.mapVerificationResponse("settle-payment", data, error);
  }

  async getPaymentOrderStatus(paymentOrderId: string): Promise<PaymentVerificationResult> {
    const { data, error } = await this.supabase.rpc("get_payment_order", { p_payment_order_id: paymentOrderId });
    if (error || !data) {
      console.error("[payment-service] get_payment_order failed", error);
      throw new ServiceError("PAYMENT_ORDER_ERROR");
    }
    return { paymentOrderId: data.id, status: data.status as PaymentOrderStatus };
  }

  private mapVerificationResponse(
    functionName: string,
    data: VerifyFunctionResponse | EdgeFunctionError | null | undefined,
    error: unknown,
  ): PaymentVerificationResult {
    if (error) {
      console.error(`[payment-service] ${functionName} failed`, error);
      throw new ServiceError("PAYMENT_GATEWAY_ERROR");
    }
    if (!data || "error" in data) {
      throw new ServiceError("PAYMENT_ORDER_ERROR", data && "error" in data ? data.error : undefined);
    }
    return { paymentOrderId: data.paymentOrderId, status: data.status };
  }
}