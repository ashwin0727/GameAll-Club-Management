import { Check } from "lucide-react";
import { cn } from "@/lib/utils";

const STEPS = ["Facility Details", "Sports", "Courts", "Operating Hours", "Pricing", "Setup"];

export function OnboardingProgress({ currentStep }: { currentStep: number }) {
  return (
    <div role="status" aria-label={`Step ${currentStep} of ${STEPS.length}`}>
      {/* Desktop: horizontal stepper */}
      <ol className="hidden items-center gap-2 md:flex">
        {STEPS.map((label, index) => {
          const step = index + 1;
          const state = step < currentStep ? "done" : step === currentStep ? "current" : "upcoming";

          return (
            <li key={label} className="flex items-center gap-2">
              {index > 0 && <span className="h-px w-6 bg-border" aria-hidden="true" />}
              <span
                aria-current={state === "current" ? "step" : undefined}
                className={cn(
                  "flex items-center gap-1.5 text-xs font-medium",
                  state === "current" && "text-primary",
                  state === "done" && "text-foreground",
                  state === "upcoming" && "text-muted-foreground",
                )}
              >
                <span
                  className={cn(
                    "flex h-4 w-4 items-center justify-center rounded-full border text-[10px]",
                    state === "current" && "border-primary bg-primary text-primary-foreground",
                    state === "done" && "border-foreground bg-foreground text-background",
                    state === "upcoming" && "border-muted-foreground",
                  )}
                >
                  {state === "done" ? <Check className="h-2.5 w-2.5" aria-hidden="true" /> : null}
                </span>
                {label}
              </span>
            </li>
          );
        })}
      </ol>

      {/* Mobile: compact bar */}
      <div className="space-y-2 md:hidden">
        <p className="text-xs font-medium text-muted-foreground">
          Step {currentStep} of {STEPS.length}
        </p>
        <div className="h-1.5 w-full overflow-hidden rounded-full bg-secondary">
          <div
            className="h-full rounded-full bg-primary transition-all"
            style={{ width: `${(currentStep / STEPS.length) * 100}%` }}
          />
        </div>
        <p aria-current="step" className="text-sm font-semibold text-foreground">
          {STEPS[currentStep - 1]}
        </p>
      </div>
    </div>
  );
}
