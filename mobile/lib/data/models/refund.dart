/// Cancellation, Refund & Payment Recovery — Phase 6. Mirrors
/// src/features/refunds/types.ts exactly: `refunds` is the append-only
/// ledger of money given back (never mutates the original `payments`
/// transaction row), separate from a booking/membership's own status (spec
/// §39/§44 — "Booking cancellation and refund must remain separately
/// traceable"). See supabase/migrations/0022_refund_enums.sql and
/// supabase/migrations/0023_cancellation_refunds.sql for the authoritative
/// backend contract this ports.
library;

import 'payment.dart';

/// Mirrors `refund_status` (0022_refund_enums.sql).
enum RefundStatus {
  requested,
  processing,
  pending,
  processed,
  failed,
  cancelled;

  String toJson() {
    switch (this) {
      case RefundStatus.requested:
        return 'REQUESTED';
      case RefundStatus.processing:
        return 'PROCESSING';
      case RefundStatus.pending:
        return 'PENDING';
      case RefundStatus.processed:
        return 'PROCESSED';
      case RefundStatus.failed:
        return 'FAILED';
      case RefundStatus.cancelled:
        return 'CANCELLED';
    }
  }

  static RefundStatus fromJson(String value) {
    switch (value) {
      case 'REQUESTED':
        return RefundStatus.requested;
      case 'PROCESSING':
        return RefundStatus.processing;
      case 'PENDING':
        return RefundStatus.pending;
      case 'PROCESSED':
        return RefundStatus.processed;
      case 'FAILED':
        return RefundStatus.failed;
      case 'CANCELLED':
        return RefundStatus.cancelled;
      default:
        throw ArgumentError('Unknown RefundStatus: $value');
    }
  }
}

/// Mirrors `refund_reason` (0022_refund_enums.sql).
enum RefundReason {
  customerCancellation,
  facilityCancellation,
  courtUnavailable,
  settlementException,
  duplicatePayment,
  ownerOverride,
  other;

  String toJson() {
    switch (this) {
      case RefundReason.customerCancellation:
        return 'CUSTOMER_CANCELLATION';
      case RefundReason.facilityCancellation:
        return 'FACILITY_CANCELLATION';
      case RefundReason.courtUnavailable:
        return 'COURT_UNAVAILABLE';
      case RefundReason.settlementException:
        return 'SETTLEMENT_EXCEPTION';
      case RefundReason.duplicatePayment:
        return 'DUPLICATE_PAYMENT';
      case RefundReason.ownerOverride:
        return 'OWNER_OVERRIDE';
      case RefundReason.other:
        return 'OTHER';
    }
  }

  static RefundReason fromJson(String value) {
    switch (value) {
      case 'CUSTOMER_CANCELLATION':
        return RefundReason.customerCancellation;
      case 'FACILITY_CANCELLATION':
        return RefundReason.facilityCancellation;
      case 'COURT_UNAVAILABLE':
        return RefundReason.courtUnavailable;
      case 'SETTLEMENT_EXCEPTION':
        return RefundReason.settlementException;
      case 'DUPLICATE_PAYMENT':
        return RefundReason.duplicatePayment;
      case 'OWNER_OVERRIDE':
        return RefundReason.ownerOverride;
      case 'OTHER':
        return RefundReason.other;
      default:
        throw ArgumentError('Unknown RefundReason: $value');
    }
  }
}

/// One row per refund attempt against a payment_order — read via the
/// `list_refunds` RPC, which returns raw `refunds` table rows (snake_case).
class Refund {
  const Refund({
    required this.id,
    required this.facilityId,
    required this.paymentOrderId,
    this.transactionId,
    required this.sourceType,
    this.sourceId,
    required this.razorpayPaymentId,
    this.razorpayRefundId,
    required this.amountMinor,
    required this.currency,
    required this.reason,
    required this.status,
    required this.isOverride,
    this.overrideReason,
    this.policyPercentApplied,
    this.failureReason,
    this.initiatedBy,
    required this.createdAt,
    required this.updatedAt,
    this.processedAt,
  });

