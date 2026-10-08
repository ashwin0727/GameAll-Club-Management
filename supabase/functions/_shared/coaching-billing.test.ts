import { assertEquals } from "jsr:@std/assert@1";
import {
  cycleAmountMinor,
  extractLinkPayment,
  razorpaySubscriptionStatusToCoaching,
  mapPaymentLinkEventToStatus,
  subscriptionStatusToCoaching,
  toRazorpayContact,
} from "./coaching-billing.ts";

Deno.test("subscriptionStatusToCoaching upper-cases the membership status vocabulary", () => {
  assertEquals(subscriptionStatusToCoaching("active"), "ACTIVE");
  assertEquals(subscriptionStatusToCoaching("halted"), "HALTED");
  assertEquals(subscriptionStatusToCoaching("completed"), "COMPLETED");
});

Deno.test("mapPaymentLinkEventToStatus maps the three link events and ignores the rest", () => {
  assertEquals(mapPaymentLinkEventToStatus("payment_link.paid"), "PAID");
  assertEquals(mapPaymentLinkEventToStatus("payment_link.cancelled"), "CANCELLED");
  assertEquals(mapPaymentLinkEventToStatus("payment_link.expired"), "EXPIRED");
  assertEquals(mapPaymentLinkEventToStatus("payment.captured"), null);
});

Deno.test("cycleAmountMinor divides evenly or refuses", () => {
  assertEquals(cycleAmountMinor(120000, 3), 40000);
  assertEquals(cycleAmountMinor(40000, 1), 40000);
  assertEquals(cycleAmountMinor(100000, 3), null); // remainder → cycle counts disagree
  assertEquals(cycleAmountMinor(0, 1), null);
  assertEquals(cycleAmountMinor(1000, 0), null);
});

Deno.test("toRazorpayContact adds the +91 country code to bare Indian mobiles", () => {
  assertEquals(toRazorpayContact("9876543210"), "+919876543210");
  assertEquals(toRazorpayContact("+91 98765 43210"), "+919876543210");
  assertEquals(toRazorpayContact("919876543210"), "+919876543210");
  assertEquals(toRazorpayContact("12345"), null);
  assertEquals(toRazorpayContact(null), null);
});

Deno.test("razorpaySubscriptionStatusToCoaching maps Razorpay's own status strings", () => {
  assertEquals(razorpaySubscriptionStatusToCoaching("active"), "ACTIVE");
  assertEquals(razorpaySubscriptionStatusToCoaching("halted"), "HALTED");
  assertEquals(razorpaySubscriptionStatusToCoaching("expired"), "EXPIRED");
  assertEquals(razorpaySubscriptionStatusToCoaching("something_new"), null);
  assertEquals(razorpaySubscriptionStatusToCoaching(undefined), null);
});

Deno.test("extractLinkPayment reads the payment from an array, an object, or reports none", () => {
  assertEquals(extractLinkPayment({ payments: [{ payment_id: "pay_1", amount: 40000, status: "captured" }] }), {
    paymentId: "pay_1",
    amountMinor: 40000,
  });
  assertEquals(extractLinkPayment({ payments: { payment_id: "pay_2", status: "captured" }, amount_paid: 40000 }), {
    paymentId: "pay_2",
    amountMinor: 40000,
  });
  assertEquals(extractLinkPayment({ payments: [{ payment_id: "pay_3", amount: 100, status: "failed" }] }), null);
  assertEquals(extractLinkPayment({ payments: null }), null);
  assertEquals(extractLinkPayment({}), null);
});
