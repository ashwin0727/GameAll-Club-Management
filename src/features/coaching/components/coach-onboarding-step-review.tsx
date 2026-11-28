"use client";

import { Pencil } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import type { CoachOnboardingState, OnboardingStep } from "@/features/coaching/components/use-coach-onboarding";
import { COACH_ONBOARDING_STEPS } from "@/features/coaching/types";
import { SESSION_FORMAT_OPTIONS } from "@/features/coaching/components/coach-onboarding-field";

function Section({ n, title, onEdit, children }: { n: number; title: string; onEdit: () => void; children: React.ReactNode }) {
  return (
    <Card className="p-4">
      <div className="mb-3 flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-primary/15 text-xs font-bold text-primary">{n}</span>
          <h3 className="text-sm font-bold">{title}</h3>
        </div>
        <button type="button" onClick={onEdit} className="flex h-8 items-center gap-1.5 rounded-lg border border-input px-2.5 text-xs font-semibold transition-colors hover:bg-accent">
          <Pencil className="h-3.5 w-3.5" aria-hidden /> Edit
        </button>
      </div>
      <dl className="space-y-1.5 text-sm">{children}</dl>
    </Card>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex gap-2">
      <dt className="w-40 shrink-0 text-muted-foreground">{label}</dt>
      <dd className="min-w-0 flex-1 break-words font-medium">{value || "—"}</dd>
    </div>
  );
}

const AGREEMENTS: { key: "terms" | "ethics" | "privacy" | "commission"; label: string }[] = [
  { key: "terms", label: "Terms of service — I confirm the coach has agreed to the platform's terms of service." },
  { key: "ethics", label: "Coach code of ethics — I confirm the coach has agreed to the code of ethics." },
  { key: "privacy", label: "Privacy & confidentiality — I confirm the coach has agreed to keep student information confidential." },
  { key: "commission", label: "Platform commission — I confirm the coach has acknowledged the platform commission fee." },
];

/** Step 5 — Review & Agreements. */
export function ReviewStep({ form, sportNames }: { form: CoachOnboardingState; sportNames: Record<string, string> }) {
  const d = form.draft;
  const go = (s: OnboardingStep) => form.setStep(s);
  const formats = d.sessionFormats.map((f) => SESSION_FORMAT_OPTIONS.find((o) => o.value === f)?.label ?? f).join(", ");
  const inr = (v: string) => (v ? `₹${Number(v).toLocaleString("en-IN")}` : "");
  const kycDone = form.payoutStatus === "COMPLETE";

  return (
    <div className="space-y-4">
      <Section n={1} title={COACH_ONBOARDING_STEPS[0]} onEdit={() => go(1)}>
        <Row label="Display name" value={d.displayName} />
        <Row label="Location" value={d.location} />
        <Row label="Timezone" value={d.timezone} />
        <Row label="Languages" value={d.languages.join(", ")} />
      </Section>
      <Section n={2} title={COACH_ONBOARDING_STEPS[1]} onEdit={() => go(2)}>
        <Row label="Niche" value={d.niche} />
        <Row label="Sports" value={d.sportIds.map((id) => sportNames[id] ?? "Sport").join(", ")} />
        <Row label="Levels" value={d.expertiseLevels.join(", ")} />
        <Row label="Experience" value={d.experience ? `${d.experience} years` : ""} />
        <Row label="Audience" value={d.targetAudience.join(", ")} />
        <Row label="Certificates" value={d.certificates.map((c) => c.name).join(", ")} />
      </Section>
      <Section n={3} title={COACH_ONBOARDING_STEPS[2]} onEdit={() => go(3)}>
        <Row label="Formats" value={formats} />
        <Row label="Durations" value={d.sessionDurations.map((m) => `${m} min`).join(", ")} />
        <Row label="Per session" value={inr(d.perSessionRate)} />
        <Row label="Weekly" value={inr(d.weeklyRate)} />
        <Row label="Monthly" value={inr(d.monthlyRate)} />
      </Section>
      <Section n={4} title={COACH_ONBOARDING_STEPS[3]} onEdit={() => go(4)}>
        <div className="flex items-center gap-2">
          <Badge variant={kycDone ? "success" : "warning"}>{kycDone ? "KYC complete" : "KYC pending"}</Badge>
          <span className="text-muted-foreground">{kycDone ? "Payout details are saved (shown masked)." : "You can add payout details later from the coach's profile."}</span>
        </div>
      </Section>

      <Card className="space-y-3 p-4">
        <h3 className="text-sm font-bold">Agreements</h3>
        {AGREEMENTS.map((a) => (
          <label key={a.key} className="flex cursor-pointer items-start gap-2.5 text-sm">
            <input
              type="checkbox"
              className="mt-1 h-4 w-4"
              checked={d.agreements[a.key]}
              onChange={(e) => form.patch({ agreements: { ...d.agreements, [a.key]: e.target.checked } })}
            />
            <span>{a.label}</span>
          </label>
        ))}
      </Card>
    </div>
  );
}
