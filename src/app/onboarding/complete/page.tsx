import type { Metadata } from "next";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Setup Complete — ${PRODUCT_NAME}`,
};

export default function OnboardingCompletePage() {
  return (
    <div className="space-y-2 text-center">
      <h1 className="text-2xl font-semibold tracking-tight">You&apos;re all set!</h1>
      <p className="text-sm text-muted-foreground">
        Your facility, sports, courts, operating hours, and pricing are saved. The dashboard is
        being built next.
      </p>
    </div>
  );
}