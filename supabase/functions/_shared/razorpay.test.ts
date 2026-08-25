import { assertEquals } from "jsr:@std/assert@1";
import {
  fetchRazorpayOrderPayments,
  fetchRazorpayPayment,
  mapRazorpayPaymentStatus,
  nextPaymentOrderStatus,
  pickMostDecisivePayment,
  verifyPaymentSignature,
  verifyWebhookSignature,
} from "./razorpay.ts";

// ── Signature verification ──────────────────────────────────────────────

Deno.test("verifyPaymentSignature accepts a correctly computed HMAC-SHA256 signature", async () => {
  const secret = "test_secret";
  // Precomputed: HMAC-SHA256("order_abc|pay_xyz", "test_secret")
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sigBytes = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode("order_abc|pay_xyz"));
  const signature = Array.from(new Uint8Array(sigBytes)).map((b) => b.toString(16).padStart(2, "0")).join("");

  assertEquals(await verifyPaymentSignature("order_abc", "pay_xyz", signature, secret), true);
});

Deno.test("verifyPaymentSignature rejects an invalid/tampered signature", async () => {
  assertEquals(await verifyPaymentSignature("order_abc", "pay_xyz", "deadbeef", "test_secret"), false);
});

Deno.test("verifyPaymentSignature rejects a signature computed for a different order/payment pair", async () => {
  const secret = "test_secret";
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sigBytes = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode("order_ANOTHER|pay_xyz"));
  const signature = Array.from(new Uint8Array(sigBytes)).map((b) => b.toString(16).padStart(2, "0")).join("");

  assertEquals(await verifyPaymentSignature("order_abc", "pay_xyz", signature, secret), false);
});

Deno.test("verifyWebhookSignature verifies against the raw body, not a re-serialized one", async () => {
  const secret = "webhook_secret";
  const rawBody = '{"event":"payment.captured","payload":{}}';
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sigBytes = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(rawBody));
  const signature = Array.from(new Uint8Array(sigBytes)).map((b) => b.toString(16).padStart(2, "0")).join("");

  assertEquals(await verifyWebhookSignature(rawBody, signature, secret), true);
  // Same JSON content, different whitespace — must NOT verify, proving the
  // raw body (not a parsed-then-reserialized version) is what's hashed.
  const reserialized = JSON.stringify(JSON.parse(rawBody));
  assertEquals(await verifyWebhookSignature(reserialized, signature, secret), reserialized === rawBody);
});

Deno.test("verifyWebhookSignature rejects an invalid signature", async () => {
  assertEquals(await verifyWebhookSignature('{"event":"payment.captured"}', "not-the-right-signature", "webhook_secret"), false);
});

// ── Status mapping ──────────────────────────────────────────────────────

Deno.test("mapRazorpayPaymentStatus maps captured/authorized/failed exactly, everything else to PAYMENT_VERIFIED", () => {
  assertEquals(mapRazorpayPaymentStatus("captured"), "CAPTURED");
  assertEquals(mapRazorpayPaymentStatus("authorized"), "AUTHORIZED");
  assertEquals(mapRazorpayPaymentStatus("failed"), "FAILED");
  assertEquals(mapRazorpayPaymentStatus("created"), "PAYMENT_VERIFIED");
  assertEquals(mapRazorpayPaymentStatus("refunded"), "PAYMENT_VERIFIED");
});

// ── State machine (mirrors apply_payment_verification) ─────────────────

Deno.test("nextPaymentOrderStatus advances forward along the normal happy path", () => {
  assertEquals(nextPaymentOrderStatus("PAYMENT_ATTEMPTED", "PAYMENT_VERIFIED"), "PAYMENT_VERIFIED");
  assertEquals(nextPaymentOrderStatus("PAYMENT_VERIFIED", "AUTHORIZED"), "AUTHORIZED");
  assertEquals(nextPaymentOrderStatus("AUTHORIZED", "CAPTURED"), "CAPTURED");
  assertEquals(nextPaymentOrderStatus("PAYMENT_ATTEMPTED", "CAPTURED"), "CAPTURED");
});

