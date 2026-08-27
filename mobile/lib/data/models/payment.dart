/// Razorpay Payment Foundation — mirrors src/features/payments/types.ts
/// exactly. See supabase/migrations/0016_payment_orders.sql and
/// supabase/functions/create-razorpay-order/index.ts for the authoritative
/// backend contract this ports. Foundation only: this phase never opens a
/// checkout UI, never confirms a payment, and never marks a booking or
/// membership as paid.
library;

/// Mirrors payment_source_type (supabase/migrations/0016_payment_orders.sql).
enum PaymentSourceType {
  membership,
  memberBooking,
  guestBooking;

  String toJson() {
    switch (this) {
      case PaymentSourceType.membership:
        return 'MEMBERSHIP';
      case PaymentSourceType.memberBooking:
        return 'MEMBER_BOOKING';
      case PaymentSourceType.guestBooking:
        return 'GUEST_BOOKING';
    }
  }

  /// Added for Phase 6 (refunds/settlement exceptions read `source_type` off
  /// `refunds`/`settlement_exceptions` rows) — Phase 1-5 never needed to
  /// parse this enum back from a string.
  static PaymentSourceType fromJson(String value) {
    switch (value) {
      case 'MEMBERSHIP':
        return PaymentSourceType.membership;
      case 'MEMBER_BOOKING':
        return PaymentSourceType.memberBooking;
      case 'GUEST_BOOKING':
        return PaymentSourceType.guestBooking;
      default:
        throw ArgumentError('Unknown PaymentSourceType: $value');
    }
  }
}

/// Mirrors payment_order_status (supabase/migrations/0016_payment_orders.sql,
/// supabase/migrations/0018_payment_verification_enum.sql) and
/// src/features/payments/types.ts's `PaymentOrderStatus` union exactly,
/// including position — `paymentVerificationPending`/`paymentVerified` sit
/// between `paymentAttempted` and `authorized`. Read from
/// `verify-razorpay-payment` / `reconcile-razorpay-payment` responses and the
/// `get_payment_order` RPC.
enum PaymentOrderStatus {
  created,
  orderCreated,
  paymentAttempted,
  paymentVerificationPending,
  paymentVerified,
  authorized,
  captured,
  completed,
  settlementException,
  failed,
  cancelled,
  refundRequested,
  partiallyRefunded,
  refunded;

  static PaymentOrderStatus fromJson(String value) {
    switch (value) {
      case 'CREATED':
        return PaymentOrderStatus.created;
      case 'ORDER_CREATED':
        return PaymentOrderStatus.orderCreated;
      case 'PAYMENT_ATTEMPTED':
        return PaymentOrderStatus.paymentAttempted;
      case 'PAYMENT_VERIFICATION_PENDING':
        return PaymentOrderStatus.paymentVerificationPending;
      case 'PAYMENT_VERIFIED':
        return PaymentOrderStatus.paymentVerified;
      case 'AUTHORIZED':
        return PaymentOrderStatus.authorized;
      case 'CAPTURED':
        return PaymentOrderStatus.captured;
      case 'COMPLETED':
        return PaymentOrderStatus.completed;
      case 'SETTLEMENT_EXCEPTION':
        return PaymentOrderStatus.settlementException;
      case 'FAILED':
        return PaymentOrderStatus.failed;
      case 'CANCELLED':
        return PaymentOrderStatus.cancelled;
      case 'REFUND_REQUESTED':
        return PaymentOrderStatus.refundRequested;
      case 'PARTIALLY_REFUNDED':
        return PaymentOrderStatus.partiallyRefunded;
      case 'REFUNDED':
        return PaymentOrderStatus.refunded;
      default:
        throw ArgumentError('Unknown PaymentOrderStatus: $value');
    }
  }
}

/// What the caller sends to start a payment. Deliberately has no `amount`
/// field — the server (create_payment_order RPC) always computes the
/// authoritative amount itself from the referenced booking/membership row;
/// the client's amount is never read, let alone trusted.
class CreatePaymentOrderInput {
  const CreatePaymentOrderInput({
    required this.facilityId,
    required this.sourceType,
    this.bookingId,
    this.membershipSessionBookingId,
    this.memberId,
    this.planId,
  });

