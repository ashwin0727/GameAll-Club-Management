"use client";

import { Label } from "@/components/ui/label";

/** Label + control + optional hint/error — the one field wrapper every onboarding step uses. */
export function OnboardingField({
  label,
  hint,
  error,
  required,
  htmlFor,
  className,
  children,
}: {
  label: string;
  hint?: string;
  error?: string | null;
  required?: boolean;
  htmlFor?: string;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <div className={`space-y-1.5 ${className ?? ""}`}>
      <Label htmlFor={htmlFor}>
        {label}
        {required && <span className="text-destructive"> *</span>}
      </Label>
      {children}
      {error ? <p className="text-xs text-destructive">{error}</p> : hint ? <p className="text-xs text-muted-foreground">{hint}</p> : null}
    </div>
  );
}

export const LANGUAGE_OPTIONS = ["English", "Hindi", "Tamil", "Telugu", "Kannada", "Malayalam", "Marathi", "Bengali", "Gujarati", "Punjabi"];
export const TIMEZONE_OPTIONS = [
  { value: "Asia/Kolkata", label: "India (IST, UTC+5:30)" },
  { value: "Asia/Dubai", label: "Dubai (GST, UTC+4)" },
  { value: "Asia/Singapore", label: "Singapore (SGT, UTC+8)" },
  { value: "Europe/London", label: "London (UK)" },
  { value: "America/New_York", label: "New York (US Eastern)" },
  { value: "Australia/Sydney", label: "Sydney (AEST)" },
];
export const AUDIENCE_OPTIONS = ["Kids", "Teens", "Adults", "Seniors", "Beginners", "Competitive players"];
export const SESSION_FORMAT_OPTIONS = [
  { value: "ONE_TO_ONE" as const, label: "1:1 sessions", hint: "One coach, one student" },
  { value: "GROUP" as const, label: "Group sessions", hint: "Several students together" },
  { value: "ASYNC" as const, label: "Async / video feedback", hint: "Reviews without a live session" },
];
export const SESSION_DURATION_OPTIONS = [30, 45, 60, 90, 120];
export const PAYOUT_FREQUENCY_OPTIONS = [
  { value: "WEEKLY" as const, label: "Weekly" },
  { value: "BIWEEKLY" as const, label: "Every 2 weeks" },
  { value: "MONTHLY" as const, label: "Monthly" },
];
