// src/app/onboarding/pricing/page.tsx
import type { Metadata } from "next";
import { PricingForm } from "@/features/pricing/components/pricing-form";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Pricing — ${PRODUCT_NAME}`,
};

export default function PricingPage() {
  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">Set your pricing</h1>
        <p className="mt-2 text-sm text-muted-foreground sm:text-base">
          Define how much customers pay to use your courts and turfs.
        </p>
      </div>

      <PricingForm />
    </div>
  );
}