  final String facilityId;
  final PaymentSourceType sourceType;

  /// MEMBER_BOOKING, or GUEST_BOOKING via an ad-hoc guest booking row.
  final String? bookingId;

  /// GUEST_BOOKING via a released membership-capacity slot.
  final String? membershipSessionBookingId;

  /// MEMBERSHIP only.
  final String? memberId;

  /// MEMBERSHIP only.
  final String? planId;
}

/// What the client is allowed to know after starting a payment — never the
/// Razorpay Key Secret, never a service-role key. [keyId] is safe to hand to
/// the Razorpay Flutter SDK in a later phase.
class PaymentOrderCheckoutInfo {
  const PaymentOrderCheckoutInfo({
    required this.keyId,
    required this.razorpayOrderId,
    required this.amount,
    required this.currency,
    required this.paymentOrderId,
    required this.receipt,
  });

  final String keyId;
  final String razorpayOrderId;

  /// Minor units (paise) — the authoritative, server-computed amount.
  final int amount;
  final String currency;
  final String paymentOrderId;
  final String receipt;

  factory PaymentOrderCheckoutInfo.fromJson(Map<String, dynamic> json) {
    return PaymentOrderCheckoutInfo(
      keyId: json['keyId'] as String,
      razorpayOrderId: json['razorpayOrderId'] as String,
      amount: (json['amount'] as num).toInt(),
      currency: json['currency'] as String,
      paymentOrderId: json['paymentOrderId'] as String,
      receipt: json['receipt'] as String,
    );
  }
}

/// The only two outcomes record_payment_attempt accepts — see
/// supabase/migrations/0017_record_payment_attempt.sql. A plain user
/// cancellation is never recorded here; it leaves the order retryable.
enum PaymentAttemptStatus {
  paymentAttempted,
  failed;

  String toJson() {
    switch (this) {
      case PaymentAttemptStatus.paymentAttempted:
        return 'PAYMENT_ATTEMPTED';
      case PaymentAttemptStatus.failed:
        return 'FAILED';
    }
  }
}

/// Phase 4 — mirrors src/features/payments/types.ts's `VerifyPaymentInput`.
/// What `verify-razorpay-payment` needs to independently re-check the
/// signature and Razorpay's own payment status/amount/currency before
/// advancing `payment_orders.status`. The client's own success callback is
/// never trusted on its own; this is what turns it into a verified result.
class VerifyPaymentInput {
  const VerifyPaymentInput({
    required this.paymentOrderId,
    required this.razorpayOrderId,
    required this.razorpayPaymentId,
    required this.razorpaySignature,
  });

  final String paymentOrderId;
  final String razorpayOrderId;
  final String razorpayPaymentId;
  final String razorpaySignature;
}

/// Mirrors src/features/payments/types.ts's `ReconcilePaymentInput`. On-demand
/// recovery for a payment order stuck pending — asks Razorpay directly via
/// `reconcile-razorpay-payment`. Not for polling; call it when the user
/// explicitly asks to check again.
class ReconcilePaymentInput {
  const ReconcilePaymentInput({required this.paymentOrderId});

  final String paymentOrderId;
}

/// Mirrors src/features/payments/types.ts's `SettlePaymentInput`. Manual
/// retry path for a payment order left at plain CAPTURED because the inline
/// settlement `apply_payment_verification` normally performs (0021_payment_
/// settlement.sql) hit a transient failure — calls `settle-payment` directly.
class SettlePaymentInput {
  const SettlePaymentInput({required this.paymentOrderId});

  final String paymentOrderId;
}

/// Mirrors src/features/payments/types.ts's `PaymentVerificationResult` —
/// what `verify-razorpay-payment` / `reconcile-razorpay-payment` /
/// `get_payment_order` hand back: the server's authoritative status, never
/// the client's claim.
class PaymentVerificationResult {
  const PaymentVerificationResult({required this.paymentOrderId, required this.status});

  final String paymentOrderId;
  final PaymentOrderStatus status;

  factory PaymentVerificationResult.fromJson(Map<String, dynamic> json) {
    return PaymentVerificationResult(
      paymentOrderId: json['paymentOrderId'] as String,
      status: PaymentOrderStatus.fromJson(json['status'] as String),
    );
  }
}