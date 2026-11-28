import type { Metadata } from "next";
import { Suspense } from "react";
import { CoachOnboardingPage } from "@/features/coaching/components/coach-onboarding-page";

export const metadata: Metadata = { title: `Add Coach` };

export default function Page() {
  return (
    <Suspense fallback={null}>
      <CoachOnboardingPage />
    </Suspense>
  );
}
