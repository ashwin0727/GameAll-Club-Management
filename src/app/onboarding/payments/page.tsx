// src/app/onboarding/payments/page.tsx
import type { Metadata } from "next";
import { PayoutSetupForm } from "@/features/onboarding/components/payout-setup-form";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Payout Details — ${PRODUCT_NAME}`,
};

export default function PaymentsPage() {
  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">Add Your Payout Details</h1>
        <p className="mt-2 text-sm text-muted-foreground sm:text-base">
          Tell us where to send the money you collect. You&apos;ll need this before you can start using your dashboard.
        </p>
      </div>

      <PayoutSetupForm />
    </div>
  );
}
