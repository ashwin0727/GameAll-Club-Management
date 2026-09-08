// ═══════════════════════════════════════════════════════════════════════════
// Shared Razorpay verification logic — Phase 4.
//
// Used by verify-razorpay-payment (client-triggered), razorpay-webhook
// (Razorpay-triggered), and reconcile-razorpay-payment (staff-triggered
// manual recheck) so the three Edge Functions never duplicate signature
// verification, status mapping, or the forward-only state machine.
//
// Pure functions only — no Supabase client, no `Deno.env` reads — so this
// module can be unit tested (razorpay.test.ts) with plain `deno test`,
// without a live Supabase/Razorpay connection.
// ═══════════════════════════════════════════════════════════════════════════

export type PaymentOrderStatus =
  | "CREATED"
  | "ORDER_CREATED"
  | "PAYMENT_ATTEMPTED"
  | "PAYMENT_VERIFICATION_PENDING"
  | "PAYMENT_VERIFIED"
  | "AUTHORIZED"
  | "CAPTURED"
  | "COMPLETED"
  | "FAILED"
  | "CANCELLED"
  | "REFUND_REQUESTED"
  | "REFUNDED";

/** Forward-progression rank — mirrors apply_payment_verification's rank_map in 0019_payment_verification.sql exactly. Statuses absent here (FAILED/CANCELLED/REFUND*) are terminal and never advanced through this map. */
const STATUS_RANK: Partial<Record<PaymentOrderStatus, number>> = {
  CREATED: 0,
  ORDER_CREATED: 1,
  PAYMENT_ATTEMPTED: 2,
  PAYMENT_VERIFICATION_PENDING: 3,
  PAYMENT_VERIFIED: 4,
  AUTHORIZED: 5,
  CAPTURED: 6,
  COMPLETED: 7,
};

/**
 * Mirrors apply_payment_verification's forward-only, no-downgrade decision
 * (0019_payment_verification.sql) — given the order's current status and a
 * Razorpay-derived target, returns the status that should be written, or
 * `null` if this is a no-op (already at/past that state, or in a terminal
 * state this logic doesn't advance from). FAILED is handled the same way
 * the SQL function handles it: only reachable from a pre-authorization
 * state, never downgrading an already-authorized/captured order.
 */
export function nextPaymentOrderStatus(current: PaymentOrderStatus, target: "AUTHORIZED" | "CAPTURED" | "FAILED" | "PAYMENT_VERIFIED"): PaymentOrderStatus | null {
  if (target === "FAILED") {
    const preAuthStates: PaymentOrderStatus[] = ["CREATED", "ORDER_CREATED", "PAYMENT_ATTEMPTED", "PAYMENT_VERIFICATION_PENDING", "PAYMENT_VERIFIED"];
    return preAuthStates.includes(current) ? "FAILED" : null;
  }
  const currentRank = STATUS_RANK[current];
  const targetRank = STATUS_RANK[target];
  if (currentRank === undefined || targetRank === undefined) return null;
  return targetRank > currentRank ? target : null;
}

/** Razorpay's payment.status values that matter to this integration — see https://razorpay.com/docs/payments/payments/#payment-life-cycle. */
export type RazorpayPaymentStatus = "created" | "authorized" | "captured" | "failed" | "refunded";

/** Maps a Razorpay payment status to the GameAll-derived target passed into `nextPaymentOrderStatus` / the apply_payment_verification RPC. */
export function mapRazorpayPaymentStatus(status: string): "AUTHORIZED" | "CAPTURED" | "FAILED" | "PAYMENT_VERIFIED" {
  switch (status) {
    case "captured":
      return "CAPTURED";
    case "authorized":
      return "AUTHORIZED";
    case "failed":
      return "FAILED";
    default:
      // "created" or anything else Razorpay might add — signature/order
      // checked out, but not yet in a state we can call authorized/
      // captured/failed. Not a failure, just not conclusive yet.
      return "PAYMENT_VERIFIED";
  }
}

