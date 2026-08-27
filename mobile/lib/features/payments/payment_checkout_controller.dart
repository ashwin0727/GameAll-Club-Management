import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../data/models/payment.dart';
import '../../data/repositories/payment_repository.dart';
import '../../data/repositories/repository_providers.dart';

/// The five states the Payment Status panel shows — mirrors
/// src/features/payments/use-payment-checkout.ts's `CheckoutResult`
/// deliberately as a much smaller set than the full [PaymentOrderStatus]
/// state machine.
///
/// [CheckoutSettled] is the ONLY state that ever reads as success — it means
/// the server actually confirmed the booking / activated the membership
/// (payment_orders.status == COMPLETED), never just that Razorpay captured
/// the money. [CheckoutException] means the payment WAS captured but the
/// business operation could not be completed (e.g. the slot was cancelled in
/// the meantime) — the payment is safe and recorded, but the user's
/// booking/membership is NOT confirmed and needs facility follow-up. Every
/// other pre-settlement server status collapses to [CheckoutPending] — the UI
/// never claims success before the server has actually settled (spec
/// §"Critical Principle" / §"Core Principle").
sealed class CheckoutResult {
  const CheckoutResult();
}

class CheckoutSettled extends CheckoutResult {
  const CheckoutSettled(this.paymentOrderId);
  final String paymentOrderId;
}

class CheckoutPending extends CheckoutResult {
  const CheckoutPending(this.paymentOrderId);
  final String paymentOrderId;
}

class CheckoutException extends CheckoutResult {
  const CheckoutException(this.paymentOrderId);
  final String paymentOrderId;
}

class CheckoutFailed extends CheckoutResult {
  const CheckoutFailed(this.paymentOrderId, this.message);
  final String paymentOrderId;
  final String message;
}

class CheckoutCancelled extends CheckoutResult {
  const CheckoutCancelled();
}

/// apply_payment_verification (0021_payment_settlement.sql) already settles
/// inline the instant a payment genuinely transitions to CAPTURED, so by the
/// time verify/reconcile return, status is normally already COMPLETED or
/// SETTLEMENT_EXCEPTION. The one gap: if that inline settlement attempt
/// itself hit a transient failure, the order is left at plain CAPTURED —
/// retryable via settle-payment directly (apply_payment_verification's own
/// rank-based guard means simply re-verifying/re-reconciling would no-op
/// without ever retrying settlement, since the payment status itself hasn't
/// changed). This gives every caller one extra, harmless retry attempt.
Future<PaymentOrderStatus> _settleIfStillCaptured(
  PaymentRepository repository,
  String paymentOrderId,
  PaymentOrderStatus status,
) async {
  if (status != PaymentOrderStatus.captured) return status;
  try {
    final settled = await repository.settlePaymentOrder(SettlePaymentInput(paymentOrderId: paymentOrderId));
    return settled.status;
  } catch (_) {
    return status;
  }
}

CheckoutResult _toCheckoutResult(String paymentOrderId, PaymentOrderStatus serverStatus) {
  if (serverStatus == PaymentOrderStatus.completed) {
    return CheckoutSettled(paymentOrderId);
  }
  if (serverStatus == PaymentOrderStatus.settlementException) {
    return CheckoutException(paymentOrderId);
  }
  if (serverStatus == PaymentOrderStatus.failed) {
    return CheckoutFailed(paymentOrderId, 'Your payment could not be completed.');
  }
  return CheckoutPending(paymentOrderId);
}

/// The one place that drives a full Razorpay Checkout attempt: create the
/// payment order (existing Phase 1/2 write path) → open Checkout → record
/// the raw client result → SERVER-side verification → server-side
/// settlement. Mirrors src/features/payments/use-payment-checkout.ts
/// exactly. The client's own "success" callback is only ever a hint —
/// `verify-razorpay-payment` (an independent signature check + a direct
/// Razorpay API call) decides whether the payment is captured, and the
/// server settles it (confirms the booking / activates the membership)
/// before this ever resolves as [CheckoutSettled]. A captured payment whose
/// booking/membership could no longer be confirmed resolves as
/// [CheckoutException], never as a silent success.
class PaymentCheckoutController {
  PaymentCheckoutController(this._repository);

