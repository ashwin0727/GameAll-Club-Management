"use client";

import { useRef, useState } from "react";
import { FileCheck2, Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Chip, NO_SPINNER_INPUT, blurOnWheel } from "@/features/coaching/components/shared";
import { AUDIENCE_OPTIONS, OnboardingField } from "@/features/coaching/components/coach-onboarding-field";
import type { CoachOnboardingState } from "@/features/coaching/components/use-coach-onboarding";
import { CERTIFICATE_ACCEPT } from "@/features/coaching/coach-onboarding-validation";
import { useFacilitySportOptions } from "@/features/facility/hooks/use-facility-sport-options";
import { COACH_EXPERTISE_LEVELS } from "@/features/coaching/types";

/** Step 2 — Expertise & Credentials. */
export function ExpertiseStep({ form, facilityId }: { form: CoachOnboardingState; facilityId: string | null }) {
  const { draft } = form;
  const sportsQuery = useFacilitySportOptions(facilityId ?? undefined);
  const [tag, setTag] = useState("");
  const fileRefs = useRef<(HTMLInputElement | null)[]>([]);

  function addTag() {
    const v = tag.trim();
    if (!v || draft.subSpecialties.includes(v)) return;
    form.patch({ subSpecialties: [...draft.subSpecialties, v] });
    setTag("");
  }

  return (
    <div className="space-y-5">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <OnboardingField label="Coaching Niche" required htmlFor="ob-niche" hint="The main thing this coach teaches.">
          <Input id="ob-niche" value={draft.niche} onChange={(e) => form.patch({ niche: e.target.value })} placeholder="e.g. Badminton – singles technique" />
        </OnboardingField>
        <OnboardingField label="Years of Experience" htmlFor="ob-exp" error={draft.experience.trim() !== "" && Number(draft.experience) < 0 ? "Cannot be negative." : null}>
          <Input id="ob-exp" type="number" min="0" step="0.5" value={draft.experience} onChange={(e) => form.patch({ experience: e.target.value })} onWheel={blurOnWheel} className={NO_SPINNER_INPUT} />
        </OnboardingField>
      </div>

      <OnboardingField label="Sports" required>
        <div className="flex flex-wrap gap-2">
          {(sportsQuery.data ?? []).map((s) => (
            <Chip key={s.facilitySportId} label={s.name} selected={draft.sportIds.includes(s.facilitySportId)} onToggle={() => form.patch({ sportIds: form.toggle(draft.sportIds, s.facilitySportId) })} />
          ))}
        </div>
      </OnboardingField>

      <OnboardingField label="Expertise Level" required>
        <div className="flex flex-wrap gap-2">
          {COACH_EXPERTISE_LEVELS.map((l) => (
            <Chip key={l} label={l} selected={draft.expertiseLevels.includes(l)} onToggle={() => form.patch({ expertiseLevels: form.toggle(draft.expertiseLevels, l) })} />
          ))}
        </div>
      </OnboardingField>

      <OnboardingField label="Sub-specialties (Optional)" hint="Type one and press Enter, e.g. Footwork, Smash, Net play.">
        <div className="flex gap-2">
          <Input
            value={tag}
            onChange={(e) => setTag(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                e.preventDefault();
                addTag();
              }
            }}
            placeholder="Add a sub-specialty"
          />
          <Button type="button" variant="outline" onClick={addTag} disabled={!tag.trim()}>
            Add
          </Button>
        </div>
        {draft.subSpecialties.length > 0 && (
          <div className="mt-2 flex flex-wrap gap-2">
            {draft.subSpecialties.map((t) => (
              <Chip key={t} label={t} selected onToggle={() => form.patch({ subSpecialties: draft.subSpecialties.filter((x) => x !== t) })} />
            ))}
          </div>
        )}
      </OnboardingField>

      <OnboardingField label="Target Audience">
        <div className="flex flex-wrap gap-2">
          {AUDIENCE_OPTIONS.map((a) => (
            <Chip key={a} label={a} selected={draft.targetAudience.includes(a)} onToggle={() => form.patch({ targetAudience: form.toggle(draft.targetAudience, a) })} />
          ))}
        </div>
      </OnboardingField>

      <OnboardingField label="Coaching Methodology (Optional)" htmlFor="ob-method">
        <Textarea id="ob-method" rows={3} value={draft.methodology} onChange={(e) => form.patch({ methodology: e.target.value })} placeholder="How the coach structures sessions and tracks progress…" />
      </OnboardingField>

      <section className="space-y-2">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm font-medium">Certifications &amp; Credentials</p>
            <p className="text-xs text-muted-foreground">JPG, PNG, WEBP or PDF, up to 5MB each. Files are stored privately.</p>
          </div>
          <Button type="button" size="sm" variant="outline" onClick={() => form.patch({ certificates: [...draft.certificates, { name: "", issuer: "", year: null, path: "" }] })}>
            <Plus className="h-4 w-4" aria-hidden /> Add
          </Button>
        </div>
        {draft.certificates.length === 0 && <p className="text-sm text-muted-foreground">No certificates added yet.</p>}
        {draft.certificates.map((c, i) => (
          <div key={i} className="grid grid-cols-1 gap-3 rounded-lg border border-border p-3 sm:grid-cols-2">
            <OnboardingField label="Certificate name" required className="sm:col-span-2">
              <Input aria-label="Certificate name" value={c.name} placeholder="e.g. BWF Level 1" onChange={(e) => form.patch({ certificates: draft.certificates.map((x, j) => (j === i ? { ...x, name: e.target.value } : x)) })} />
            </OnboardingField>
            <OnboardingField label="Issued by">
              <Input aria-label="Issued by" value={c.issuer} placeholder="Issuing body" onChange={(e) => form.patch({ certificates: draft.certificates.map((x, j) => (j === i ? { ...x, issuer: e.target.value } : x)) })} />
            </OnboardingField>
            <OnboardingField label="Year">
              <Input
                aria-label="Year"
                inputMode="numeric"
                maxLength={4}
                value={c.year ?? ""}
                placeholder="e.g. 2022"
                onChange={(e) => {
                  const y = e.target.value.replace(/\D/g, "").slice(0, 4);
                  form.patch({ certificates: draft.certificates.map((x, j) => (j === i ? { ...x, year: y ? Number(y) : null } : x)) });
                }}
              />
            </OnboardingField>
            <div className="flex flex-wrap items-center justify-between gap-2 sm:col-span-2">
              <input
                ref={(el) => {
                  fileRefs.current[i] = el;
                }}
                type="file"
                accept={CERTIFICATE_ACCEPT.join(",")}
                className="hidden"
                onChange={(e) => {
                  void form.uploadCertificate(i, e.target.files?.[0]);
                  e.target.value = "";
                }}
              />
              <Button type="button" size="sm" variant="outline" disabled={!form.coachId || form.busy} onClick={() => fileRefs.current[i]?.click()}>
                {c.path ? <FileCheck2 className="h-4 w-4 text-success" aria-hidden /> : null}
                {c.path ? "Replace file" : "Upload file"}
              </Button>
              <Button type="button" size="icon" variant="ghost" aria-label="Remove certificate" onClick={() => form.patch({ certificates: draft.certificates.filter((_, j) => j !== i) })}>
                <Trash2 className="h-4 w-4" aria-hidden />
              </Button>
            </div>
          </div>
        ))}
      </section>
    </div>
  );
}
