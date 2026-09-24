"use client";

import { Check } from "lucide-react";
import { WIZARD_STEPS, type WizardStep } from "@/features/memberships/add-member-wizard";
import { cn } from "@/lib/utils";

/**
 * The five-step tracker across the top of Add New Member. The step you're on is filled green,
 * finished steps carry a tick and can be gone back to, and steps ahead stay muted until the
 * ones before them are complete.
 */
export function WizardStepper({
  current,
  furthest,
  onSelect,
}: {
  current: WizardStep;
  /** The furthest step reachable with what's been filled in so far. */
  furthest: WizardStep;
  onSelect: (step: WizardStep) => void;
}) {
  return (
    <ol className="flex flex-wrap items-center gap-x-8 gap-y-3">
      {WIZARD_STEPS.map(({ step, title, hint }) => {
        const isCurrent = step === current;
        const isDone = step < current;
        const reachable = step <= furthest;
        return (
          <li key={step}>
            <button
              type="button"
              disabled={!reachable}
              aria-current={isCurrent ? "step" : undefined}
              onClick={() => reachable && onSelect(step)}
              className={cn(
                "flex items-center gap-3 text-left transition-opacity",
                reachable ? "hover:opacity-80" : "cursor-not-allowed opacity-60",
              )}
            >
              <span
                className={cn(
                  "flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-sm font-semibold transition-colors",
                  isCurrent
                    ? "bg-[#0B9B63] text-white"
                    : isDone
                      ? "bg-success/20 text-success"
                      : "bg-muted text-muted-foreground",
                )}
              >
                {isDone ? <Check className="h-4 w-4" strokeWidth={3} aria-hidden /> : step}
              </span>
              <span className="min-w-0">
                <span
                  className={cn(
                    "block whitespace-nowrap text-sm font-semibold",
                    isCurrent || isDone ? "text-black dark:text-foreground" : "text-muted-foreground",
                  )}
                >
                  {title}
                </span>
                <span className="block whitespace-nowrap text-xs text-muted-foreground">{hint}</span>
              </span>
            </button>
          </li>
        );
      })}
    </ol>
  );
}