export interface RazorpayPayment {
  id: string;
  order_id: string;
  amount: number;
  currency: string;
  status: string;
}

function toHex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function hmacSha256Hex(message: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return toHex(signature);
}

/** Constant-time string comparison — avoids leaking signature-match progress via response timing. */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

/**
 * Verifies a Razorpay Checkout payment signature — HMAC-SHA256 of
 * `${razorpayOrderId}|${razorpayPaymentId}` keyed with the Razorpay Key
 * Secret. This is the ONLY correct algorithm for this signature (see
 * https://razorpay.com/docs/payments/server-integration/nodejs/payment-gateway/build-integration/#3-verify-payment-signature)
 * — never the webhook signature algorithm, which signs the raw body
 * instead.
 */
export async function verifyPaymentSignature(razorpayOrderId: string, razorpayPaymentId: string, signature: string, keySecret: string): Promise<boolean> {
  const expected = await hmacSha256Hex(`${razorpayOrderId}|${razorpayPaymentId}`, keySecret);
  return timingSafeEqual(expected, signature);
}

/**
 * Verifies a Razorpay webhook signature — HMAC-SHA256 of the exact raw
 * request body, keyed with the dedicated Razorpay Webhook Secret (never
 * the Key Secret). Callers MUST pass the untouched raw body text read
 * directly off the request — re-serializing parsed JSON changes
 * whitespace/key order and breaks the signature.
 */
export async function verifyWebhookSignature(rawBody: string, signature: string, webhookSecret: string): Promise<boolean> {
  const expected = await hmacSha256Hex(rawBody, webhookSecret);
  return timingSafeEqual(expected, signature);
}

/** Fetches a payment's authoritative state directly from Razorpay's API — never trusted from the client. */
export async function fetchRazorpayPayment(paymentId: string, keyId: string, keySecret: string): Promise<RazorpayPayment> {
  const response = await fetch(`https://api.razorpay.com/v1/payments/${paymentId}`, {
    headers: { Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}` },
  });
  if (!response.ok) {
    throw new Error(`Razorpay payment lookup failed with status ${response.status}`);
  }
  return response.json();
}

/**
 * Captures an authorized-but-not-yet-captured payment, so an order never
 * strands the customer's money in the AUTHORIZED state when the Razorpay
 * account is not set to auto-capture. `amountMinor`/`currency` MUST be the
 * payment's own authorized amount (from fetchRazorpayPayment), not GameAll's
 * order amount — Razorpay rejects a capture whose amount differs from what
 * was authorized. A payment Razorpay already captured (its 400
 * "payment already captured") is treated as success by re-fetching.
 */
export async function captureRazorpayPayment(
  paymentId: string,
  amountMinor: number,
  currency: string,
  keyId: string,
  keySecret: string,
): Promise<RazorpayPayment> {
  const response = await fetch(`https://api.razorpay.com/v1/payments/${paymentId}/capture`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ amount: amountMinor, currency }),
  });
  if (response.ok) {
    return response.json();
  }
  // Already captured (a webhook or a racing verify call beat us to it), or a
  // transient gateway issue — re-fetch and let the status speak for itself.
  const payment = await fetchRazorpayPayment(paymentId, keyId, keySecret);
  if (payment.status === "captured") {
    return payment;
  }
  throw new Error(`Razorpay capture failed with status ${response.status}`);
}

