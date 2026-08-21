// src/app/onboarding/courts/page.tsx
import type { Metadata } from "next";
import { CourtsSetupForm } from "@/features/courts-setup/components/courts-setup-form";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Courts & Turfs Setup — ${PRODUCT_NAME}`,
};

export default function CourtsSetupPage() {
  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">
          Set up your courts &amp; turfs
        </h1>
        <p className="mt-2 text-sm text-muted-foreground sm:text-base">
          Add the playing areas available at your facility.
        </p>
      </div>

      <CourtsSetupForm />
    </div>
  );
}