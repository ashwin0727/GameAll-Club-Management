"use client";

import { useState } from "react";
import { ArrowRight, BadgeCheck, Check, Clock, ShieldCheck } from "lucide-react";
import { isCheckoutCancellation, isCheckoutFailure } from "@/features/payments/razorpay-checkout";
import { Skeleton } from "@/components/ui/skeleton";
import { FormMessage } from "@/features/auth/components/form-message";
import { SubmitButton } from "@/features/auth/components/submit-button";
import { Feature, featureRows, type PlanKey } from "@/features/plans/components/pricing-page";
import { usePlanOptions, useSelectPlan } from "@/features/plans/hooks";
import { formatRupees, limitLabel, priceFor, yearlySavingMinor } from "@/features/plans/plans";
import type { BillingInterval, PlanOption, PlanSnapshot } from "@/features/plans/types";
import { cn } from "@/lib/utils";

const TAGLINE: Record<string, string> = {
  basic: "For clubs getting started",
  advanced: "For clubs that want it all on autopilot",
};

/** The percentage a plan saves when paid yearly, rounded (e.g. 16). */
function savingPct(plan: PlanOption): number {
  const full = plan.monthlyMinor * 12;
  return full > 0 ? Math.round((yearlySavingMinor(plan) / full) * 100) : 0;
}

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
          if (isCheckoutCancellation(e)) return; // closed Checkout without paying, nothing happened
          setError(isCheckoutFailure(e) ? e.description : e instanceof Error ? e.message : "Could not save your plan.");
        },
        onSettled: () => setPendingCode(null),
      },
    );
  }

  if (options.isLoading) return <Skeleton className="h-80 w-full rounded-xl" />;
  if (options.isError || !options.data?.length) return <FormMessage>We couldn&apos;t load the plans. Please try again.</FormMessage>;

  const trialDays = options.data[0]?.trialDays ?? 90;
  const bestSaving = Math.max(...options.data.map(savingPct));

  return (
    <div className="space-y-8">
      {error && <FormMessage>{error}</FormMessage>}

      <div className="flex justify-center">
        <div role="group" aria-label="Billing period" className="inline-flex items-center rounded-full border border-border bg-muted/60 p-1 text-sm">
          {(["month", "year"] as const).map((i) => (
            <button
              key={i}
              type="button"
              aria-pressed={interval === i}
              onClick={() => setInterval(i)}
              className={cn(
                "flex items-center gap-2 rounded-full px-5 py-2 font-medium transition-all",
                interval === i ? "bg-background text-foreground shadow-sm" : "text-muted-foreground hover:text-foreground",
              )}
            >
              {i === "month" ? "Monthly" : "Yearly"}
              {i === "year" && bestSaving > 0 && (
                <span className="rounded-full bg-primary/10 px-2 py-0.5 text-[11px] font-semibold text-primary">Save {bestSaving}%</span>
              )}
            </button>
          ))}
        </div>
      </div>

      <div className="grid gap-6 lg:grid-cols-2 lg:items-start">
        {options.data.map((plan) => {
          const isCurrent = current?.planCode === plan.code;
          const isCurrentPeriod = isCurrent && current?.interval === interval;
          const known = plan.code === "basic" || plan.code === "advanced";
          const rows = known ? featureRows(plan.code as PlanKey) : [];
          const price = priceFor(plan, interval);
          const perMonth = Math.round(plan.yearlyMinor / 12 / 100) * 100;
          return (
            <section
              key={plan.code}
              className={cn(
                "relative flex flex-col overflow-hidden rounded-3xl border bg-card",
                plan.isPopular ? "border-primary shadow-[0_20px_60px_-20px_hsl(var(--primary)/0.35)] ring-4 ring-primary/10" : "border-border",
              )}
            >
              <div className={cn("px-6 pb-6 pt-7 sm:px-8", plan.isPopular ? "bg-primary/[0.08]" : "bg-muted/50")}>
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <h2 className="text-2xl font-semibold tracking-tight">{plan.name}</h2>
                    {TAGLINE[plan.code] && <p className="mt-0.5 text-sm font-medium text-primary">{TAGLINE[plan.code]}</p>}
                  </div>
                  <div className="flex shrink-0 flex-col items-end gap-1.5">
                    {plan.isPopular && (
                      <span className="rounded-full bg-primary px-3 py-1 text-xs font-semibold text-primary-foreground">Most popular</span>
                    )}
                    {isCurrent && (
                      <span className="inline-flex items-center gap-1 rounded-full border border-primary/30 bg-background px-3 py-1 text-xs font-semibold text-primary">
                        <BadgeCheck className="h-3.5 w-3.5" aria-hidden /> Your plan
                      </span>
                    )}
                  </div>
                </div>
                {plan.description && <p className="mt-4 text-[15px] leading-relaxed text-foreground/80">{plan.description}</p>}

                <div className="mt-5 flex flex-wrap items-baseline gap-x-2 gap-y-1">
                  {interval === "year" && plan.monthlyMinor * 12 > plan.yearlyMinor && (
                    <span className="text-lg font-medium text-muted-foreground line-through">{formatRupees(plan.monthlyMinor * 12)}</span>
                  )}
                  <span className="text-4xl font-semibold tracking-tight">{formatRupees(price)}</span>
                  <span className="text-sm text-muted-foreground">/ {interval}</span>
                  {interval === "year" && savingPct(plan) > 0 && (
                    <span className="ml-1 rounded-full bg-primary/10 px-2 py-0.5 text-xs font-semibold text-primary">Save {savingPct(plan)}%</span>
                  )}
                </div>
                <p className="mt-1.5 h-4 text-xs text-muted-foreground">
                  {interval === "year" ? `Just ${formatRupees(perMonth)} a month, billed yearly` : `Billed monthly. Switch to yearly and save ${savingPct(plan)}%`}
                </p>

                <SubmitButton
                  type="button"
                  className="mt-5 h-12 w-full rounded-xl"
                  pending={pendingCode === plan.code}
                  pendingLabel="Opening payment…"
                  disabled={select.isPending || isCurrentPeriod}
                  onClick={() => choose(plan)}
                >
                  {isCurrentPeriod ? (
                    "Current plan"
                  ) : (
                    <span className="inline-flex items-center gap-2">
                      {current ? `Switch to ${plan.name}` : plan.trialDays > 0 ? `Start ${plan.trialDays}-day free trial` : ctaLabel}
                      <ArrowRight className="h-4 w-4" aria-hidden />
                    </span>
                  )}
                </SubmitButton>
              </div>

              <div className="flex-1 px-6 pb-7 pt-6 sm:px-8">
                <p className="mb-4 text-[15px] font-semibold">{plan.isPopular ? "Everything in Basic, plus:" : "What you get:"}</p>
                <ul className="space-y-3.5">
                  <li className="flex gap-3 text-sm font-medium">
                    <Check className="mt-0.5 h-4 w-4 shrink-0 text-primary" aria-hidden />
                    {limitLabel(plan.maxCourts, "courts")}
                    {plan.pageKeys.includes("STAFF") && ` and ${limitLabel(plan.maxStaff, "staff logins").toLowerCase()}`}
                  </li>
                  {known
                    ? rows.map((r) => <Feature key={r.key} line={r.line} upgrade={r.upgrade} />)
                    : plan.features.map((f) => (
                        <li key={f} className="flex gap-3 text-sm">
                          <Check className="mt-0.5 h-4 w-4 shrink-0 text-primary" aria-hidden />
                          {f}
                        </li>
                      ))}
                </ul>
              </div>
            </section>
          );
        })}
      </div>

      <div className="grid gap-3 rounded-2xl border border-border bg-muted/40 p-4 text-sm sm:grid-cols-3">
        <p className="flex items-center gap-2">
          <Clock className="h-4 w-4 shrink-0 text-primary" aria-hidden /> {trialDays} days free, nothing to pay today
        </p>
        <p className="flex items-center gap-2">
          <ShieldCheck className="h-4 w-4 shrink-0 text-primary" aria-hidden /> Flat fee, no commission on bookings
        </p>
        <p className="flex items-center gap-2">
          <Check className="h-4 w-4 shrink-0 text-primary" aria-hidden /> Switch or cancel any time
        </p>
      </div>
      <p className="text-center text-xs text-muted-foreground">
        You authorise Auto Pay now and pay nothing for the first {trialDays} days. After that your chosen plan is charged automatically, monthly or yearly, until you cancel.
      </p>
    </div>
  );
}