/** Fetches every payment attempt Razorpay has recorded for an order — used by reconcile-razorpay-payment when no specific payment id is known yet. */
export async function fetchRazorpayOrderPayments(razorpayOrderId: string, keyId: string, keySecret: string): Promise<RazorpayPayment[]> {
  const response = await fetch(`https://api.razorpay.com/v1/orders/${razorpayOrderId}/payments`, {
    headers: { Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}` },
  });
  if (!response.ok) {
    throw new Error(`Razorpay order-payments lookup failed with status ${response.status}`);
  }
  const body = await response.json();
  return (body.items ?? []) as RazorpayPayment[];
}

/** Picks the most decisive payment attempt to reconcile against: captured beats authorized beats failed, and ties break to the most recently returned (Razorpay already orders these newest-first). */
export function pickMostDecisivePayment(payments: RazorpayPayment[]): RazorpayPayment | null {
  const byPriority = (status: string) => (status === "captured" ? 0 : status === "authorized" ? 1 : status === "failed" ? 2 : 3);
  if (payments.length === 0) return null;
  return [...payments].sort((a, b) => byPriority(a.status) - byPriority(b.status))[0];
}

// ═══════════════════════════════════════════════════════════════════════════
// Refunds — Phase 6. Shared by every Edge Function that submits a refund to
// Razorpay (create-razorpay-refund, cancel-booking, cancel-membership-slot,
// cancel-membership) so the API call/idempotency shape lives in one place.
// ═══════════════════════════════════════════════════════════════════════════

export interface RazorpayRefund {
  id: string;
  payment_id: string;
  amount: number;
  currency: string;
  status: string; // "created" (queued) | "processed" | "failed" — see https://razorpay.com/docs/payments/refunds/
}

/**
 * Submits a refund to Razorpay for an already-captured payment. Amount MUST
 * be in the smallest currency unit (paise), matching every other amount in
 * this integration (spec §18). `notes.gameall_refund_id` is what
 * apply_refund_webhook's fallback lookup (by razorpay_payment_id) exists
 * for if a webhook ever arrives before this call's response does — the
 * primary link is still the returned razorpay_refund_id, stored immediately
 * after this resolves.
 */
export async function createRazorpayRefund(paymentId: string, amountMinor: number, keyId: string, keySecret: string, reference: string): Promise<RazorpayRefund> {
  const response = await fetch(`https://api.razorpay.com/v1/payments/${paymentId}/refund`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ amount: amountMinor, speed: "normal", notes: { reference } }),
  });
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Razorpay refund request failed with status ${response.status}: ${body}`);
  }
  return response.json();
}

/** Maps a razorpay-webhook `refund.*` event type to apply_refund_webhook's `p_status` argument. */
export function mapRefundEventToStatus(eventType: string): "created" | "processed" | "failed" | null {
  switch (eventType) {
    case "refund.created":
      return "created";
    case "refund.processed":
      return "processed";
    case "refund.failed":
      return "failed";
    default:
      return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Subscriptions — Phase 2 (recurring UPI AutoPay). Shared by razorpay-webhook
// so the subscription.* event → membership_subscription_status mapping lives
// in one place and is unit-testable.
// ═══════════════════════════════════════════════════════════════════════════

export type MembershipSubscriptionStatus =
  | "created"
  | "authenticated"
  | "active"
  | "pending"
  | "halted"
  | "cancelled"
  | "completed";

export interface RazorpaySubscription {
  id: string;
  status: string;
  paid_count?: number;
  current_start?: number | null;
  current_end?: number | null;
}

/** Maps a `subscription.*` webhook event type to the apply_subscription_webhook status, or null for events we don't act on. */
export function mapSubscriptionEventToStatus(eventType: string): MembershipSubscriptionStatus | null {
  switch (eventType) {
    case "subscription.authenticated":
      return "authenticated";
    case "subscription.activated":
    case "subscription.charged":
    case "subscription.resumed":
      return "active";
    case "subscription.pending":
      return "pending";
    case "subscription.halted":
      return "halted";
    case "subscription.cancelled":
      return "cancelled";
    case "subscription.completed":
      return "completed";
    default:
      return null;
  }
}

/** Unix seconds → "YYYY-MM-DD" (UTC), or null. */
export function unixToDateString(seconds: number | null | undefined): string | null {
  if (!seconds) return null;
  return new Date(seconds * 1000).toISOString().slice(0, 10);
}