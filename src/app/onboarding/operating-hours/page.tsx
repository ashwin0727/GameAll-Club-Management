// src/app/onboarding/operating-hours/page.tsx
import type { Metadata } from "next";
import { OperatingHoursForm } from "@/features/operating-hours/components/operating-hours-form";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Operating Hours — ${PRODUCT_NAME}`,
};

export default function OperatingHoursPage() {
  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">Set your operating hours</h1>
        <p className="mt-2 text-sm text-muted-foreground sm:text-base">
          Choose when your facility is open for bookings and activities.
        </p>
      </div>

      <OperatingHoursForm />
    </div>
  );
}