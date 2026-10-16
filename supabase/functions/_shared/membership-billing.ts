// ═══════════════════════════════════════════════════════════════════════════
// Membership AutoPay — the amount and cadence maths, kept pure and unit-tested.
//
// What a member is charged:
//   • EVERY cycle  — the PLAN's price (its "Price per billing cycle"), on the plan's billing interval:
//                    1 month → monthly, 3 months → every 3 months, 12 months → yearly.
//   • ONCE, with the first payment only — the extras the owner added on top: the registration / joining
//                    fee and any GST. These never recur.
// Razorpay anchors the schedule to the day the first payment is made (14 Oct → 14 Nov → 14 Dec …).
// ═══════════════════════════════════════════════════════════════════════════

export interface BillingCycle {
  period: "monthly" | "yearly";
  /** Razorpay's interval: every `interval` months (or years). */
  interval: number;
  /** The same cycle in calendar months (12 for a yearly plan). */
  months: number;
  label: string;
}

/**
 * The plan's Duration (30 / 90 / 180 / 365 days) as a Razorpay cadence. Razorpay has no "quarterly" —
 * 3 and 6 months are `monthly` with an interval.
 */
export function billingCycle(durationDays: number): BillingCycle {
  const d = durationDays > 0 ? durationDays : 30;
  if (d >= 360) {
    const years = Math.max(1, Math.round(d / 365));
    return { period: "yearly", interval: years, months: years * 12, label: years === 1 ? "yearly" : `every ${years} years` };
  }
  const months = Math.max(1, Math.round(d / 30));
  return { period: "monthly", interval: months, months, label: months === 1 ? "monthly" : `every ${months} months` };
}

/**
 * The amount charged every cycle: the plan's price. Only a membership with no plan behind it falls back
 * to its own fee — never to a payment total, which carries one-time extras.
 */
export function recurringAmountInr(planPriceInr: number | null | undefined, membershipFeeInr: number | null | undefined): number {
  if (planPriceInr && planPriceInr > 0) return Math.round(planPriceInr);
  return Math.max(0, Math.round(membershipFeeInr ?? 0));
}

export interface OneTimeItem {
  name: string;
  amountInr: number;
}

/** What is charged once, on top of the first cycle: the registration / joining fee and the GST on the plan price. */
export function oneTimeItems(input: { recurringInr: number; registrationFeeInr: number | null | undefined; gstPercent: number | null | undefined }): OneTimeItem[] {
  const items: OneTimeItem[] = [];
  const registration = Math.max(0, Math.round(input.registrationFeeInr ?? 0));
  if (registration > 0) items.push({ name: "Registration / joining fee (one-time)", amountInr: registration });
  const gst = Math.max(0, input.gstPercent ?? 0);
  const gstAmount = Math.round((input.recurringInr * gst) / 100);
  if (gstAmount > 0) items.push({ name: `GST ${gst}% (first payment)`, amountInr: gstAmount });
  return items;
}

/** Razorpay `addons`: one-time items added to the FIRST charge only. Amounts are in paise. */
export function razorpayAddons(items: OneTimeItem[]): { item: { name: string; amount: number; currency: string } }[] {
  return items.filter((i) => i.amountInr > 0).map((i) => ({ item: { name: i.name, amount: i.amountInr * 100, currency: "INR" } }));
}
