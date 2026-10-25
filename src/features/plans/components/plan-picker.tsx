"use client";

import { useState } from "react";
import { Check } from "lucide-react";
import { isCheckoutCancellation, isCheckoutFailure } from "@/features/payments/razorpay-checkout";
import { Skeleton } from "@/components/ui/skeleton";
import { FormMessage } from "@/features/auth/components/form-message";
import { SubmitButton } from "@/features/auth/components/submit-button";
import { usePlanOptions, useSelectPlan } from "@/features/plans/hooks";
import { formatRupees, limitLabel, priceFor, yearlySavingMinor } from "@/features/plans/plans";
import type { BillingInterval, PlanOption, PlanSnapshot } from "@/features/plans/types";
import { cn } from "@/lib/utils";

/**
 * Two plans, monthly or yearly. Choosing one starts the free trial the first time; after that it just switches the plan.
 * Shared by the onboarding step and the dashboard Plans page.
 */
export function PlanPicker({
  facilityId,
  current,
  onSelected,
  ctaLabel = "Choose plan",
}: {
  facilityId: string;
  current: PlanSnapshot | null;
  onSelected: () => void;
  ctaLabel?: string;
}) {
  const options = usePlanOptions();
  const select = useSelectPlan(facilityId);
  const [interval, setInterval] = useState<BillingInterval>(current?.interval ?? "year");
  const [pendingCode, setPendingCode] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  function choose(plan: PlanOption) {
    setError(null);
    setPendingCode(plan.code);
    select.mutate(
      { planCode: plan.code, interval },
      {
        onSuccess: onSelected,
        onError: (e) => {
          if (isCheckoutCancellation(e)) return; // closed Checkout without paying — nothing happened
          setError(isCheckoutFailure(e) ? e.description : e instanceof Error ? e.message : "Could not save your plan.");
        },
        onSettled: () => setPendingCode(null),
      },
    );
  }

  if (options.isLoading) return <Skeleton className="h-80 w-full rounded-xl" />;
  if (options.isError || !options.data?.length) return <FormMessage>We couldn&apos;t load the plans. Please try again.</FormMessage>;

  return (
    <div className="space-y-6">
      {error && <FormMessage>{error}</FormMessage>}

      <div className="flex justify-center">
        <div role="group" aria-label="Billing period" className="inline-flex rounded-full border border-border bg-muted/50 p-1 text-sm">
          {(["month", "year"] as const).map((i) => (
            <button
              key={i}
              type="button"
              aria-pressed={interval === i}
              onClick={() => setInterval(i)}
              className={cn(
                "rounded-full px-4 py-1.5 font-medium transition-colors",
                interval === i ? "bg-background text-foreground shadow-sm" : "text-muted-foreground hover:text-foreground",
              )}
            >
              {i === "month" ? "Monthly" : "Yearly"}
            </button>
          ))}
        </div>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        {options.data.map((plan) => {
          const isCurrent = current?.planCode === plan.code;
          const saving = yearlySavingMinor(plan);
          return (
            <div
              key={plan.code}
              className={cn(
                "relative flex flex-col rounded-2xl border bg-card p-6",
                plan.isPopular ? "border-primary shadow-sm" : "border-border",
              )}
            >
              {plan.isPopular && (
                <span className="absolute -top-3 left-6 rounded-full bg-primary px-3 py-0.5 text-xs font-medium text-primary-foreground">
                  Most popular
                </span>
              )}
              <h2 className="text-lg font-semibold">{plan.name}</h2>
              {plan.description && <p className="mt-1 text-sm text-muted-foreground">{plan.description}</p>}

              <p className="mt-5 flex items-baseline gap-1">
                <span className="text-4xl font-semibold tracking-tight">{formatRupees(priceFor(plan, interval))}</span>
                <span className="text-sm text-muted-foreground">/ {interval}</span>
              </p>
              <p className="mt-1 h-5 text-xs text-muted-foreground">
                {interval === "year" && saving > 0 ? `Save ${formatRupees(saving)} a year vs monthly` : " "}
              </p>

              <ul className="mt-5 flex-1 space-y-2.5 text-sm">
                <li className="flex gap-2">
                  <Check className="mt-0.5 h-4 w-4 shrink-0 text-primary" aria-hidden />
                  {limitLabel(plan.maxCourts, "courts")}
                </li>
                <li className="flex gap-2">
                  <Check className="mt-0.5 h-4 w-4 shrink-0 text-primary" aria-hidden />
                  {limitLabel(plan.maxStaff, "staff logins")}
                </li>
                {plan.features.map((f) => (
                  <li key={f} className="flex gap-2">
                    <Check className="mt-0.5 h-4 w-4 shrink-0 text-primary" aria-hidden />
                    {f}
                  </li>
                ))}
              </ul>

              <SubmitButton
                type="button"
                className="mt-6"
                pending={pendingCode === plan.code}
                pendingLabel="Opening payment…"
                disabled={select.isPending || (isCurrent && current?.interval === interval)}
                onClick={() => choose(plan)}
              >
                {isCurrent && current?.interval === interval
                  ? "Current plan"
                  : current
                    ? `Switch to ${plan.name}`
                    : plan.trialDays > 0
                      ? `Start ${plan.trialDays}-day free trial`
                      : ctaLabel}
              </SubmitButton>
            </div>
          );
        })}
      </div>

      <p className="text-center text-xs text-muted-foreground">
        You authorise Auto Pay now and pay nothing for the first {options.data[0]?.trialDays ?? 90} days. After that your chosen plan is charged automatically — monthly or yearly — until you cancel.
      </p>
    </div>
  );
}
