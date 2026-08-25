import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/app_exception.dart';
import '../models/payment.dart';

/// Razorpay Payment Foundation — Phase 1 + Phase 2 port. Mirrors
/// src/services/payments/supabase-payment.service.ts exactly: the single
/// write path for starting a payment (membership purchase, member booking,
/// or guest booking) is the `create-razorpay-order` Edge Function — the
/// only place the Razorpay secret exists. It validates the request
/// server-side via the `create_payment_order` RPC and computes the
/// authoritative amount itself; this client never sends an amount. See
/// supabase/migrations/0016_payment_orders.sql and
/// supabase/functions/create-razorpay-order/index.ts for the authoritative
/// backend contract.
///
/// Creating an order does NOT mean the payment succeeded, the booking is
/// confirmed, or the membership is active — those all wait for a later
/// phase's payment verification. This class deliberately stops at handing
/// back [PaymentOrderCheckoutInfo]; it never opens a checkout UI.
class PaymentRepository {
  PaymentRepository(this._client);

  final SupabaseClient _client;

  Future<PaymentOrderCheckoutInfo> createPaymentOrder(CreatePaymentOrderInput input) async {
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'create-razorpay-order',
        body: {
          'facilityId': input.facilityId,
          'sourceType': input.sourceType.toJson(),
          'bookingId': input.bookingId,
          'membershipSessionBookingId': input.membershipSessionBookingId,
          'memberId': input.memberId,
          'planId': input.planId,
        },
      );
    } on FunctionsHttpException catch (e) {
      // The Edge Function itself responded (400/500/502) with a JSON
      // `{ error: string }` body — a specific, already-polished business-rule
      // or gateway message. Surfaced verbatim, mirroring the web service's
      // PAYMENT_ORDER_ERROR handling.
      final details = e.details;
      if (details is Map && details['error'] is String) {
        throw AppException(AppErrorCode.paymentOrderError, details['error'] as String);
      }
      throw AppException(AppErrorCode.paymentGatewayError);
    } on FunctionException {
      // FunctionsRelayException (Supabase relay failed before reaching the
      // function) or FunctionsFetchException (request never sent, e.g. no
      // network) — nothing specific to surface, map to a generic gateway
      // error rather than leaking the raw error.
      throw AppException(AppErrorCode.paymentGatewayError);
    }

    return PaymentOrderCheckoutInfo.fromJson((response.data as Map).cast<String, dynamic>());
  }

  /// Records the raw, unverified result the Razorpay Flutter SDK hands back
  /// after a payment attempt (success or failure) — never a user
  /// cancellation, which leaves the order retryable. Does not verify a
  /// signature, does not confirm a booking, and does not activate a
  /// membership; that is a later phase's job.
  Future<void> recordPaymentAttempt({
    required String paymentOrderId,
    required PaymentAttemptStatus status,
    String? razorpayPaymentId,
    String? razorpaySignature,
  }) async {
    try {
      await _client.rpc(
        'record_payment_attempt',
        params: {
          'p_payment_order_id': paymentOrderId,
          'p_status': status.toJson(),
          'p_razorpay_payment_id': razorpayPaymentId,
          'p_razorpay_signature': razorpaySignature,
        },
      );
    } on PostgrestException catch (e) {
      throw AppException(AppErrorCode.paymentOrderError, e.message);
    }
  }

  /// Server-side authority for "did this payment actually succeed?" — calls
  /// `verify-razorpay-payment`, which independently re-checks the signature
  /// and Razorpay's own payment status/amount/currency before advancing
  /// `payment_orders.status`. The client's own success callback is never
  /// trusted on its own; this is what turns it into a verified result.
  Future<PaymentVerificationResult> verifyPaymentOrder(VerifyPaymentInput input) async {
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'verify-razorpay-payment',
        body: {
          'paymentOrderId': input.paymentOrderId,
          'razorpayOrderId': input.razorpayOrderId,
          'razorpayPaymentId': input.razorpayPaymentId,
          'razorpaySignature': input.razorpaySignature,
        },
      );
    } on FunctionsHttpException catch (e) {
      final details = e.details;
      if (details is Map && details['error'] is String) {
        throw AppException(AppErrorCode.paymentOrderError, details['error'] as String);
      }
      throw AppException(AppErrorCode.paymentGatewayError);
    } on FunctionException {
      throw AppException(AppErrorCode.paymentGatewayError);
    }

    return PaymentVerificationResult.fromJson((response.data as Map).cast<String, dynamic>());
  }

  /// On-demand recovery for a payment order stuck pending (lost client
  /// callback, webhook not yet arrived) — asks Razorpay directly via
  /// `reconcile-razorpay-payment`. Not for polling; call it when the user
  /// explicitly asks to check again.
  Future<PaymentVerificationResult> reconcilePaymentOrder(ReconcilePaymentInput input) async {
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'reconcile-razorpay-payment',
        body: {'paymentOrderId': input.paymentOrderId},
      );
    } on FunctionsHttpException catch (e) {
      final details = e.details;
      if (details is Map && details['error'] is String) {
        throw AppException(AppErrorCode.paymentOrderError, details['error'] as String);
      }
      throw AppException(AppErrorCode.paymentGatewayError);
    } on FunctionException {
      throw AppException(AppErrorCode.paymentGatewayError);
    }

    return PaymentVerificationResult.fromJson((response.data as Map).cast<String, dynamic>());
  }

  /// Reads the current authoritative status for a payment order (RLS-scoped)
  /// — what payment status UI should poll/display, never Razorpay directly.
  /// Mirrors the existing `get_payment_order` RPC (already used server-side
  /// since Phase 1); no new privileged read path.
  Future<PaymentVerificationResult> getPaymentOrderStatus(String paymentOrderId) async {
    final dynamic data;
    try {
      data = await _client.rpc('get_payment_order', params: {'p_payment_order_id': paymentOrderId});
    } on PostgrestException catch (e) {
      throw AppException(AppErrorCode.paymentOrderError, e.message);
    }
    if (data == null) {
      throw AppException(AppErrorCode.paymentOrderError);
    }
    final row = (data as Map).cast<String, dynamic>();
    return PaymentVerificationResult(
      paymentOrderId: row['id'] as String,
      status: PaymentOrderStatus.fromJson(row['status'] as String),
    );
  }
}