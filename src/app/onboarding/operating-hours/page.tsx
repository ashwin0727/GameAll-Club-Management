// src/app/onboarding/operating-hours/page.tsx
import type { Metadata } from "next";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Operating Hours — ${PRODUCT_NAME}`,
};

export default function OperatingHoursPlaceholderPage() {
  return (
    <div className="space-y-2 text-center">
      <h1 className="text-2xl font-semibold tracking-tight">Operating Hours — Coming Next</h1>
      <p className="text-sm text-muted-foreground">
        Great work! Next you&apos;ll set your facility&apos;s operating hours. This step is being
        built next.
      </p>
    </div>
  );
}