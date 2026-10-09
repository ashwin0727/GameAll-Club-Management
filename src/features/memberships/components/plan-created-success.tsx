"use client";

import { Check, Trophy } from "lucide-react";
import { Card } from "@/components/ui/card";
import { durationLabel, planFeatures } from "@/features/memberships/plan-insights";
import { featureCountLabel, planSubtitle, planTotalAmountInr } from "@/features/memberships/plan-created";
import type { MembershipPlan } from "@/features/memberships/types";

function inr(v: number): string {
  return `₹${v.toLocaleString("en-IN")}`;
}

function createdOn(iso: string): string {
  const d = new Date(iso);
  const date = d.toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
  const time = d.toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit", hour12: true }).toUpperCase();
  return `${date}, ${time}`;
}

const CONFETTI = [
  "left-[12%] top-[10%] bg-pink-400",
  "left-[22%] top-[4%] bg-blue-400",
  "left-[34%] top-[14%] bg-yellow-400",
  "right-[30%] top-[8%] bg-green-400",
  "right-[18%] top-[14%] bg-pink-400",
  "right-[10%] top-[6%] bg-orange-400",
  "left-[8%] top-[34%] bg-yellow-400",
  "right-[8%] top-[34%] bg-blue-400",
];

/**
 * Shown right after a plan is saved: the plan at a glance, then three ways on — open the plan,
 * start another, or head back to the plan list.
 */
export function PlanCreatedSuccess({
  plan,
  sportLabel,
  onViewPlan,
  onCreateAnother,
  onGoToPlans,
}: {
  plan: MembershipPlan;
  sportLabel: string | null;
  onViewPlan: () => void;
  onCreateAnother: () => void;
  onGoToPlans: () => void;
}) {
  const rows: [string, string][] = [
    ["Duration", durationLabel(plan.durationDays)],
    ["Price", inr(plan.priceInr)],
    ["Total Amount", inr(planTotalAmountInr(plan))],
    ["Benefits", featureCountLabel(planFeatures(plan).length)],
    ["Created On", createdOn(plan.createdAt)],
  ];

  return (
    <div className="mx-auto w-full max-w-md space-y-6 py-6">
      <div className="relative flex flex-col items-center text-center">
        {CONFETTI.map((c) => (
          <span key={c} aria-hidden className={`absolute h-2 w-1 rotate-45 rounded-sm ${c}`} />
        ))}
        <span className="flex h-28 w-28 items-center justify-center rounded-full bg-[#0B9B63]/10">
          <span className="flex h-20 w-20 items-center justify-center rounded-full bg-[#0B9B63]/20">
            <span className="flex h-14 w-14 items-center justify-center rounded-full bg-[#0B9B63]">
              <Check className="h-8 w-8 text-white" strokeWidth={3} aria-hidden />
            </span>
          </span>
        </span>
        <h1 className="mt-5 text-2xl font-bold text-black dark:text-foreground">Plan Created Successfully!</h1>
        <p className="mt-1 text-sm text-muted-foreground">Your membership plan has been created and is now active.</p>
      </div>

      <Card className="space-y-4 rounded-2xl p-4">
        <div className="flex items-center gap-3">
          <span className="flex h-16 w-16 shrink-0 items-center justify-center rounded-xl bg-[#0B9B63]/15 text-[#0B7A55]">
            <Trophy className="h-7 w-7" aria-hidden />
          </span>
          <div className="min-w-0">
            <p className="truncate text-base font-bold text-black dark:text-foreground">{plan.name}</p>
            <p className="text-xs text-muted-foreground">{planSubtitle(plan.category, sportLabel)}</p>
            <span className="mt-1.5 inline-block rounded-full bg-[#0B9B63]/15 px-3 py-0.5 text-xs font-semibold text-[#0B7A55]">
              Active
            </span>
          </div>
        </div>
        <dl className="divide-y divide-border border-t border-border">
          {rows.map(([k, v]) => (
            <div key={k} className="flex items-center justify-between gap-3 py-2.5 text-sm">
              <dt className="text-muted-foreground">{k}</dt>
              <dd className="font-semibold text-foreground">{v}</dd>
            </div>
          ))}
        </dl>
      </Card>

      <div className="space-y-3">
        <button
          type="button"
          onClick={onViewPlan}
          className="h-12 w-full rounded-xl bg-[#0B9B63] text-sm font-semibold text-white transition-opacity hover:opacity-90"
        >
          View Plan
        </button>
        <button
          type="button"
          onClick={onCreateAnother}
          className="h-12 w-full rounded-xl border border-[#0B9B63] bg-card text-sm font-semibold text-[#0B7A55] transition-colors hover:bg-[#0B9B63]/5"
        >
          Create Another Plan
        </button>
        <button
          type="button"
          onClick={onGoToPlans}
          className="h-12 w-full rounded-xl border border-[#0B9B63] bg-card text-sm font-semibold text-[#0B7A55] transition-colors hover:bg-[#0B9B63]/5"
        >
          Go to Membership Plans
        </button>
      </div>
    </div>
  );
}
