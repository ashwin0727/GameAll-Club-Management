// ═══════════════════════════════════════════════════════════════════════════
// Cancellation, Refund & Payment Recovery — Phase 6.
//
// Mirrors 0023_cancellation_refunds.sql exactly: `refunds` is the append-
// only ledger of money given back (never mutates the original `payments`
// transaction row), separate from a booking/membership's own status
// (spec §39/§44 — "Booking cancellation and refund must remain separately
// traceable").
// ═══════════════════════════════════════════════════════════════════════════

import type { PaymentSourceType } from "@/features/payments/types";
import type { FinanceDateRange } from "@/features/finance/types";

export type RefundStatus = "REQUESTED" | "PROCESSING" | "PENDING" | "PROCESSED" | "FAILED" | "CANCELLED";

export type RefundReason =
  | "CUSTOMER_CANCELLATION"
  | "FACILITY_CANCELLATION"
  | "COURT_UNAVAILABLE"
  | "SETTLEMENT_EXCEPTION"
  | "DUPLICATE_PAYMENT"
  | "OWNER_OVERRIDE"
  | "OTHER";

export interface Refund {
  id: string;
  facilityId: string;
  paymentOrderId: string;
  transactionId: string | null;
  sourceType: PaymentSourceType;
  sourceId: string | null;
  razorpayPaymentId: string;
  razorpayRefundId: string | null;
  amountMinor: number;
  currency: string;
  reason: RefundReason;
  status: RefundStatus;
  isOverride: boolean;
  overrideReason: string | null;
  policyPercentApplied: number | null;
  failureReason: string | null;
  initiatedBy: string | null;
  createdAt: string;
  updatedAt: string;
  processedAt: string | null;
}

export type SettlementExceptionReason = "BOOKING_NO_LONGER_AVAILABLE" | "GUEST_CAPACITY_EXHAUSTED" | "MEMBERSHIP_INVALID" | "BUSINESS_VALIDATION_FAILED" | "DATABASE_SETTLEMENT_FAILURE";

export interface SettlementException {
  id: string;
  facilityId: string;
  paymentOrderId: string;
  transactionId: string | null;
  sourceType: PaymentSourceType;
  sourceId: string | null;
  reason: SettlementExceptionReason;
  status: "OPEN" | "RESOLVED";
  createdAt: string;
  resolvedAt: string | null;
}

export interface CancellationPolicy {
  facilityId: string;
  fullRefundHours: number;
  fullRefundPercent: number;
  partialRefundHours: number;
  partialRefundPercent: number;
}

export interface UpsertCancellationPolicyInput {
  facilityId: string;
  fullRefundHours: number;
  fullRefundPercent: number;
  partialRefundHours: number;
  partialRefundPercent: number;
}

/** What a cancellation/refund submission returns for the refund it created (if any) — never the client's own claim about status, always the server's. */
export interface RefundSubmission {
  id: string;
  status: RefundStatus;
  razorpayRefundId?: string;
}

export interface CancelBookingInput {
  bookingId: string;
  reason?: string;
  /** Owner override — replaces the policy-computed refund percent (0-100). */
  refundOverridePercent?: number;
  overrideReason?: string;
}

export interface CancelMembershipSlotInput {
  /** membership_session_bookings.id */
  bookingId: string;
  reason?: string;
  refundOverridePercent?: number;
  overrideReason?: string;
}

export interface CancelMembershipInput {
  membershipId: string;
  reason?: string;
  /** Explicit owner-decided refund amount — omit for no refund (spec §14/§15). */
  refundAmountMinor?: number;
  overrideReason?: string;
}

/** Finance → Refunds filters (spec §"Refund Filters"). */
export interface RefundListFilters {
  status?: RefundStatus;
  sourceType?: PaymentSourceType;
  dateRange?: FinanceDateRange;
  limit?: number;
  offset?: number;
}

/** Finance → Settlement Exceptions filters (spec §"Exception Filters"). Only OPEN/RESOLVED exist in this app's data model — there is no intermediate "processing" state for a settlement exception. */
export interface SettlementExceptionListFilters {
  status?: "OPEN" | "RESOLVED" | null;
  sourceType?: PaymentSourceType;
  dateRange?: FinanceDateRange;
}

export interface InitiateRefundInput {
  /** Exactly one of paymentOrderId or settlementExceptionId. */
  paymentOrderId?: string;
  settlementExceptionId?: string;
  /** Required with paymentOrderId; ignored for settlementExceptionId (always a full refund). */
  amountMinor?: number;
  reason?: RefundReason;
  overrideReason?: string;
}