  final PaymentRepository _repository;

  Future<CheckoutResult> startCheckout(
    CreatePaymentOrderInput input, {
    String? contactName,
    String? contactPhone,
  }) async {
    final checkoutInfo = await _repository.createPaymentOrder(input);
    final completer = Completer<CheckoutResult>();
    final razorpay = Razorpay();

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) async {
      await _repository.recordPaymentAttempt(
        paymentOrderId: checkoutInfo.paymentOrderId,
        status: PaymentAttemptStatus.paymentAttempted,
        razorpayPaymentId: response.paymentId,
        razorpaySignature: response.signature,
      );

      try {
        final verified = await _repository.verifyPaymentOrder(
          VerifyPaymentInput(
            paymentOrderId: checkoutInfo.paymentOrderId,
            razorpayOrderId: checkoutInfo.razorpayOrderId,
            razorpayPaymentId: response.paymentId ?? '',
            razorpaySignature: response.signature ?? '',
          ),
        );
        final finalStatus = await _settleIfStillCaptured(_repository, checkoutInfo.paymentOrderId, verified.status);
        if (!completer.isCompleted) {
          completer.complete(_toCheckoutResult(checkoutInfo.paymentOrderId, finalStatus));
        }
      } catch (_) {
        // Verification itself failed to complete (network blip, gateway
        // hiccup) — NOT the same as a rejected verification. The payment may
        // still be genuinely fine; the webhook or a manual "Check Again"
        // (reconcile) will resolve it. Never tell the user it failed when we
        // simply don't know yet.
        if (!completer.isCompleted) {
          completer.complete(CheckoutPending(checkoutInfo.paymentOrderId));
        }
      }
    });

    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) async {
      // Razorpay Flutter reports a user-cancelled checkout (back button /
      // swipe-away) as an error with code 2 — treat it as a plain
      // cancellation, matching the web Checkout.js `ondismiss` behavior:
      // no DB write, the order stays retryable.
      if (response.code == Razorpay.PAYMENT_CANCELLED) {
        if (!completer.isCompleted) completer.complete(const CheckoutCancelled());
        return;
      }
      await _repository.recordPaymentAttempt(
        paymentOrderId: checkoutInfo.paymentOrderId,
        status: PaymentAttemptStatus.failed,
      );
      if (!completer.isCompleted) {
        completer.complete(CheckoutFailed(checkoutInfo.paymentOrderId, response.message ?? 'Payment failed.'));
      }
    });

    razorpay.open({
      'key': checkoutInfo.keyId,
      'order_id': checkoutInfo.razorpayOrderId,
      'amount': checkoutInfo.amount,
      'currency': checkoutInfo.currency,
      'name': 'GameAll',
      if (contactName != null || contactPhone != null)
        'prefill': {
          'name': ?contactName,
          'contact': ?contactPhone,
        },
    });

    try {
      return await completer.future;
    } finally {
      razorpay.clear();
    }
  }

  /// Manual recovery for a payment stuck "pending" — asks Razorpay directly
  /// rather than waiting for the webhook, then retries settlement if the
  /// payment turns out to already be captured. Not for polling; call on
  /// explicit user action ("Check Again").
  Future<CheckoutResult> checkAgain(String paymentOrderId) async {
    try {
      final reconciled = await _repository.reconcilePaymentOrder(ReconcilePaymentInput(paymentOrderId: paymentOrderId));
      final finalStatus = await _settleIfStillCaptured(_repository, paymentOrderId, reconciled.status);
      return _toCheckoutResult(paymentOrderId, finalStatus);
    } catch (_) {
      return CheckoutPending(paymentOrderId);
    }
  }
}

final paymentCheckoutControllerProvider = Provider<PaymentCheckoutController>((ref) {
  return PaymentCheckoutController(ref.watch(paymentRepositoryProvider));
});