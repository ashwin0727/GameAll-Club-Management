// src/app/onboarding/layout.tsx
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { OnboardingProgress } from "@/features/onboarding/components/onboarding-progress";
import { LeaveConfirmDialog } from "@/features/onboarding/components/leave-confirm-dialog";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";

export default function OnboardingLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const currentStep = useOnboardingStore((s) => s.currentStep);
  const draft = useOnboardingStore((s) => s.draft);
  const [confirmOpen, setConfirmOpen] = useState(false);

  const hasUnsavedProgress = Object.values(draft).some((value) => Boolean(value));

  function handleBack() {
    if (hasUnsavedProgress) {
      setConfirmOpen(true);
      return;
    }
    router.replace("/login");
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

      <LeaveConfirmDialog
        open={confirmOpen}
        onOpenChange={setConfirmOpen}
        onLeave={() => router.replace("/login")}
      />
    </div>
  );
}
