"use client";

import { useState } from "react";
import { getPaymentService } from "@/services/payments";
import { openRazorpayCheckout, isCheckoutCancellation, isCheckoutFailure } from "@/features/payments/razorpay-checkout";
import type { CreatePaymentOrderInput, PaymentOrderStatus } from "@/features/payments/types";

/**
 * The four states the Payment Status panel shows — deliberately a much
 * smaller set than the full `PaymentOrderStatus` state machine. "captured"
 * is the only state that ever reads as success to the user; every
 * pre-capture server status (PAYMENT_VERIFIED/AUTHORIZED/etc.) collapses to
 * "pending" — the UI never claims success before the server has actually
 * confirmed CAPTURED (spec §"Critical Principle").
 */
export type CheckoutResult =
  | { status: "captured"; paymentOrderId: string }
  | { status: "pending"; paymentOrderId: string }
  | { status: "failed"; paymentOrderId: string; message: string }
  | { status: "cancelled" };

function toCheckoutResult(paymentOrderId: string, serverStatus: PaymentOrderStatus): CheckoutResult {
  if (serverStatus === "CAPTURED" || serverStatus === "COMPLETED") {
    return { status: "captured", paymentOrderId };
  }
  if (serverStatus === "FAILED") {
    return { status: "failed", paymentOrderId, message: "Your payment could not be completed." };
  }
  return { status: "pending", paymentOrderId };
}

/**
 * The one place that drives a full Razorpay Checkout attempt: create the
 * payment order (existing Phase 1/2 write path) → open Checkout → record
 * the raw client result → SERVER-side verification. The client's own
 * "success" callback is only ever a hint — `verify-razorpay-payment` (an
 * independent signature check + a direct Razorpay API call) is what
 * actually decides whether this resolves as "captured". Never confirms a
 * booking or activates a membership — callers decide what, if anything, to
 * do with a "captured" result; that business settlement is a later phase.
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
          return toCheckoutResult(checkoutInfo.paymentOrderId, verified.status);
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

  /** Manual recovery for a payment stuck "pending" — asks Razorpay directly rather than waiting for the webhook. Not for polling; call on explicit user action ("Check Again"). */
  async function checkAgain(paymentOrderId: string): Promise<CheckoutResult> {
    setIsProcessing(true);
    try {
      const result = await getPaymentService().reconcilePaymentOrder({ paymentOrderId });
      return toCheckoutResult(paymentOrderId, result.status);
    } catch {
      return { status: "pending", paymentOrderId };
    } finally {
      setIsProcessing(false);
    }
  }

  return { startCheckout, checkAgain, isProcessing };
}