"use client";

import { ArrowRight, CalendarDays, Check } from "lucide-react";
import {
  durationLabel,
  monthlyEquivalentInr,
  planFeatures,
  planTagline,
  splitPlanName,
  type PlanBadge,
} from "@/features/memberships/plan-insights";
import type { MembershipPlan } from "@/features/memberships/types";
import { cn } from "@/lib/utils";

export interface PlanCardTheme {
  surface: string;
  chip: string;
  tick: string;
  button: string;
  badge: string;
  rule: string;
}

/**
 * One theme per card position, cycled, so no two plans side by side look alike — clubs often
 * run several plans of the same length, which a duration-based palette would paint identically.
 */
/** Exported so any other plan listing (the Add Member wizard's picker) uses these same colours. */
export const PLAN_CARD_THEMES: PlanCardTheme[] = [
  {
    surface: "bg-[#EFFBF4] dark:bg-success/10",
    chip: "bg-success/20 text-success",
    tick: "bg-success",
    button: "bg-[#0B9B63]",
    badge: "bg-success/20 text-success",
    rule: "bg-success/20",
  },
  {
    surface: "bg-[#EFF5FE] dark:bg-blue-500/10",
    chip: "bg-blue-500/20 text-blue-600 dark:text-blue-400",
    tick: "bg-blue-500",
    button: "bg-blue-600",
    badge: "bg-blue-500/20 text-blue-700 dark:text-blue-300",
    rule: "bg-blue-500/20",
  },
  {
    surface: "bg-[#FFF8EC] dark:bg-warning/10",
    chip: "bg-warning/25 text-warning",
    tick: "bg-warning",
    button: "bg-[#E89611]",
    badge: "bg-warning/25 text-warning",
    rule: "bg-warning/25",
  },
  {
    surface: "bg-[#F7F2FE] dark:bg-purple-500/10",
    chip: "bg-purple-500/20 text-purple-600 dark:text-purple-400",
    tick: "bg-purple-500",
    button: "bg-purple-600",
    badge: "bg-purple-500/20 text-purple-700 dark:text-purple-300",
    rule: "bg-purple-500/20",
  },
];

function inr(v: number): string {
  return `₹${v.toLocaleString("en-IN")}`;
}

/**
 * One plan in the "Popular Plans" row: its price (with the per-month equivalent where the plan
 * runs longer than a month), what it includes, and a way into its details.
 */
export function PlanCard({
  plan,
  badge,
  index = 0,
  glass = false,
  bordered = true,
  ctaLabel = "View Details",
  onViewDetails,
}: {
  plan: MembershipPlan;
  badge?: PlanBadge | string;
  /** Position in the row — picks the card's colour. */
  index?: number;
  /** Drops the drawn border for a translucent, ring-edged surface. */
  glass?: boolean;
  /** False when this card is already nested inside another bordered container (e.g. the Create
   *  Plan wizard's Plan Preview) — its own border/shadow would just double up on the outer one. */
  bordered?: boolean;
  /** E.g. "Join Now" for a live preview card, where there's nothing to view details of yet. */
  ctaLabel?: string;
  onViewDetails: () => void;
}) {
  const theme = PLAN_CARD_THEMES[index % PLAN_CARD_THEMES.length]!;
  const name = splitPlanName(plan.name);
  const perMonth = monthlyEquivalentInr(plan.priceInr, plan.durationDays);
  const months = Math.max(1, Math.round(plan.durationDays / 30));

  return (
    <div
      className={cn(
        "relative flex flex-col rounded-2xl p-4",
        theme.surface,
        !bordered
          ? "border-0"
          : glass
            ? "border-0 shadow-[0_6px_20px_rgba(16,40,34,0.06)] ring-1 ring-white/60 backdrop-blur-md dark:ring-white/10"
          : "border border-border/60",
      )}
    >
      {badge && (
        <span className={cn("absolute right-3 top-3 rounded-full px-2.5 py-1 text-[11px] font-semibold", theme.badge)}>
          {badge}
        </span>
      )}

      {/* Icon and name side by side, as in the design. */}
      <div className="flex items-start gap-3 pr-20">
        <span className={cn("flex h-11 w-11 shrink-0 items-center justify-center rounded-xl", theme.chip)}>
          <CalendarDays className="h-5 w-5" aria-hidden />
        </span>
        {/* A bracketed qualifier drops to its own line rather than being squashed onto one. */}
        <p className="min-w-0 break-words text-[15px] font-bold leading-snug text-black dark:text-foreground">
          {name.main}
          {name.detail && <span className="block text-xs font-medium text-muted-foreground">{name.detail}</span>}
        </p>
      </div>

      {/* A plan's own description wins — planTagline is only the generic fallback for plans that don't have one. */}
      <p className="mt-3 text-sm text-muted-foreground">{plan.description?.trim() || planTagline(plan.durationDays)}</p>

      {/* The price and its unit stay on one line; the per-month equivalent gets its own below. */}
      <p className="mt-3 flex items-baseline gap-1.5 whitespace-nowrap">
        <span className="text-2xl font-bold tabular-nums text-black dark:text-foreground">{inr(plan.priceInr)}</span>
        <span className="text-sm text-muted-foreground">{months === 1 ? "/ month" : `/ ${durationLabel(plan.durationDays)}`}</span>
      </p>
      {months > 1 && <p className="mt-0.5 text-sm text-muted-foreground">({inr(perMonth)} / month)</p>}

      <span className={cn("my-4 h-px w-full", theme.rule)} aria-hidden />

      <ul className="flex-1 space-y-2.5">
        {planFeatures(plan).map((f) => (
          <li key={f} className="flex items-start gap-2 text-sm text-foreground/85">
            {/* A filled disc with a white tick, per the design — not a bare check mark. */}
            <span className={cn("mt-0.5 flex h-4 w-4 shrink-0 items-center justify-center rounded-full", theme.tick)}>
              <Check className="h-2.5 w-2.5 text-white" strokeWidth={3.5} aria-hidden />
            </span>
            <span>{f}</span>
          </li>
        ))}
      </ul>

      <button
        type="button"
        onClick={onViewDetails}
        className={cn(
          "mt-4 flex h-11 w-full items-center justify-center gap-2 rounded-xl text-sm font-semibold text-white transition-opacity hover:opacity-90",
          theme.button,
        )}
      >
        {ctaLabel}
        <ArrowRight className="h-4 w-4" aria-hidden />
      </button>
    </div>
  );
}
