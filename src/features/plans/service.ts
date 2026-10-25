import { createClient } from "@/lib/supabase/client";
import { openRazorpaySubscriptionCheckout } from "@/features/payments/razorpay-checkout";
import { toPlanOption, toPlanSnapshot } from "@/features/plans/plans";
import type { BillingInterval, PlanOption, PlanSnapshot } from "@/features/plans/types";

// The plan RPCs are newer than the generated database types, hence the casts.
type Rpc = (fn: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: { message: string } | null }>;
const rpc: Rpc = (fn, args) => {
  const supabase = createClient();
  return (supabase.rpc as unknown as Rpc).call(supabase, fn, args);
};

export async function listPlans(): Promise<PlanOption[]> {
  const { data, error } = await rpc("list_plans");
  if (error) throw new Error("Unable to load the plans.");
  return ((data as Record<string, unknown>[] | null) ?? []).map(toPlanOption);
}

export async function getMyPlan(facilityId: string): Promise<PlanSnapshot | null> {
  const { data, error } = await rpc("my_facility_plan", { p_facility_id: facilityId });
  if (error) throw new Error("Unable to load your plan.");
  return toPlanSnapshot(data as Record<string, unknown> | null);
}

interface StartResponse {
  subscriptionId: string;
  keyId: string;
  planName: string;
  interval: BillingInterval;
  amountMinor: number;
  trial: boolean;
  firstChargeOn: string | null;
}

/**
 * Choose a plan: the server creates the Razorpay subscription, the owner authorises the mandate in Razorpay Checkout, and the
 * server switches the plan on once the signature checks out. A first plan is free until its first charge date. Rejects with
 * `null` when the owner closes Checkout without paying (see isCheckoutCancellation).
 */
export async function startPlan(facilityId: string, planCode: string, interval: BillingInterval): Promise<void> {
  const supabase = createClient();
  const started = await supabase.functions.invoke<StartResponse & { error?: string }>("create-plan-subscription", {
    body: { action: "start", facilityId, planCode, interval },
  });
  if (started.error || !started.data?.subscriptionId) {
    throw new Error(await functionErrorMessage(started.error, "Could not start the plan payment."));
  }
  const info = started.data;

  const outcome = await openRazorpaySubscriptionCheckout(
    { keyId: info.keyId, subscriptionId: info.subscriptionId },
    { description: `${info.planName} plan · ${info.interval === "year" ? "yearly" : "monthly"}` },
  );

  const confirmed = await supabase.functions.invoke<{ ok?: boolean; error?: string }>("create-plan-subscription", {
    body: { action: "confirm", subscriptionId: info.subscriptionId, paymentId: outcome.razorpayPaymentId, signature: outcome.razorpaySignature },
  });
  if (confirmed.error) throw new Error(await functionErrorMessage(confirmed.error, "Your payment went through, but we could not switch the plan on. Please contact support."));
}

async function functionErrorMessage(error: unknown, fallback: string): Promise<string> {
  const ctx = (error as { context?: Response } | null)?.context;
  if (ctx && typeof ctx.json === "function") {
    try {
      const body = (await ctx.json()) as { error?: string };
      if (body.error) return body.error;
    } catch {
      /* fall through */
    }
  }
  return fallback;
}
