export type PaymentSourceType = "MEMBERSHIP" | "MEMBER_BOOKING" | "GUEST_BOOKING";

export type PaymentOrderStatus =
  | "CREATED"
  | "ORDER_CREATED"
  | "PAYMENT_ATTEMPTED"
  | "PAYMENT_VERIFICATION_PENDING"
  | "PAYMENT_VERIFIED"
  | "AUTHORIZED"
  | "CAPTURED"
  | "COMPLETED"
  | "FAILED"
  | "CANCELLED"
  | "REFUND_REQUESTED"
  | "REFUNDED";

export interface CreatePaymentOrderInput {
  facilityId: string;
  sourceType: PaymentSourceType;
  /** MEMBER_BOOKING, or GUEST_BOOKING via an ad-hoc guest booking row. */
  bookingId?: string;
  /** GUEST_BOOKING via a released membership-capacity slot. */
  membershipSessionBookingId?: string;
  /** MEMBERSHIP only. */
  memberId?: string;
  /** MEMBERSHIP only. */
  planId?: string;
}

/**
 * What the client is allowed to know after starting a payment — never the
 * Razorpay Key Secret, never a service-role key. `keyId` is safe to hand to
 * Razorpay Checkout (web) / the Razorpay Flutter SDK.
 */
export interface PaymentOrderCheckoutInfo {
  keyId: string;
  razorpayOrderId: string;
  /** Minor units (paise) — the authoritative, server-computed amount. */
  amount: number;
  currency: string;
  paymentOrderId: string;
  receipt: string;
}

/** The only two outcomes record_payment_attempt accepts — see 0017_record_payment_attempt.sql. */
export type PaymentAttemptStatus = "PAYMENT_ATTEMPTED" | "FAILED";

export interface RecordPaymentAttemptInput {
  paymentOrderId: string;
  status: PaymentAttemptStatus;
  razorpayPaymentId?: string;
  razorpaySignature?: string;
}

export interface VerifyPaymentInput {
  paymentOrderId: string;
  razorpayOrderId: string;
  razorpayPaymentId: string;
  razorpaySignature: string;
}

export interface ReconcilePaymentInput {
  paymentOrderId: string;
}

/** What verify-razorpay-payment / reconcile-razorpay-payment hand back — the server's authoritative status, never the client's claim. */
export interface PaymentVerificationResult {
  paymentOrderId: string;
  status: PaymentOrderStatus;
}