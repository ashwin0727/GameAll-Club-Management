import type { MembershipAutoPay } from "@/features/memberships/types";

/** How the member's AutoPay is doing, in words an owner can act on. */
export function autoPayStatusLabel(status: MembershipAutoPay["status"]): { label: string; detail: string } {
  switch (status) {
    case "created":
      return { label: "Awaiting authorisation", detail: "The member hasn't approved the payment link yet. Charging starts once they do." };
    case "authenticated":
      return { label: "Authorised", detail: "The member approved AutoPay; the first charge is being processed." };
    case "active":
      return { label: "Active", detail: "Charged automatically each cycle on the same day of the month." };
    case "pending":
      return { label: "Payment failed — retrying", detail: "The last charge failed. Razorpay is retrying; the member may need to check their account." };
    case "halted":
      return { label: "Stopped — payment failed", detail: "Retries ran out. The member must authorise again or pay another way." };
    case "cancelled":
      return { label: "Cancelled", detail: "AutoPay was stopped. The membership runs to its paid-until date." };
    case "completed":
      return { label: "Completed", detail: "AutoPay ran its full course." };
  }
}

/** "every month", "every 3 months", "every year". */
export function autoPayCadence(intervalMonths: number | null): string {
  if (!intervalMonths || intervalMonths === 1) return "every month";
  if (intervalMonths === 12) return "every year";
  if (intervalMonths % 12 === 0) return `every ${intervalMonths / 12} years`;
  return `every ${intervalMonths} months`;
}

/**
 * A subscription that has already collected a charge is active, whatever the last event said — Razorpay can
 * deliver "authenticated" after "charged", and older rows were left on the earlier status.
 */
export function effectiveAutoPayStatus(a: Pick<MembershipAutoPay, "status" | "chargeCount">): MembershipAutoPay["status"] {
  if ((a.status === "authenticated" || a.status === "created") && a.chargeCount > 0) return "active";
  return a.status;
}

/**
 * The date the next AutoPay charge is due: shown whenever AutoPay is running — charging, retrying, or
 * authorised with the first charge already collected. Razorpay's own date when we have it, else the
 * membership's next payment date. Null before the first charge and once AutoPay has stopped.
 */
export function autoPayNextCharge(a: Pick<MembershipAutoPay, "status" | "chargeCount" | "nextChargeDate">, membershipEndDate: string | null): string | null {
  const status = effectiveAutoPayStatus(a);
  if (status !== "active" && status !== "pending") return null;
  return a.nextChargeDate ?? membershipEndDate;
}
