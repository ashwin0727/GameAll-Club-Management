"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import { toBooking } from "@/services/bookings/supabase-booking.service";
import type {
  BookingCancellationQuote,
  BookingCancellationSummary,
  OfflineRefundDue,
  CancelBookingInput,
  CancelMembershipInput,
  CancelMembershipSlotInput,
  CancellationPolicy,
  InitiateRefundInput,
  Refund,
  RefundListFilters,
  RefundSubmission,
  SettlementException,
  SettlementExceptionListFilters,
  UpsertCancellationPolicyInput,
} from "@/features/refunds/types";
import type { RefundService } from "@/services/refunds/refund.service";
import { ServiceError } from "@/services/shared/service-error";
import type { Database } from "@/types/database.types";

type RefundRow = Database["public"]["Tables"]["refunds"]["Row"];
type SettlementExceptionRow = Database["public"]["Tables"]["settlement_exceptions"]["Row"];
type CancellationPolicyRow = Database["public"]["Tables"]["cancellation_policies"]["Row"];

function toRefund(row: RefundRow): Refund {
  return {
    id: row.id,
    facilityId: row.facility_id,
    paymentOrderId: row.payment_order_id,
    transactionId: row.transaction_id,
    sourceType: row.source_type,
    sourceId: row.source_id,
    razorpayPaymentId: row.razorpay_payment_id,
    razorpayRefundId: row.razorpay_refund_id,
    amountMinor: row.amount_minor,
    currency: row.currency,
    reason: row.reason,
    status: row.status,
    isOverride: row.is_override,
    overrideReason: row.override_reason,
    policyPercentApplied: row.policy_percent_applied,
    failureReason: row.failure_reason,
    initiatedBy: row.initiated_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    processedAt: row.processed_at,
  };
}

function toSettlementException(row: SettlementExceptionRow): SettlementException {
  return {
    id: row.id,
    facilityId: row.facility_id,
    paymentOrderId: row.payment_order_id,
    transactionId: row.transaction_id,
    sourceType: row.source_type,
    sourceId: row.source_id,
    reason: row.reason,
    status: row.status,
    createdAt: row.created_at,
    resolvedAt: row.resolved_at,
  };
}

function toCancellationPolicy(row: CancellationPolicyRow): CancellationPolicy {
  return {
    facilityId: row.facility_id,
    fullRefundHours: row.full_refund_hours,
    fullRefundPercent: row.full_refund_percent,
    partialRefundHours: row.partial_refund_hours,
    partialRefundPercent: row.partial_refund_percent,
  };
}

interface RefundSubmissionResponse {
  refundId: string;
  status: string;
  razorpayRefundId?: string;
}

interface EdgeFunctionError {
  error: string;
}

function toSubmission(response: RefundSubmissionResponse): RefundSubmission {
  return { id: response.refundId, status: response.status as RefundSubmission["status"], razorpayRefundId: response.razorpayRefundId };
}

export class SupabaseRefundService implements RefundService {
  private readonly supabase: SupabaseClient<Database>;

  constructor(client?: SupabaseClient<Database>) {
    this.supabase = client ?? createClient();
  }

