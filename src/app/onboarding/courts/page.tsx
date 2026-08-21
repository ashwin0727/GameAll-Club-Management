// src/app/onboarding/courts/page.tsx
import type { Metadata } from "next";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Courts Setup — ${PRODUCT_NAME}`,
};

export default function CourtsSetupPlaceholderPage() {
  return (
    <div className="space-y-2 text-center">
      <h1 className="text-2xl font-semibold tracking-tight">Courts Setup — Coming Next</h1>
      <p className="text-sm text-muted-foreground">
        Nice work! Next you&apos;ll set up the courts and turfs for each sport. This step is being built next.
      </p>
    </div>
  );
}