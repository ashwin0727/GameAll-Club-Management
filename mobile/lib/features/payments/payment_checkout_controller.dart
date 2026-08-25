import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../data/models/payment.dart';
import '../../data/repositories/payment_repository.dart';
import '../../data/repositories/repository_providers.dart';

/// The four states the Payment Status panel shows — mirrors
/// src/features/payments/use-payment-checkout.ts's `CheckoutResult`
/// deliberately as a much smaller set than the full [PaymentOrderStatus]
/// state machine. `CheckoutCaptured` is the only state that ever reads as
/// success to the user; every pre-capture server status
/// (PAYMENT_VERIFIED/AUTHORIZED/etc.) collapses to `CheckoutPending` — the UI
/// never claims success before the server has actually confirmed CAPTURED
/// (spec §"Critical Principle").
sealed class CheckoutResult {
  const CheckoutResult();
}

class CheckoutCaptured extends CheckoutResult {
  const CheckoutCaptured(this.paymentOrderId);
  final String paymentOrderId;
}

class CheckoutPending extends CheckoutResult {
  const CheckoutPending(this.paymentOrderId);
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

CheckoutResult _toCheckoutResult(String paymentOrderId, PaymentOrderStatus serverStatus) {
  if (serverStatus == PaymentOrderStatus.captured || serverStatus == PaymentOrderStatus.completed) {
    return CheckoutCaptured(paymentOrderId);
  }
  if (serverStatus == PaymentOrderStatus.failed) {
    return CheckoutFailed(paymentOrderId, 'Your payment could not be completed.');
  }
  return CheckoutPending(paymentOrderId);
}

/// The one place that drives a full Razorpay Checkout attempt: create the
/// payment order (existing Phase 1/2 write path) → open Checkout → record
/// the raw client result → SERVER-side verification. Mirrors
/// src/features/payments/use-payment-checkout.ts exactly. The client's own
/// "success" callback is only ever a hint — `verify-razorpay-payment` (an
/// independent signature check + a direct Razorpay API call) is what
/// actually decides whether this resolves as [CheckoutCaptured]. Never
/// confirms a booking or activates a membership — callers decide what, if
/// anything, to do with a captured result; that business settlement is a
/// later phase.
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
        if (!completer.isCompleted) {
          completer.complete(_toCheckoutResult(checkoutInfo.paymentOrderId, verified.status));
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
          if (contactName != null) 'name': contactName,
          if (contactPhone != null) 'contact': contactPhone,
        },
    });

    try {
      return await completer.future;
    } finally {
      razorpay.clear();
    }
  }

  /// Manual recovery for a payment stuck "pending" — asks Razorpay directly
  /// rather than waiting for the webhook. Not for polling; call on explicit
  /// user action ("Check Again").
  Future<CheckoutResult> checkAgain(String paymentOrderId) async {
    try {
      final result = await _repository.reconcilePaymentOrder(ReconcilePaymentInput(paymentOrderId: paymentOrderId));
      return _toCheckoutResult(paymentOrderId, result.status);
    } catch (_) {
      return CheckoutPending(paymentOrderId);
    }
  }
}

final paymentCheckoutControllerProvider = Provider<PaymentCheckoutController>((ref) {
  return PaymentCheckoutController(ref.watch(paymentRepositoryProvider));
});