  async cancelBooking(
    input: CancelBookingInput,
  ): Promise<{ booking: import("@/features/bookings/types").Booking; refund: RefundSubmission | null; refunds: RefundSubmission[]; cancellation: BookingCancellationSummary | null }> {
    const { data, error } = await this.supabase.functions.invoke<
      | {
          booking: Database["public"]["Tables"]["bookings"]["Row"];
          refund: RefundSubmissionResponse | null;
          refunds?: RefundSubmissionResponse[];
          cancellation?: {
            hours_until_start: number;
            rule: string;
            deduction_percent: number;
            refund_percent: number;
            is_override: boolean;
            total_minor: number;
            paid_minor: number;
            refund_minor: number;
            online_refund_minor: number;
            offline_refund_due_minor: number;
          } | null;
        }
      | EdgeFunctionError
    >("cancel-booking", {
      body: { bookingId: input.bookingId, reason: input.reason, refundOverridePercent: input.refundOverridePercent, overrideReason: input.overrideReason },
    });
    if (error) {
      console.error("[refund-service] cancel-booking failed", error);
      throw new ServiceError("PAYMENT_GATEWAY_ERROR");
    }
    if (!data || "error" in data) {
      throw new ServiceError("PAYMENT_ORDER_ERROR", data && "error" in data ? data.error : undefined);
    }
    const c = data.cancellation;
    return {
      booking: toBooking(data.booking),
      refund: data.refund ? toSubmission(data.refund) : null,
      refunds: (data.refunds ?? []).map(toSubmission),
      cancellation: c
        ? {
            hoursUntilStart: Number(c.hours_until_start),
            rule: c.rule,
            deductionPercent: c.deduction_percent,
            refundPercent: c.refund_percent,
            isOverride: c.is_override,
            totalMinor: c.total_minor,
            paidMinor: c.paid_minor,
            refundMinor: c.refund_minor,
            onlineRefundMinor: c.online_refund_minor,
            offlineRefundDueMinor: c.offline_refund_due_minor,
          }
        : null,
    };
  }

  async listOfflineRefundsDue(facilityId: string): Promise<OfflineRefundDue[]> {
    const { data, error } = await this.supabase.rpc("list_offline_refunds_due" as never, { p_facility_id: facilityId } as never);
    if (error) {
      console.error("[refund-service] list_offline_refunds_due failed", error);
      return [];
    }
    return (data as unknown as OfflineRefundDue[] | null) ?? [];
  }

  async settleOfflineRefund(bookingId: string): Promise<void> {
    const { error } = await this.supabase.rpc("settle_offline_refund" as never, { p_booking_id: bookingId } as never);
    if (error) throw new ServiceError("DATABASE_ERROR", error.message);
  }

  async bookingCancellationQuote(bookingId: string, overridePercent?: number): Promise<BookingCancellationQuote | null> {
    const { data, error } = await this.supabase.rpc("staff_booking_cancellation_quote" as never, {
      p_booking_id: bookingId,
      p_override_percent: overridePercent ?? null,
    } as never);
    if (error || !data) {
      if (error) console.error("[refund-service] staff_booking_cancellation_quote failed", error);
      return null;
    }
    return data as unknown as BookingCancellationQuote;
  }

  async cancelMembershipSlot(input: CancelMembershipSlotInput): Promise<{ refund: RefundSubmission | null }> {
    const { data, error } = await this.supabase.functions.invoke<{ booking: unknown; refund: RefundSubmissionResponse | null } | EdgeFunctionError>("cancel-membership-slot", {
      body: { bookingId: input.bookingId, reason: input.reason, refundOverridePercent: input.refundOverridePercent, overrideReason: input.overrideReason },
    });
    if (error) {
      console.error("[refund-service] cancel-membership-slot failed", error);
      throw new ServiceError("PAYMENT_GATEWAY_ERROR");
    }
    if (!data || "error" in data) {
      throw new ServiceError("PAYMENT_ORDER_ERROR", data && "error" in data ? data.error : undefined);
    }
    return { refund: data.refund ? toSubmission(data.refund) : null };
  }

  async cancelMembership(input: CancelMembershipInput): Promise<{ refund: RefundSubmission | null }> {
    const { data, error } = await this.supabase.functions.invoke<{ membership: unknown; refund: RefundSubmissionResponse | null } | EdgeFunctionError>("cancel-membership", {
      body: { membershipId: input.membershipId, reason: input.reason, refundAmountMinor: input.refundAmountMinor, overrideReason: input.overrideReason },
    });
    if (error) {
      console.error("[refund-service] cancel-membership failed", error);
      throw new ServiceError("PAYMENT_GATEWAY_ERROR");
    }
    if (!data || "error" in data) {
      throw new ServiceError("PAYMENT_ORDER_ERROR", data && "error" in data ? data.error : undefined);
    }
    return { refund: data.refund ? toSubmission(data.refund) : null };
  }