  final String id;
  final String facilityId;
  final String paymentOrderId;
  final String? transactionId;
  final PaymentSourceType sourceType;
  final String? sourceId;
  final String razorpayPaymentId;
  final String? razorpayRefundId;
  final int amountMinor;
  final String currency;
  final RefundReason reason;
  final RefundStatus status;
  final bool isOverride;
  final String? overrideReason;
  final int? policyPercentApplied;
  final String? failureReason;
  final String? initiatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? processedAt;

  factory Refund.fromJson(Map<String, dynamic> json) {
    return Refund(
      id: json['id'] as String,
      facilityId: json['facility_id'] as String,
      paymentOrderId: json['payment_order_id'] as String,
      transactionId: json['transaction_id'] as String?,
      sourceType: PaymentSourceType.fromJson(json['source_type'] as String),
      sourceId: json['source_id'] as String?,
      razorpayPaymentId: json['razorpay_payment_id'] as String,
      razorpayRefundId: json['razorpay_refund_id'] as String?,
      amountMinor: (json['amount_minor'] as num).toInt(),
      currency: json['currency'] as String? ?? 'INR',
      reason: RefundReason.fromJson(json['reason'] as String),
      status: RefundStatus.fromJson(json['status'] as String),
      isOverride: json['is_override'] as bool? ?? false,
      overrideReason: json['override_reason'] as String?,
      policyPercentApplied: (json['policy_percent_applied'] as num?)?.toInt(),
      failureReason: json['failure_reason'] as String?,
      initiatedBy: json['initiated_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      processedAt: json['processed_at'] != null ? DateTime.parse(json['processed_at'] as String) : null,
    );
  }
}

/// Mirrors `settlement_exceptions.reason` (0021_payment_settlement.sql).
enum SettlementExceptionReason {
  bookingNoLongerAvailable,
  guestCapacityExhausted,
  membershipInvalid,
  businessValidationFailed,
  databaseSettlementFailure;

  static SettlementExceptionReason fromJson(String value) {
    switch (value) {
      case 'BOOKING_NO_LONGER_AVAILABLE':
        return SettlementExceptionReason.bookingNoLongerAvailable;
      case 'GUEST_CAPACITY_EXHAUSTED':
        return SettlementExceptionReason.guestCapacityExhausted;
      case 'MEMBERSHIP_INVALID':
        return SettlementExceptionReason.membershipInvalid;
      case 'BUSINESS_VALIDATION_FAILED':
        return SettlementExceptionReason.businessValidationFailed;
      case 'DATABASE_SETTLEMENT_FAILURE':
        return SettlementExceptionReason.databaseSettlementFailure;
      default:
        throw ArgumentError('Unknown SettlementExceptionReason: $value');
    }
  }
}

enum SettlementExceptionStatus {
  open,
  resolved;

  String toJson() => this == SettlementExceptionStatus.open ? 'OPEN' : 'RESOLVED';

  static SettlementExceptionStatus fromJson(String value) {
    return value == 'RESOLVED' ? SettlementExceptionStatus.resolved : SettlementExceptionStatus.open;
  }
}

/// A payment received but the underlying business operation (booking,
/// guest slot, membership) could not be confirmed — read via the
/// `list_settlement_exceptions` RPC, which returns raw
/// `settlement_exceptions` table rows (snake_case).
class SettlementException {
  const SettlementException({
    required this.id,
    required this.facilityId,
    required this.paymentOrderId,
    this.transactionId,
    required this.sourceType,
    this.sourceId,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
  });

  final String id;
  final String facilityId;
  final String paymentOrderId;
  final String? transactionId;
  final PaymentSourceType sourceType;
  final String? sourceId;
  final SettlementExceptionReason reason;
  final SettlementExceptionStatus status;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  factory SettlementException.fromJson(Map<String, dynamic> json) {
    return SettlementException(
      id: json['id'] as String,
      facilityId: json['facility_id'] as String,
      paymentOrderId: json['payment_order_id'] as String,
      transactionId: json['transaction_id'] as String?,
      sourceType: PaymentSourceType.fromJson(json['source_type'] as String),
      sourceId: json['source_id'] as String?,
      reason: SettlementExceptionReason.fromJson(json['reason'] as String),
      status: SettlementExceptionStatus.fromJson(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      resolvedAt: json['resolved_at'] != null ? DateTime.parse(json['resolved_at'] as String) : null,
    );
  }
}

/// A facility's configured (or default) cancellation policy — read via
/// `get_effective_cancellation_policy`, which always returns a row (a
/// facility that never configured one gets the documented default rather
/// than null). Written via `upsert_cancellation_policy`.
class CancellationPolicy {
  const CancellationPolicy({
    required this.facilityId,
    required this.fullRefundHours,
    required this.fullRefundPercent,
    required this.partialRefundHours,
    required this.partialRefundPercent,
  });

