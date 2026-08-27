import type {
  CreatePaymentOrderInput,
  PaymentOrderCheckoutInfo,
  PaymentVerificationResult,
  ReconcilePaymentInput,
  RecordPaymentAttemptInput,
  SettlePaymentInput,
  VerifyPaymentInput,
} from "@/features/payments/types";

export interface PaymentService {
  /**
   * The single write path for starting a payment, regardless of source
   * (membership purchase, member booking, or guest booking). Calls the
   * `create-razorpay-order` Edge Function — the only place the Razorpay
   * secret exists — which validates the request server-side and computes
   * the authoritative amount itself; the client never sends an amount.
   *
   * Creating an order does NOT mean the payment succeeded, the booking is
   * confirmed, or the membership is active — those all wait for a later
   * phase's payment verification.
   */
  createPaymentOrder(input: CreatePaymentOrderInput): Promise<PaymentOrderCheckoutInfo>;

  /**
   * Records the raw, unverified result Razorpay Checkout hands back after a
   * payment attempt (success or failure) — never a user cancellation, which
   * leaves the order retryable. Does not verify a signature, does not
   * confirm a booking, and does not activate a membership; that is a later
   * phase's job.
   */
  recordPaymentAttempt(input: RecordPaymentAttemptInput): Promise<void>;

  /**
   * Server-side authority for "did this payment actually succeed?" — calls
   * `verify-razorpay-payment`, which independently re-checks the signature
   * and Razorpay's own payment status/amount/currency before advancing
   * `payment_orders.status`. The client's own success callback is never
   * trusted on its own; this is what turns it into a verified result.
   */
  verifyPaymentOrder(input: VerifyPaymentInput): Promise<PaymentVerificationResult>;

  /**
   * On-demand recovery for a payment order stuck pending (lost client
   * callback, webhook not yet arrived) — asks Razorpay directly via
   * `reconcile-razorpay-payment`. Not for polling; call it when the user
   * explicitly asks to check again.
   */
  reconcilePaymentOrder(input: ReconcilePaymentInput): Promise<PaymentVerificationResult>;

  /** Reads the current authoritative status for a payment order (RLS-scoped) — what payment status UI should poll/display, never Razorpay directly. */
  getPaymentOrderStatus(paymentOrderId: string): Promise<PaymentVerificationResult>;

  /**
   * Manual retry for a payment stuck at CAPTURED because business
   * settlement (confirm the booking / activate the membership) hit a
   * transient failure — calls `settle-payment`. Settlement normally
   * already happens automatically the instant a payment is verified as
   * captured; this exists only for the retry path. Fully idempotent — a
   * business rejection (cancelled booking, deactivated plan, ...) already
   * resolved to SETTLEMENT_EXCEPTION and calling this again will not
   * change that.
   */
  settlePaymentOrder(input: SettlePaymentInput): Promise<PaymentVerificationResult>;
}