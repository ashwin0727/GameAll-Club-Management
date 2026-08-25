import type { PaymentOrderCheckoutInfo } from "@/features/payments/types";

const CHECKOUT_SCRIPT_SRC = "https://checkout.razorpay.com/v1/checkout.js";

declare global {
  interface Window {
    Razorpay?: new (options: RazorpayOptions) => RazorpayInstance;
  }
}

interface RazorpayInstance {
  open(): void;
  on(event: "payment.failed", handler: (response: RazorpayFailureResponse) => void): void;
}

interface RazorpaySuccessResponse {
  razorpay_payment_id: string;
  razorpay_order_id: string;
  razorpay_signature: string;
}

interface RazorpayFailureResponse {
  error: { code: string; description: string; metadata?: { payment_id?: string } };
}

interface RazorpayOptions {
  key: string;
  order_id: string;
  amount: number;
  currency: string;
  name: string;
  description?: string;
  prefill?: { name?: string; contact?: string; email?: string };
  handler: (response: RazorpaySuccessResponse) => void;
  modal?: { ondismiss?: () => void };
}

let scriptLoadPromise: Promise<void> | null = null;

/** Injects Razorpay's Checkout.js once and reuses the same promise on every subsequent call. */
function loadRazorpayScript(): Promise<void> {
  if (typeof window === "undefined") {
    return Promise.reject(new Error("Razorpay Checkout is only available in the browser."));
  }
  if (window.Razorpay) {
    return Promise.resolve();
  }
  scriptLoadPromise ??= new Promise<void>((resolve, reject) => {
    const script = document.createElement("script");
    script.src = CHECKOUT_SCRIPT_SRC;
    script.async = true;
    script.onload = () => resolve();
    script.onerror = () => {
      scriptLoadPromise = null;
      reject(new Error("Unable to load Razorpay Checkout. Check your connection and try again."));
    };
    document.body.appendChild(script);
  });
  return scriptLoadPromise;
}

export interface CheckoutOutcome {
  razorpayPaymentId: string;
  razorpaySignature: string;
}

export interface CheckoutFailure {
  razorpayPaymentId?: string;
  description: string;
}

/**
 * Opens Razorpay Checkout for an already-created payment order. Resolves
 * with the raw client-side result on success, rejects with
 * {@link CheckoutFailure} on a reported failure, or rejects with `null` if
 * the customer closed the modal without paying (a plain cancellation — not
 * an error, just nothing happened).
 */
export async function openRazorpayCheckout(
  checkoutInfo: PaymentOrderCheckoutInfo,
  options: { description?: string; prefill?: { name?: string; contact?: string; email?: string } } = {},
): Promise<CheckoutOutcome> {
  await loadRazorpayScript();
  if (!window.Razorpay) {
    throw new Error("Razorpay Checkout failed to initialize.");
  }

  return new Promise<CheckoutOutcome>((resolve, reject) => {
    let settled = false;
    const razorpay = new window.Razorpay!({
      key: checkoutInfo.keyId,
      order_id: checkoutInfo.razorpayOrderId,
      amount: checkoutInfo.amount,
      currency: checkoutInfo.currency,
      name: "GameAll",
      description: options.description,
      prefill: options.prefill,
      handler: (response) => {
        settled = true;
        resolve({ razorpayPaymentId: response.razorpay_payment_id, razorpaySignature: response.razorpay_signature });
      },
      modal: {
        ondismiss: () => {
          if (!settled) reject(null);
        },
      },
    });
    razorpay.on("payment.failed", (response) => {
      settled = true;
      reject({
        razorpayPaymentId: response.error.metadata?.payment_id,
        description: response.error.description,
      } satisfies CheckoutFailure);
    });
    razorpay.open();
  });
}

/** True when a rejection from {@link openRazorpayCheckout} was a plain user cancellation. */
export function isCheckoutCancellation(reason: unknown): boolean {
  return reason === null;
}

/** True when a rejection from {@link openRazorpayCheckout} was a reported Razorpay failure. */
export function isCheckoutFailure(reason: unknown): reason is CheckoutFailure {
  return typeof reason === "object" && reason !== null && "description" in reason;
}