  final String facilityId;
  final int fullRefundHours;
  final int fullRefundPercent;
  final int partialRefundHours;
  final int partialRefundPercent;

  factory CancellationPolicy.fromJson(Map<String, dynamic> json) {
    return CancellationPolicy(
      facilityId: json['facility_id'] as String,
      fullRefundHours: (json['full_refund_hours'] as num).toInt(),
      fullRefundPercent: (json['full_refund_percent'] as num).toInt(),
      partialRefundHours: (json['partial_refund_hours'] as num).toInt(),
      partialRefundPercent: (json['partial_refund_percent'] as num).toInt(),
    );
  }
}

class UpsertCancellationPolicyInput {
  const UpsertCancellationPolicyInput({
    required this.facilityId,
    required this.fullRefundHours,
    required this.fullRefundPercent,
    required this.partialRefundHours,
    required this.partialRefundPercent,
  });

  final String facilityId;
  final int fullRefundHours;
  final int fullRefundPercent;
  final int partialRefundHours;
  final int partialRefundPercent;
}

/// What a cancellation/refund submission returns for the refund it created
/// (if any) — never the client's own claim about status, always the
/// server's. Read from the `cancel-booking` / `cancel-membership-slot` /
/// `cancel-membership` / `create-razorpay-refund` Edge Function responses.
class RefundSubmission {
  const RefundSubmission({required this.id, required this.status, this.razorpayRefundId});

  final String id;
  final RefundStatus status;
  final String? razorpayRefundId;

  /// The normal shape (`submitRequestedRefund`'s `SubmitRefundResult`) keys
  /// the id as `refundId`; the one no-Razorpay-configured fallback branch in
  /// cancel-booking/cancel-membership-slot/cancel-membership instead sends
  /// `{ id, status }` for the still-REQUESTED refund it couldn't submit.
  /// Accepting either key keeps this client correct against both shapes the
  /// server can actually send, mirroring the Edge Functions' real (if
  /// slightly inconsistent) response bodies rather than only the common case.
  factory RefundSubmission.fromJson(Map<String, dynamic> json) {
    return RefundSubmission(
      id: (json['refundId'] ?? json['id']) as String,
      status: RefundStatus.fromJson(json['status'] as String),
      razorpayRefundId: json['razorpayRefundId'] as String?,
    );
  }
}

class CancelBookingInput {
  const CancelBookingInput({required this.bookingId, this.reason, this.refundOverridePercent, this.overrideReason});

  final String bookingId;
  final String? reason;

  /// Owner override — replaces the policy-computed refund percent (0-100).
  final int? refundOverridePercent;
  final String? overrideReason;
}

class CancelMembershipSlotInput {
  /// membership_session_bookings.id
  const CancelMembershipSlotInput({required this.bookingId, this.reason, this.refundOverridePercent, this.overrideReason});

  final String bookingId;
  final String? reason;
  final int? refundOverridePercent;
  final String? overrideReason;
}

class CancelMembershipInput {
  const CancelMembershipInput({required this.membershipId, this.reason, this.refundAmountMinor, this.overrideReason});

  final String membershipId;
  final String? reason;

  /// Explicit owner-decided refund amount — omit for no refund (spec §14/§15).
  final int? refundAmountMinor;
  final String? overrideReason;
}

class InitiateRefundInput {
  /// Exactly one of [paymentOrderId] or [settlementExceptionId].
  const InitiateRefundInput({this.paymentOrderId, this.settlementExceptionId, this.amountMinor, this.reason, this.overrideReason});

  final String? paymentOrderId;
  final String? settlementExceptionId;

  /// Required with [paymentOrderId]; ignored for [settlementExceptionId]
  /// (always a full refund).
  final int? amountMinor;
  final RefundReason? reason;
  final String? overrideReason;
}