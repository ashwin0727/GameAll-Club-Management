"use client";

import { useState } from "react";
import { getPaymentService } from "@/services/payments";
import { openRazorpayCheckout, isCheckoutCancellation, isCheckoutFailure } from "@/features/payments/razorpay-checkout";
import type { CreatePaymentOrderInput, PaymentOrderStatus } from "@/features/payments/types";

/**
 * The five states the Payment Status panel shows — deliberately a much
 * smaller set than the full `PaymentOrderStatus` state machine.
 *
 * "settled" is the ONLY state that ever reads as success — it means the
 * server actually confirmed the booking / activated the membership
 * (payment_orders.status = COMPLETED), never just that Razorpay captured
 * the money. "exception" means the payment WAS captured but the business
 * operation could not be completed (e.g. the slot was cancelled in the
 * meantime) — the payment is safe and recorded, but the user's booking/
 * membership is NOT confirmed and needs facility follow-up. Every other
 * pre-settlement server status collapses to "pending" — the UI never
 * claims success before the server has actually settled (spec §"Critical
 * Principle" / §"Core Principle").
 */
export type CheckoutResult =
  | { status: "settled"; paymentOrderId: string }
  | { status: "pending"; paymentOrderId: string }
  | { status: "exception"; paymentOrderId: string }
  | { status: "failed"; paymentOrderId: string; message: string }
  | { status: "cancelled" };

/**
 * apply_payment_verification (0021_payment_settlement.sql) already settles
 * inline the instant a payment genuinely transitions to CAPTURED, so by the
 * time verify/reconcile return, status is normally already COMPLETED or
 * SETTLEMENT_EXCEPTION. The one gap: if that inline settlement attempt
 * itself hit a transient failure, the order is left at plain CAPTURED —
 * retryable via settle-payment directly (apply_payment_verification's own
 * rank-based guard means simply re-verifying/re-reconciling would no-op
 * without ever retrying settlement, since the payment status itself hasn't
 * changed). This gives every caller one extra, harmless retry attempt.
 */
async function settleIfStillCaptured(paymentOrderId: string, status: PaymentOrderStatus): Promise<PaymentOrderStatus> {
  if (status !== "CAPTURED") return status;
  try {
    const settled = await getPaymentService().settlePaymentOrder({ paymentOrderId });
    return settled.status;
  } catch {
    return status;
  }
}

function toCheckoutResult(paymentOrderId: string, serverStatus: PaymentOrderStatus): CheckoutResult {
  if (serverStatus === "COMPLETED") {
    return { status: "settled", paymentOrderId };
  }
  if (serverStatus === "SETTLEMENT_EXCEPTION") {
    return { status: "exception", paymentOrderId };
  }
  if (serverStatus === "FAILED") {
    return { status: "failed", paymentOrderId, message: "Your payment could not be completed." };
  }
  return { status: "pending", paymentOrderId };
}

/**
 * The one place that drives a full Razorpay Checkout attempt: create the
 * payment order (existing Phase 1/2 write path) → open Checkout → record
 * the raw client result → SERVER-side verification → server-side
 * settlement. The client's own "success" callback is only ever a hint —
 * `verify-razorpay-payment` (an independent signature check + a direct
 * Razorpay API call) decides whether the payment is captured, and the
 * server settles it (confirms the booking / activates the membership)
 * before this ever resolves as "settled". A captured payment whose
 * booking/membership could no longer be confirmed resolves as
 * "exception", never as a silent success.
 */
export function usePaymentCheckout() {
  const [isProcessing, setIsProcessing] = useState(false);

  async function startCheckout(
    input: CreatePaymentOrderInput,
    options: { description?: string; prefill?: { name?: string; contact?: string; email?: string } } = {},
  ): Promise<CheckoutResult> {
    setIsProcessing(true);
    try {
      const checkoutInfo = await getPaymentService().createPaymentOrder(input);
      try {
        const outcome = await openRazorpayCheckout(checkoutInfo, options);
        await getPaymentService().recordPaymentAttempt({
          paymentOrderId: checkoutInfo.paymentOrderId,
          status: "PAYMENT_ATTEMPTED",
          razorpayPaymentId: outcome.razorpayPaymentId,
          razorpaySignature: outcome.razorpaySignature,
        });

        try {
          const verified = await getPaymentService().verifyPaymentOrder({
            paymentOrderId: checkoutInfo.paymentOrderId,
            razorpayOrderId: checkoutInfo.razorpayOrderId,
            razorpayPaymentId: outcome.razorpayPaymentId,
            razorpaySignature: outcome.razorpaySignature,
          });
          const finalStatus = await settleIfStillCaptured(checkoutInfo.paymentOrderId, verified.status);
          return toCheckoutResult(checkoutInfo.paymentOrderId, finalStatus);
        } catch {
          // Verification itself failed to complete (network blip, gateway
          // hiccup) — NOT the same as a rejected verification. The payment
          // may still be genuinely fine; the webhook or a manual "Check
          // Again" (reconcile) will resolve it. Never tell the user it
          // failed when we simply don't know yet.
          return { status: "pending", paymentOrderId: checkoutInfo.paymentOrderId };
        }
      } catch (reason) {
        if (isCheckoutCancellation(reason)) {
          return { status: "cancelled" };
        }
        if (isCheckoutFailure(reason)) {
          await getPaymentService().recordPaymentAttempt({
            paymentOrderId: checkoutInfo.paymentOrderId,
            status: "FAILED",
            razorpayPaymentId: reason.razorpayPaymentId,
          });
          return { status: "failed", paymentOrderId: checkoutInfo.paymentOrderId, message: reason.description };
        }
        throw reason;
      }
    } finally {
      setIsProcessing(false);
    }
  }

  /** Manual recovery for a payment stuck "pending" — asks Razorpay directly rather than waiting for the webhook, then retries settlement if the payment turns out to already be captured. Not for polling; call on explicit user action ("Check Again"). */
  async function checkAgain(paymentOrderId: string): Promise<CheckoutResult> {
    setIsProcessing(true);
    try {
      const reconciled = await getPaymentService().reconcilePaymentOrder({ paymentOrderId });
      const finalStatus = await settleIfStillCaptured(paymentOrderId, reconciled.status);
      return toCheckoutResult(paymentOrderId, finalStatus);
    } catch {
      return { status: "pending", paymentOrderId };
    } finally {
      setIsProcessing(false);
    }
  }

  return { startCheckout, checkAgain, isProcessing };
}