import { assertEquals } from "jsr:@std/assert";
import { billingCycle, oneTimeItems, razorpayAddons, recurringAmountInr } from "./membership-billing.ts";

Deno.test("billingCycle: 1 month is monthly, 3 months is every 3 months, 12 months is yearly", () => {
  assertEquals(billingCycle(30), { period: "monthly", interval: 1, months: 1, label: "monthly" });
  assertEquals(billingCycle(90), { period: "monthly", interval: 3, months: 3, label: "every 3 months" });
  assertEquals(billingCycle(180), { period: "monthly", interval: 6, months: 6, label: "every 6 months" });
  assertEquals(billingCycle(365), { period: "yearly", interval: 1, months: 12, label: "yearly" });
  assertEquals(billingCycle(0).interval, 1); // no duration falls back to monthly
});

Deno.test("recurringAmountInr: the plan's price, never a payment total", () => {
  assertEquals(recurringAmountInr(2500, 2900), 2500);
  assertEquals(recurringAmountInr(null, 2500), 2500); // no plan behind it: the membership's own fee
  assertEquals(recurringAmountInr(undefined, undefined), 0);
});

Deno.test("oneTimeItems: registration fee and GST on the plan price, nothing when there are none", () => {
  assertEquals(oneTimeItems({ recurringInr: 2500, registrationFeeInr: 200, gstPercent: 0 }), [
    { name: "Registration / joining fee (one-time)", amountInr: 200 },
  ]);
  assertEquals(oneTimeItems({ recurringInr: 2500, registrationFeeInr: 200, gstPercent: 18 }), [
    { name: "Registration / joining fee (one-time)", amountInr: 200 },
    { name: "GST 18% (first payment)", amountInr: 450 },
  ]);
  assertEquals(oneTimeItems({ recurringInr: 2500, registrationFeeInr: 0, gstPercent: 0 }), []);
  assertEquals(oneTimeItems({ recurringInr: 2500, registrationFeeInr: null, gstPercent: null }), []);
});

Deno.test("razorpayAddons: paise, and only items with an amount", () => {
  assertEquals(razorpayAddons([{ name: "Joining fee", amountInr: 200 }, { name: "Zero", amountInr: 0 }]), [
    { item: { name: "Joining fee", amount: 20000, currency: "INR" } },
  ]);
});
