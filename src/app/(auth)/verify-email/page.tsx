import { Suspense } from "react";
import type { Metadata } from "next";
import { AuthCard } from "@/features/auth/components/auth-card";
import { VerifyEmailPanel } from "@/features/auth/components/verify-email-panel";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Verify your email — ${PRODUCT_NAME}`,
};

export default function VerifyEmailPage() {
  return (
    <AuthCard title="Verify your email">
      <Suspense fallback={<div className="h-[380px]" />}>
        <VerifyEmailPanel />
      </Suspense>
    </AuthCard>
  );
}