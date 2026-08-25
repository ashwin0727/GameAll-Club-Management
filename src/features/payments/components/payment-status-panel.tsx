"use client";

import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import type { CheckoutResult } from "@/features/payments/use-payment-checkout";

export type PaymentStatusPanelState = "processing" | CheckoutResult;

/**
 * The one reusable payment-status presentation (spec §"Payment Status
 * Screen") — used inline inside every payment-triggering dialog instead of
 * each one inventing its own copy. Never claims success for anything short
 * of the server's own "captured" result; "pending" always offers a manual
 * recheck rather than implying the payment failed.
 */
export function PaymentStatusPanel({
  state,
  isCheckingAgain,
  onCheckAgain,
  onRetry,
}: {
  state: PaymentStatusPanelState | null;
  isCheckingAgain?: boolean;
  onCheckAgain?: () => void;
  onRetry?: () => void;
}) {
  if (!state || state === "processing") {
    if (state !== "processing") return null;
    return (
      <div className="rounded-md border border-border bg-secondary/40 p-3 text-sm">
        <p className="font-medium">Payment Processing</p>
        <p className="text-muted-foreground">We&apos;re confirming your payment. Please wait…</p>
      </div>
    );
  }

  if (state.status === "cancelled") {
    return null;
  }

  if (state.status === "captured") {
    return (
      <div className="rounded-md border border-border bg-secondary/40 p-3 text-sm">
        <Badge variant="success">Payment Successful</Badge>
        <p className="mt-2 text-muted-foreground">Your payment has been confirmed.</p>
      </div>
    );
  }

  if (state.status === "failed") {
    return (
      <div className="rounded-md border border-border bg-secondary/40 p-3 text-sm">
        <Badge variant="destructive">Payment Failed</Badge>
        <p className="mt-2 text-muted-foreground">Your payment could not be completed.</p>
        {onRetry && (
          <Button type="button" size="sm" variant="outline" className="mt-2" onClick={onRetry}>
            Try Again
          </Button>
        )}
      </div>
    );
  }

  // "pending" — signature/order checked out but Razorpay hasn't
  // conclusively reported authorized/captured yet, or verification itself
  // couldn't complete. Never presented as a failure.
  return (
    <div className="rounded-md border border-border bg-secondary/40 p-3 text-sm">
      <Badge variant="warning">Payment Status Pending</Badge>
      <p className="mt-2 text-muted-foreground">We&apos;re still confirming your payment. Please check again shortly.</p>
      {onCheckAgain && (
        <Button type="button" size="sm" variant="outline" className="mt-2" disabled={isCheckingAgain} onClick={onCheckAgain}>
          {isCheckingAgain ? "Checking…" : "Check Again"}
        </Button>
      )}
    </div>
  );
}