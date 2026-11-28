"use client";

import { useEffect, useMemo } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { ArrowLeft, ArrowRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import { PermissionDenied } from "@/features/staff/components/permission-denied";
import { useFacilitySportOptions } from "@/features/facility/hooks/use-facility-sport-options";
import { PageHeader, TableSkeleton } from "@/features/coaching/components/shared";
import { CoachAddedContent } from "@/features/coaching/components/coach-added-content";
import { IdentityStep } from "@/features/coaching/components/coach-onboarding-step-identity";
import { ExpertiseStep } from "@/features/coaching/components/coach-onboarding-step-expertise";
import { ServicesStep } from "@/features/coaching/components/coach-onboarding-step-services";
import { PayoutStep } from "@/features/coaching/components/coach-onboarding-step-payout";
import { ReviewStep } from "@/features/coaching/components/coach-onboarding-step-review";
import { useCoachOnboarding, type OnboardingStep } from "@/features/coaching/components/use-coach-onboarding";
import { COACH_ONBOARDING_STEPS } from "@/features/coaching/types";

const STEP_SUBTITLE: Record<OnboardingStep, string> = {
  1: "Who the coach is and how students will see them.",
  2: "What they teach and the credentials behind it.",
  3: "How they coach and what they charge.",
  4: "Where their earnings are paid. You can finish this later.",
  5: "Check everything and confirm the agreements.",
};

/**
 * Add Coach — a 5-step onboarding on its own page (one step visible at a time). Step 1 saves a draft coach, steps 2-4 save as
 * you go, step 5 activates the coach. `?coach=<id>` resumes a draft at the step it stopped on.
 */
export function CoachOnboardingPage() {
  const perms = usePermissionContext();
  const router = useRouter();
  const params = useSearchParams();
  const resumeId = params.get("coach");
  const facilityId = perms?.facilityId ?? null;
  const stepParam = Number(params.get("step"));
  const requestedStep = (Number.isInteger(stepParam) && stepParam >= 1 && stepParam <= 5 ? stepParam : null) as OnboardingStep | null;
  const form = useCoachOnboarding(facilityId, resumeId, requestedStep);
  const sportsQuery = useFacilitySportOptions(facilityId ?? undefined);
  const sportNames = useMemo(() => Object.fromEntries((sportsQuery.data ?? []).map((s) => [s.facilitySportId, s.name])), [sportsQuery.data]);

  // Keep the address bar on the draft + step so a reload or a shared link reopens the same place.
  useEffect(() => {
    if (!form.coachId || form.completed) return;
    window.history.replaceState(null, "", `/coaching/coaches/add?coach=${form.coachId}&step=${form.step}`);
  }, [form.coachId, form.step, form.completed]);

  if (!perms?.can("COACHING_MANAGE_COACHES")) {
    return <PermissionDenied message="You don't have permission to manage coaches." />;
  }

  if (form.completed) {
    return (
      <div className="space-y-4">
        <Card className="p-6">
          <CoachAddedContent coachId={form.completed.coachId} name={form.completed.name} credentials={form.credentials} onNavigate={(href) => router.push(href)} />
          {!form.credentials && (
            <p className="mt-4 text-center text-xs text-muted-foreground">
              Sign-in details are only shown when the account is created. Lost the password? Open the person under Staff and choose Reset Password.
            </p>
          )}
          <div className="mt-6 flex items-center justify-between border-t border-border pt-4">
            <Button type="button" variant="outline" onClick={() => (window.location.href = "/coaching/coaches/add")}>
              Add Another Coach
            </Button>
            <Button onClick={() => router.push("/coaching")}>Go to Coaches List</Button>
          </div>
        </Card>
      </div>
    );
  }

  const step = form.step;
  const title = COACH_ONBOARDING_STEPS[step - 1];
  const valid = form.stepValid(step);

  async function exitWithDraft() {
    const ok = await form.saveDraft();
    if (ok) router.push("/coaching/coaches");
  }

  async function next() {
    await form.saveAndContinue();
  }

  return (
    <div className="space-y-4">
      <PageHeader
        title="Add Coach"
        subtitle="Add a new coach to your club. They will be able to take coaching sessions and manage their schedule."
      />

      <Card className="space-y-6 p-6">
        <div className="flex items-start gap-3">
          <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-success/15 text-sm font-semibold text-success">
            {step}
          </span>
          <div>
            <h3 className="text-sm font-semibold">
              Step {step} of 5 · {title}
            </h3>
            <p className="text-xs text-muted-foreground">{STEP_SUBTITLE[step]}</p>
          </div>
        </div>

        {form.loading ? (
          <TableSkeleton rows={5} />
        ) : (
          <>
            {step === 1 && <IdentityStep form={form} />}
            {step === 2 && <ExpertiseStep form={form} facilityId={facilityId} />}
            {step === 3 && <ServicesStep form={form} />}
            {step === 4 && <PayoutStep form={form} />}
            {step === 5 && <ReviewStep form={form} sportNames={sportNames} />}
          </>
        )}

        {form.error && (
          <p role="alert" className="text-sm text-destructive">
            {form.error}
          </p>
        )}

        <div className="flex flex-wrap items-center justify-between gap-2 border-t border-border pt-4">
          <div className="flex items-center gap-2">
            {step === 1 ? (
              <Button type="button" variant="outline" onClick={() => router.push("/coaching/coaches")}>
                Cancel
              </Button>
            ) : (
              <Button type="button" variant="outline" disabled={form.busy} onClick={() => form.setStep((step - 1) as OnboardingStep)}>
                <ArrowLeft className="h-4 w-4" aria-hidden /> Back
              </Button>
            )}
            {step < 5 && (
              <Button type="button" variant="ghost" disabled={form.busy || form.loading} onClick={() => void exitWithDraft()}>
                Save draft &amp; exit
              </Button>
            )}
          </div>
          <div className="flex items-center gap-2">
            {step === 4 && (
              <Button type="button" variant="outline" disabled={form.busy} onClick={form.skipPayout}>
                Finish later
              </Button>
            )}
            {step < 5 ? (
              <Button type="button" disabled={form.busy || form.loading || (!valid && !(step === 4 && !form.canManagePayouts))} onClick={() => (step === 4 && !form.canManagePayouts ? form.skipPayout() : void next())}>
                {form.busy ? form.stage || "Saving…" : "Save & continue"} {!form.busy && <ArrowRight className="h-4 w-4" aria-hidden />}
              </Button>
            ) : (
              <Button type="button" disabled={form.busy || !valid} onClick={() => void form.complete()}>
                {form.busy ? form.stage || "Submitting…" : "Submit & Activate Coach"}
              </Button>
            )}
          </div>
        </div>
      </Card>
    </div>
  );
}
