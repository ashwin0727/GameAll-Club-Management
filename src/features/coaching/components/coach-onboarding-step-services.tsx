"use client";

import { Input } from "@/components/ui/input";
import { Chip, NO_SPINNER_INPUT, blurOnWheel } from "@/features/coaching/components/shared";
import { OnboardingField, SESSION_DURATION_OPTIONS, SESSION_FORMAT_OPTIONS } from "@/features/coaching/components/coach-onboarding-field";
import type { CoachOnboardingState, OnboardingDraft } from "@/features/coaching/components/use-coach-onboarding";
import { isValidRupees } from "@/features/coaching/coach-onboarding-validation";
import { cn } from "@/lib/utils";

type RateKey = "perSessionRate" | "weeklyRate" | "monthlyRate";

const RATE_FIELDS: { key: RateKey; id: string; label: string; placeholder: string }[] = [
  { key: "perSessionRate", id: "ob-rate-session", label: "Per Session Coaching Amount (₹)", placeholder: "e.g. 500" },
  { key: "weeklyRate", id: "ob-rate-week", label: "Weekly Session Coaching Amount (₹)", placeholder: "e.g. 2000" },
  { key: "monthlyRate", id: "ob-rate-month", label: "Monthly Session Coaching Amount (₹)", placeholder: "e.g. 7000" },
];

/** Step 3 — Sessions & Pricing. (Weekly availability is edited later from the coach's profile.) */
export function ServicesStep({ form }: { form: CoachOnboardingState }) {
  const { draft } = form;

  return (
    <div className="space-y-5">
      <OnboardingField label="Session Formats" required>
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
          {SESSION_FORMAT_OPTIONS.map((f) => {
            const on = draft.sessionFormats.includes(f.value);
            return (
              <button
                key={f.value}
                type="button"
                aria-pressed={on}
                onClick={() => form.patch({ sessionFormats: form.toggle(draft.sessionFormats, f.value) })}
                className={cn("rounded-lg border p-3 text-left text-sm transition-colors", on ? "border-primary bg-primary/10" : "border-border hover:bg-accent")}
              >
                <span className="block font-medium">{f.label}</span>
                <span className="text-xs text-muted-foreground">{f.hint}</span>
              </button>
            );
          })}
        </div>
      </OnboardingField>

      <OnboardingField label="Session Durations" required>
        <div className="flex flex-wrap gap-2">
          {SESSION_DURATION_OPTIONS.map((m) => (
            <Chip key={m} label={`${m} min`} selected={draft.sessionDurations.includes(m)} onToggle={() => form.patch({ sessionDurations: form.toggle(draft.sessionDurations, m).sort((a, b) => a - b) })} />
          ))}
        </div>
      </OnboardingField>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        {RATE_FIELDS.map((r) => {
          const value = draft[r.key as keyof OnboardingDraft] as string;
          return (
            <OnboardingField key={r.key} label={r.label} htmlFor={r.id} error={value !== "" && !isValidRupees(value) ? "Enter a whole number of rupees greater than 0." : null}>
              <Input
                id={r.id}
                inputMode="numeric"
                value={value}
                onChange={(e) => form.patch({ [r.key]: e.target.value.replace(/[^\d]/g, "") })}
                onWheel={blurOnWheel}
                className={NO_SPINNER_INPUT}
                placeholder={r.placeholder}
              />
            </OnboardingField>
          );
        })}
      </div>
    </div>
  );
}