Deno.test("nextPaymentOrderStatus never downgrades CAPTURED — duplicate/out-of-order events are no-ops", () => {
  assertEquals(nextPaymentOrderStatus("CAPTURED", "AUTHORIZED"), null);
  assertEquals(nextPaymentOrderStatus("CAPTURED", "PAYMENT_VERIFIED"), null);
  assertEquals(nextPaymentOrderStatus("CAPTURED", "CAPTURED"), null);
});

Deno.test("nextPaymentOrderStatus treats a repeat of the same status as a no-op (duplicate webhook / duplicate verification)", () => {
  assertEquals(nextPaymentOrderStatus("AUTHORIZED", "AUTHORIZED"), null);
});

Deno.test("nextPaymentOrderStatus allows FAILED only before authorization, never after", () => {
  assertEquals(nextPaymentOrderStatus("PAYMENT_ATTEMPTED", "FAILED"), "FAILED");
  assertEquals(nextPaymentOrderStatus("PAYMENT_VERIFIED", "FAILED"), "FAILED");
  assertEquals(nextPaymentOrderStatus("AUTHORIZED", "FAILED"), null);
  assertEquals(nextPaymentOrderStatus("CAPTURED", "FAILED"), null);
});

Deno.test("nextPaymentOrderStatus is a no-op from an already-terminal FAILED state", () => {
  assertEquals(nextPaymentOrderStatus("FAILED", "CAPTURED"), null);
  assertEquals(nextPaymentOrderStatus("FAILED", "FAILED"), null);
});

// ── Razorpay HTTP calls (mocked fetch — §"No Mock Persistence" only bars mocking in the real app, not in tests) ──

Deno.test("fetchRazorpayPayment returns the parsed payment on a 200", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (() => Promise.resolve(new Response(JSON.stringify({ id: "pay_1", order_id: "order_1", amount: 80000, currency: "INR", status: "captured" }), { status: 200 }))) as typeof fetch;
  try {
    const payment = await fetchRazorpayPayment("pay_1", "key_id", "key_secret");
    assertEquals(payment.status, "captured");
    assertEquals(payment.amount, 80000);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("fetchRazorpayPayment throws on a non-2xx response instead of returning a falsy/empty result", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (() => Promise.resolve(new Response("not found", { status: 404 }))) as typeof fetch;
  try {
    let threw = false;
    try {
      await fetchRazorpayPayment("pay_missing", "key_id", "key_secret");
    } catch {
      threw = true;
    }
    assertEquals(threw, true);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("fetchRazorpayOrderPayments returns the items array", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (() =>
    Promise.resolve(
      new Response(JSON.stringify({ items: [{ id: "pay_1", order_id: "order_1", amount: 80000, currency: "INR", status: "captured" }] }), { status: 200 }),
    )) as typeof fetch;
  try {
    const payments = await fetchRazorpayOrderPayments("order_1", "key_id", "key_secret");
    assertEquals(payments.length, 1);
    assertEquals(payments[0].id, "pay_1");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("pickMostDecisivePayment prefers captured over authorized over failed", () => {
  const authorized = { id: "pay_a", order_id: "o", amount: 1, currency: "INR", status: "authorized" };
  const captured = { id: "pay_c", order_id: "o", amount: 1, currency: "INR", status: "captured" };
  const failed = { id: "pay_f", order_id: "o", amount: 1, currency: "INR", status: "failed" };

  assertEquals(pickMostDecisivePayment([authorized, failed, captured])?.id, "pay_c");
  assertEquals(pickMostDecisivePayment([authorized, failed])?.id, "pay_a");
  assertEquals(pickMostDecisivePayment([failed])?.id, "pay_f");
  assertEquals(pickMostDecisivePayment([]), null);
});