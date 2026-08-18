"use client";

import { cn } from "@/lib/utils";
import { evaluatePasswordStrength } from "@/features/auth/validation";

const SEGMENT_TONE: Record<string, string> = {
  weak: "bg-destructive",
  medium: "bg-warning",
  strong: "bg-success",
};

const LABEL_TONE: Record<string, string> = {
  weak: "text-destructive",
  medium: "text-warning",
  strong: "text-success",
};

/**
 * Three-segment strength meter. Advisory only — the submit rule is the 8
 * character minimum, not the score. The word ("Weak"/"Medium"/"Strong") carries
 * the meaning so the bars are never the sole indicator.
 */
export function PasswordStrengthMeter({ password }: { password: string }) {
  const { strength, score, label, hint } = evaluatePasswordStrength(password);
  if (strength === "empty") return null;

  return (
    <div className="space-y-1.5 pt-0.5">
      <div className="flex items-center gap-2">
        <div className="flex flex-1 gap-1" aria-hidden="true">
          {[1, 2, 3].map((segment) => (
            <span
              key={segment}
              className={cn(
                "h-1 flex-1 rounded-full transition-colors",
                segment <= score ? SEGMENT_TONE[strength] : "bg-border",
              )}
            />
          ))}
        </div>
        <span className={cn("text-xs font-medium", LABEL_TONE[strength])}>{label}</span>
      </div>
      {/* Polite: strength updates as the user types and must not interrupt. */}
      <p className="text-xs text-muted-foreground" aria-live="polite">
        {hint ?? "Strong password — good to go."}
      </p>
    </div>
  );
}