  async initiateRefund(input: InitiateRefundInput): Promise<RefundSubmission> {
    const { data, error } = await this.supabase.functions.invoke<RefundSubmissionResponse | EdgeFunctionError>("create-razorpay-refund", {
      body: {
        paymentOrderId: input.paymentOrderId,
        settlementExceptionId: input.settlementExceptionId,
        amountMinor: input.amountMinor,
        reason: input.reason,
        overrideReason: input.overrideReason,
      },
    });
    if (error) {
      console.error("[refund-service] create-razorpay-refund failed", error);
      throw new ServiceError("PAYMENT_GATEWAY_ERROR");
    }
    if (!data || "error" in data) {
      throw new ServiceError("PAYMENT_ORDER_ERROR", data && "error" in data ? data.error : undefined);
    }
    return toSubmission(data);
  }

  async refundableAmount(paymentOrderId: string): Promise<number> {
    const { data, error } = await this.supabase.rpc("refundable_amount", { p_payment_order_id: paymentOrderId });
    if (error) {
      console.error("[refund-service] refundable_amount failed", error);
      throw new ServiceError("PAYMENT_ORDER_ERROR", error.message);
    }
    return data ?? 0;
  }

  async listRefunds(facilityId: string, filters: RefundListFilters = {}): Promise<Refund[]> {
    const { data, error } = await this.supabase.rpc("list_refunds", {
      p_facility_id: facilityId,
      p_status: filters.status ?? null,
      p_source_type: filters.sourceType ?? null,
      p_preset: filters.dateRange?.preset ?? null,
      p_start_date: filters.dateRange?.startDate ?? null,
      p_end_date: filters.dateRange?.endDate ?? null,
      p_limit: filters.limit ?? 100,
      p_offset: filters.offset ?? 0,
    });
    if (error) throw new ServiceError("PAYMENT_ORDER_ERROR", error.message);
    return (data ?? []).map(toRefund);
  }

  async listSettlementExceptions(facilityId: string, filters: SettlementExceptionListFilters = { status: "OPEN" }): Promise<SettlementException[]> {
    const { data, error } = await this.supabase.rpc("list_settlement_exceptions", {
      p_facility_id: facilityId,
      p_status: filters.status === undefined ? "OPEN" : filters.status,
      p_source_type: filters.sourceType ?? null,
      p_preset: filters.dateRange?.preset ?? null,
      p_start_date: filters.dateRange?.startDate ?? null,
      p_end_date: filters.dateRange?.endDate ?? null,
    });
    if (error) throw new ServiceError("PAYMENT_ORDER_ERROR", error.message);
    return (data ?? []).map(toSettlementException);
  }

  async getCancellationPolicy(facilityId: string): Promise<CancellationPolicy> {
    const { data, error } = await this.supabase.rpc("get_effective_cancellation_policy", { p_facility_id: facilityId });
    if (error || !data) throw new ServiceError("PAYMENT_ORDER_ERROR", error?.message);
    return toCancellationPolicy(data);
  }

  async upsertCancellationPolicy(input: UpsertCancellationPolicyInput): Promise<CancellationPolicy> {
    const { data, error } = await this.supabase.rpc("upsert_cancellation_policy", {
      p_facility_id: input.facilityId,
      p_full_refund_hours: input.fullRefundHours,
      p_full_refund_percent: input.fullRefundPercent,
      p_partial_refund_hours: input.partialRefundHours,
      p_partial_refund_percent: input.partialRefundPercent,
    });
    if (error || !data) throw new ServiceError("PAYMENT_ORDER_ERROR", error?.message);
    return toCancellationPolicy(data);
  }
}