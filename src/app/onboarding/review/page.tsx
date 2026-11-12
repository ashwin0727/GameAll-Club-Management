// src/app/onboarding/review/page.tsx
import type { Metadata } from "next";
import { SetupReviewPage } from "@/features/setup-review/components/setup-review-page";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Setup Under Review — ${PRODUCT_NAME}`,
};

export default function Page() {
  return <SetupReviewPage />;
}
