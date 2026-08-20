// src/app/onboarding/sports/page.tsx
import type { Metadata } from "next";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Sports Setup — ${PRODUCT_NAME}`,
};

export default function SportsSetupPlaceholderPage() {
  return (
    <div className="space-y-2 text-center">
      <h1 className="text-2xl font-semibold tracking-tight">Sports Setup — Coming Next</h1>
      <p className="text-sm text-muted-foreground">
        Great! Now let&apos;s add the sports you operate. This step is being built next.
      </p>
    </div>
  );
}
