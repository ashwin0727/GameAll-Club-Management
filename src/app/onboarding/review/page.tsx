// src/app/onboarding/review/page.tsx
import type { Metadata } from "next";
import { SetupReviewPage } from "@/features/setup-review/components/setup-review-page";

export const metadata: Metadata = {
  title: `Setup Under Review`,
};

export default function Page() {
  return <SetupReviewPage />;
}
