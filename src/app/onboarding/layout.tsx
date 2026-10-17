// src/app/onboarding/layout.tsx
"use client";

import { useEffect } from "react";
import { usePathname, useRouter } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { OnboardingProgress } from "@/features/onboarding/components/onboarding-progress";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";

const PREVIOUS_STEP_PATH: Record<string, string> = {
  "/onboarding/sports": "/onboarding/facility",
  "/onboarding/courts": "/onboarding/sports",
  "/onboarding/operating-hours": "/onboarding/courts",
  "/onboarding/pricing": "/onboarding/operating-hours",
  "/onboarding/complete": "/onboarding/pricing",
};

export default function OnboardingLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const currentStep = useOnboardingStore((s) => s.currentStep);
  const previousStepPath = PREVIOUS_STEP_PATH[pathname ?? ""] ?? "/dashboard";

  // The store uses skipHydration so the client's first render matches the
  // server's default (empty/step-1) HTML. Rehydrate here too — not every
  // onboarding step (e.g. the /onboarding/courts placeholder) mounts a form
  // that would otherwise trigger this, and OnboardingProgress's currentStep
  // needs the real persisted value once it's safe to show it.
  useEffect(() => {
    useOnboardingStore.persist.rehydrate();
  }, []);

  // Back always goes straight to the previous step — progress is saved as you go, so there is nothing to confirm.
  function handleBack() {
    router.replace(previousStepPath);
  }

  return (
    <div className="min-h-[100dvh] bg-background">
      <header className="border-b border-border">
        <div className="mx-auto flex max-w-[1000px] items-center justify-between px-5 py-4 sm:px-8">
          <button
            type="button"
            onClick={handleBack}
            className="flex items-center gap-1.5 text-sm font-medium text-muted-foreground transition-colors hover:text-foreground"
          >
            <ArrowLeft className="h-4 w-4" aria-hidden="true" />
            Back
          </button>
          <OnboardingProgress currentStep={currentStep} />
        </div>
      </header>

      <main className="mx-auto max-w-[1000px] px-5 py-10 sm:px-8">{children}</main>

    </div>
  );
}
