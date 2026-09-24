"use client";

import { Check } from "lucide-react";
import { PLAN_WIZARD_STEPS, type PlanWizardStep } from "@/features/memberships/create-plan-wizard";
import { cn } from "@/lib/utils";

/**
 * The five-step vertical tracker down the left of Create Membership Plan — same rules as the
 * Add Member wizard's horizontal `WizardStepper` (current step filled, done steps ticked,
 * ahead-of-furthest steps locked), laid out as a column with a connecting line between the
 * numbered circles, matching the design.
 */
export function PlanWizardStepper({
  current,
  furthest,
  isDone,
  onSelect,
}: {
  current: PlanWizardStep;
  furthest: PlanWizardStep;
  isDone: (step: PlanWizardStep) => boolean;
  onSelect: (step: PlanWizardStep) => void;
}) {
  return (
    <ol>
      {PLAN_WIZARD_STEPS.map(({ step, title, hint }, i) => {
        const isCurrent = step === current;
        const done = isDone(step);
        const reachable = step <= furthest;
        return (
          <li key={step} className={cn("relative", i < PLAN_WIZARD_STEPS.length - 1 && "pb-4")}>
            {/* Spans to the *bottom of the li* rather than a fixed percentage — since the gap
                between items is this padding, not a margin outside the li's own box, the line
                now actually reaches the next circle instead of stopping short of it. */}
            {/* Horizontally centered on the circle: button padding (6px) + half the circle's
                width (18px) = 24px. Starts right at the circle's own bottom edge — the button's
                6px top padding pushes the circle down that far too, so top-9 (36px) alone
                would've landed inside the circle, overlapping the number/tick. */}
            {i < PLAN_WIZARD_STEPS.length - 1 && <span className="absolute bottom-0 left-[23.5px] top-[42px] w-px bg-border" aria-hidden />}
            <button
              type="button"
              disabled={!reachable}
              aria-current={isCurrent ? "step" : undefined}
              onClick={() => reachable && onSelect(step)}
              className={cn(
                "relative flex w-full items-center gap-3 rounded-lg p-1.5 text-left transition-colors",
                reachable ? "hover:bg-accent/50" : "cursor-not-allowed opacity-60",
              )}
            >
              <span
                className={cn(
                  "flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-sm font-semibold transition-colors",
                  isCurrent
                    ? "bg-[#0B9B63] text-white"
                    : done
                      ? "bg-success/20 text-success"
                      : "bg-muted text-muted-foreground",
                )}
              >
                {done ? <Check className="h-4 w-4" strokeWidth={3} aria-hidden /> : step}
              </span>
              <span className="min-w-0">
                <span
                  className={cn(
                    "block text-sm font-semibold",
                    isCurrent || done ? "text-black dark:text-foreground" : "text-muted-foreground",
                  )}
                >
                  {title}
                </span>
                <span className="block text-xs text-muted-foreground">{hint}</span>
              </span>
            </button>
          </li>
        );
      })}
    </ol>
  );
}
