// src/app/onboarding/facility/page.tsx
import type { Metadata } from "next";
import { FacilityDetailsForm } from "@/features/onboarding/components/facility-details-form";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Facility Details — ${PRODUCT_NAME}`,
};

export default function FacilityDetailsPage() {
  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">
          Let&apos;s set up your facility
        </h1>
        <p className="mt-2 text-sm text-muted-foreground sm:text-base">
          Tell us a little about your facility. You can update these details later.
        </p>
      </div>

      <FacilityDetailsForm />
    </div>
  );
}
