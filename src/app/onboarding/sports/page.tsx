// src/app/onboarding/sports/page.tsx
import type { Metadata } from "next";
import { SportsSetupForm } from "@/features/sports-setup/components/sports-setup-form";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Sports Setup — ${PRODUCT_NAME}`,
};

export default function SportsSetupPage() {
  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">What sports do you operate?</h1>
        <p className="mt-2 text-sm text-muted-foreground sm:text-base">
          Select the sports available at your facility. You can add or remove sports later.
        </p>
      </div>

      <SportsSetupForm />
    </div>
  );
}