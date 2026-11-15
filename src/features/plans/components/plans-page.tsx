"use client";

import { useRouter } from "next/navigation";
import { CalendarClock, ChevronDown, Crown } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import { FAQS, GROUPS, GroupRows } from "@/features/plans/components/pricing-page";
import { PlanNotice } from "@/features/plans/components/plan-notice";
import { PlanPicker } from "@/features/plans/components/plan-picker";
import { useMyPlan, usePlanOptions } from "@/features/plans/hooks";
import { formatRupees } from "@/features/plans/plans";
import type { PlanSnapshot } from "@/features/plans/types";
import { formatPlanDate } from "@/features/profile/plan";

const TRIAL_DAYS = 90;

/** Where the club stands today: the plan, its price, and when it renews or the trial ends. */
function CurrentPlanCard({ plan }: { plan: PlanSnapshot }) {
  const endLabel = plan.lapsed ? "Ended on" : plan.onTrial ? "Trial ends on" : "Renews on";
  const used = plan.onTrial ? Math.min(100, Math.max(0, ((TRIAL_DAYS - plan.daysLeft) / TRIAL_DAYS) * 100)) : 0;
  return (
    <section className="overflow-hidden rounded-3xl border border-primary/20 bg-card shadow-sm">
      <div className="flex flex-col items-center gap-6 bg-gradient-to-b from-primary/[0.10] via-primary/[0.04] to-transparent px-6 pb-7 pt-8 text-center">
        <div className="flex flex-col items-center gap-3">
          <span className="flex h-12 w-12 items-center justify-center rounded-2xl bg-primary text-primary-foreground">
            <Crown className="h-6 w-6" aria-hidden />
          </span>
          <div>
            <p className="text-xs font-medium uppercase tracking-wider text-muted-foreground">Your current plan</p>
            <p className="text-xl font-semibold tracking-tight">
              {plan.name}
              {plan.onTrial && (
                <span className="ml-2 rounded-full bg-primary/10 px-2.5 py-0.5 align-middle text-xs font-semibold text-primary">Free trial</span>
              )}
              {plan.lapsed && (
                <span className="ml-2 rounded-full bg-warning/15 px-2.5 py-0.5 align-middle text-xs font-semibold text-foreground">Ended</span>
              )}
            </p>
          </div>
        </div>
        <div className="grid w-full max-w-sm grid-cols-2 gap-4 rounded-2xl border border-border bg-background/80 p-4 text-sm">
          <div>
            <p className="text-muted-foreground">Price</p>
            <p className="font-semibold">
              {formatRupees(plan.priceMinor)} <span className="font-normal text-muted-foreground">/ {plan.interval}</span>
            </p>
          </div>
          <div>
            <p className="flex items-center justify-center gap-1.5 text-muted-foreground">
              <CalendarClock className="h-3.5 w-3.5" aria-hidden /> {endLabel}
            </p>
            <p className="font-semibold">{formatPlanDate(plan.validTill)}</p>
          </div>
        </div>
      </div>
      {plan.onTrial && (
        <div className="border-t border-border px-6 py-5">
          <div className="flex items-center justify-between text-xs text-muted-foreground">
            <span>
              {plan.daysLeft} day{plan.daysLeft === 1 ? "" : "s"} left of your {TRIAL_DAYS}-day trial
            </span>
            <span>{Math.round(used)}% used</span>
          </div>
          <div className="mt-2 h-2 overflow-hidden rounded-full bg-muted" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(used)}>
            <div className="h-full rounded-full bg-primary transition-all" style={{ width: `${used}%` }} />
          </div>
        </div>
      )}
    </section>
  );
}

function ComparisonTable() {
  const options = usePlanOptions();
  const price = (code: string) => options.data?.find((p) => p.code === code);
  const basic = price("basic");
  const advanced = price("advanced");
  return (
    <section>
      <h2 className="text-xl font-semibold tracking-tight">Compare the plans</h2>
      <p className="mt-1 text-sm text-muted-foreground">Every page in the app, and which plan it comes with.</p>
      <div className="mt-5 overflow-hidden rounded-2xl border border-border bg-card">
        <div className="overflow-x-auto">
          <table className="w-full min-w-[560px] text-sm">
            <thead>
              <tr className="border-b border-border bg-muted/40 text-left">
                <th className="px-5 py-4 font-medium text-muted-foreground">Feature</th>
                <th className="w-40 px-4 py-4 text-center">
                  <span className="block font-semibold">Basic</span>
                  {basic && <span className="text-xs font-normal text-muted-foreground">{formatRupees(basic.monthlyMinor)} / month</span>}
                </th>
                <th className="w-40 bg-primary/[0.06] px-4 py-4 text-center">
                  <span className="block font-semibold text-primary">Advanced</span>
                  {advanced && <span className="text-xs font-normal text-muted-foreground">{formatRupees(advanced.monthlyMinor)} / month</span>}
                </th>
              </tr>
            </thead>
            <tbody>
              {GROUPS.map((g) => (
                <GroupRows key={g.title} title={g.title} keys={g.keys} />
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </section>
  );
}

function Faq() {
  return (
    <section>
      <h2 className="text-xl font-semibold tracking-tight">Questions, answered</h2>
      <div className="mt-5 divide-y divide-border rounded-2xl border border-border bg-card">
        {FAQS.map((f) => (
          <details key={f.q} className="group px-5 py-4 [&_summary::-webkit-details-marker]:hidden">
            <summary className="flex cursor-pointer list-none items-center justify-between gap-4 text-sm font-semibold">
              {f.q}
              <ChevronDown className="h-4 w-4 shrink-0 text-muted-foreground transition-transform group-open:rotate-180" aria-hidden />
            </summary>
            <p className="mt-3 text-sm leading-relaxed text-muted-foreground">{f.a}</p>
          </details>
        ))}
      </div>
    </section>
  );
}

/** Dashboard → Plans. The owner can pick or switch; everyone else sees what the club is on. */
export function PlansPage() {
  const router = useRouter();
  const ctx = usePermissionContext();
  const isOwner = ctx?.baseRole === "owner";
  const mine = useMyPlan(ctx?.facilityId);
  const plan = mine.data ?? null;

  if (!ctx) return null;
  if (mine.isLoading) return <Skeleton className="h-80 w-full rounded-xl" />;

  return (
    <div className="w-full space-y-8">
      <div className="mx-auto max-w-2xl space-y-5">
        {plan ? <CurrentPlanCard plan={plan} /> : <PlanNotice plan={plan} />}
        {plan?.lapsed && <PlanNotice plan={plan} />}
      </div>

      {isOwner && (
        <div className="text-center">
          <h2 className="text-2xl font-semibold tracking-tight">{plan ? "Switch plan" : "Choose your plan"}</h2>
          <p className="mt-1 text-sm text-muted-foreground">Pick monthly or yearly. Your data stays exactly where it is when you switch.</p>
        </div>
      )}

      {isOwner ? (
        <PlanPicker facilityId={ctx.facilityId} current={plan} onSelected={() => router.refresh()} />
      ) : (
        <p className="rounded-xl border border-border bg-muted/40 p-4 text-sm text-muted-foreground">Only the owner can change the plan.</p>
      )}

      <ComparisonTable />
      <Faq />
    </div>
  );
}
